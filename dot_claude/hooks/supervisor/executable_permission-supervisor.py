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

DEFAULT_CONFIG = {
    "enabled": False,
    "backend": "judge-codex.sh",
    "backend_timeout_seconds": 120,
    # Regexes (matched against tool_name + serialized tool_input). Any match
    # forces escalation to the human; the judge cannot auto-allow these.
    "hard_escalate_patterns": [
        r"\brm\s+-[a-zA-Z]*[rf]",
        r"\bgit\s+push\b.*(--force|-f)\b",
        r"\bsudo\b",
        r"\bcurl\b[^\n|]*\|\s*(sh|bash|zsh)\b",
        r"\bwget\b[^\n|]*\|\s*(sh|bash|zsh)\b",
        r"\bchmod\s+-R\b",
        r"\bmkfs\b|\bdd\s+if=",
        r"(^|[^\w])~?/?\.ssh/",
        r"\.env(\b|[^\w])",
        r"id_rsa|id_ed25519|\.pem\b|credentials",
        r"\b:\s*\(\)\s*\{",  # fork bomb-ish
    ],
}


def load_config():
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
    return cfg


def is_enabled(cfg):
    """Enabled only when config says so AND the env opt-in is set.

    CLAUDE_SUPERVISOR overrides: "1"/"true" force-on, "0"/"false" force-off.
    """
    env = os.environ.get("CLAUDE_SUPERVISOR")
    if env is not None:
        return env.strip().lower() in ("1", "true", "yes", "on")
    return bool(cfg.get("enabled"))


def matches_hard_rule(cfg, haystack):
    for pat in cfg.get("hard_escalate_patterns", []):
        try:
            if re.search(pat, haystack):
                return pat
        except re.error:
            continue
    return None


def run_backend(cfg, context):
    """Run the configured judge backend. Returns (decision, reason)."""
    backend = os.environ.get("CLAUDE_SUPERVISOR_BACKEND") or cfg.get("backend", "judge-codex.sh")
    backend_path = backend if os.path.isabs(backend) else str(HOOK_DIR / backend)
    timeout = float(cfg.get("backend_timeout_seconds", 120))
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
        return "ask", "backend timeout"
    except Exception as exc:
        return "ask", "backend launch error: {}".format(exc)

    if proc.returncode != 0:
        return "ask", "backend exit {}: {}".format(proc.returncode, proc.stderr.strip()[:200])

    verdict = parse_verdict(proc.stdout)
    if verdict is None:
        return "ask", "unparseable backend output"
    decision = verdict.get("decision", "ask")
    if decision not in ("allow", "deny", "ask"):
        decision = "ask"
    return decision, verdict.get("reason", "")


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


def audit(record):
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    except Exception:
        pass  # logging must never break the hook


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

    cfg = load_config()

    record = {
        "ts": started,
        "event": event_name,
        "tool": tool_name,
        "cwd": cwd,
    }

    if not is_enabled(cfg):
        record.update(decision="ask", stage="disabled")
        audit(record)
        return  # no output -> human decides

    haystack = "{}\n{}".format(tool_name, json.dumps(tool_input, ensure_ascii=False))
    hard = matches_hard_rule(cfg, haystack)
    if hard:
        record.update(decision="ask", stage="hard_rule", rule=hard)
        audit(record)
        return  # dangerous -> always human

    context = {
        "tool_name": tool_name,
        "tool_input": tool_input,
        "cwd": cwd,
        "session_id": event.get("session_id", ""),
        "hook_event_name": event_name,
    }
    decision, reason = run_backend(cfg, context)

    record.update(
        decision=decision,
        stage="backend",
        reason=reason,
        elapsed_ms=int((time.time() - started) * 1000),
    )
    audit(record)
    emit(event_name, decision, reason)


if __name__ == "__main__":
    main()
