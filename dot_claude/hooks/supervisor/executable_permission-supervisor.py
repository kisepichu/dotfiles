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
    # Regexes (matched against tool_name + serialized tool_input). Any match
    # is approved before consulting the backend. Hard escalation still wins,
    # so secret material is escalated even though Read is broadly allowed here.
    "always_allow_patterns": [
        r"\bpython3\s+(~|\$HOME|/Users/[^/\s]+|/home/[^/\s]+)/\.claude/skills/pr-review/scripts/[A-Za-z0-9_-]+\.py(\s|$)",
        # Read tool: inspecting any single file is safe; secrets are caught by
        # the hard rules above this in the pipeline. Fixes "look at repos/..."
        # being denied as out-of-scope.
        r"^Read\n",
        # Read-only Bash with no command chaining/redirection that could hide a
        # side effect. Only a single safe command (optionally with args/pipes
        # between read-only tools) is auto-allowed.
        r"^Bash\n.*\"command\":\s*\"\s*(cat|ls|head|tail|wc|file|stat|tree|pwd|grep|rg|fd|find|git\s+(status|log|diff|show|branch|remote|fetch|ls-files|rev-parse|config\s+--get))\b[^\"&;><$`]*\"",
    ],
    # Tool names that should always be left to the real user. This keeps
    # clarifying questions from being auto-allowed or auto-denied by the judge.
    # When `answer_user_questions` is true these are answered by the judge
    # instead of escalated.
    "always_ask_tools": ["AskUserQuestion"],
    # Regexes (matched against tool_name + serialized tool_input). Any match
    # forces escalation to the human; the judge cannot auto-allow these.
    "hard_escalate_patterns": [
        r"\brm\s+-[A-Za-z]*[rR][A-Za-z]*[fF]",
        r"\brm\s+-[A-Za-z]*[fF][A-Za-z]*[rR]",
        r"\brm\b(?=.*--recursive)(?=.*--force)",
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


def project_key(cwd):
    """Normalize a cwd to its project root so subdirectories share one toggle.

    Walks up from cwd looking for a `.git` marker (cheap stat calls, no
    subprocess). Falls back to the cwd itself when no repo is found. Returns an
    absolute, resolved path string, or "" when cwd is unknown.
    """
    if not cwd:
        return ""
    try:
        cur = Path(cwd).resolve()
    except Exception:
        return cwd
    for d in (cur, *cur.parents):
        if (d / ".git").exists():
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


def matches_allow_rule(cfg, haystack):
    for pat in cfg.get("always_allow_patterns", []):
        try:
            if re.search(pat, haystack):
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
    feedback = (
        "The human operator is unattended; the permission supervisor answered "
        "this question on their behalf. Selected answer: {answer}. "
        "Rationale: {reason} "
        "Treat this as the user's final answer, proceed accordingly, and do "
        "not call AskUserQuestion again for the same decision."
    ).format(answer=answer, reason=reason or "(supervisor judgement)")
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


def write_state(updates, cwd=None):
    """Merge `updates` into the project's runtime state file. Returns new state."""
    path = state_path(cwd)
    state = load_state(cwd)
    state.update(updates)
    key = project_key(cwd)
    if key and not os.environ.get(STATE_ENV):
        state["_project"] = key  # for --list readability; ignored on load
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(state, ensure_ascii=False, indent=2) + "\n")
    return state


def cli_main(argv):
    """Handle invocations with CLI args (live toggle / status). Returns exit code.

    Usage: permission-supervisor.py
        [--on | --off | --toggle | --status | --list
         | --answers-on | --answers-off | --answers-toggle]
    These edit a runtime state file, which the hook re-reads on every call, so
    the supervisor can be flipped while Claude Code keeps running. The file is
    scoped to the CURRENT project (git root of the working dir) unless
    CLAUDE_SUPERVISOR_STATE_FILE points it elsewhere, so parallel projects
    toggle independently.
    """
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
                st = json.load(open(f, encoding="utf-8"))
            except Exception:
                continue
            print("{:8} {}  ({})".format(
                "ENABLED" if st.get("enabled") is True else "disabled",
                st.get("_project", "?"), f.name))
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
        print("answer_user_questions: {}".format(bool(cfg.get("answer_user_questions"))))
        return 0
    if cmd in ("--on", "on"):
        write_state({"enabled": True}, cwd)
        note = "" if os.environ.get("CLAUDE_SUPERVISOR") is None \
            else " (note: CLAUDE_SUPERVISOR env still overrides)"
        print("supervisor enabled for {} -> next hook call{}".format(key or path, note))
        return 0
    if cmd in ("--off", "off"):
        write_state({"enabled": False}, cwd)
        print("supervisor disabled for {}".format(key or path))
        return 0
    if cmd in ("--toggle", "toggle"):
        new = not (load_state(cwd).get("enabled") is True)
        write_state({"enabled": new}, cwd)
        print("supervisor {} for {}".format("enabled" if new else "disabled", key or path))
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
    sys.stderr.write(
        "usage: permission-supervisor.py "
        "[--on|--off|--toggle|--status|--list"
        "|--answers-on|--answers-off|--answers-toggle]\n")
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
    if "_config_error" in cfg:
        record["config_error"] = cfg["_config_error"]

    if not is_enabled(cfg):
        record.update(decision="ask", stage="disabled")
        audit(record)
        return  # no output -> human decides

    haystack = "{}\n{}".format(tool_name, json.dumps(tool_input, ensure_ascii=False))

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

    always_allow = matches_allow_rule(cfg, haystack)
    if always_allow:
        reason = "matched always-allow pattern"
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
