#!/usr/bin/env bash
# Default supervisor backend: ask codex to judge a single tool call.
#
# Contract: reads a context JSON object on stdin, prints a verdict JSON
# {"decision":"allow|deny|ask","reason":"..."} on stdout. On any failure it
# prints an "ask" verdict so the orchestrator escalates to the human.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

ask() {
  python3 -c "import json,sys; print(json.dumps({'decision':'ask','reason':sys.argv[1]}))" \
    "${1:-codex backend error}"
  exit 0
}

CONTEXT="$(cat)"
[ -n "$CONTEXT" ] || ask "empty context"
command -v codex >/dev/null 2>&1 || ask "codex not found"

# Pick the template by mode: "answer" mode asks codex to answer a clarifying
# question on the user's behalf; otherwise it judges a permission request.
MODE="$(CONTEXT="$CONTEXT" python3 -c 'import json,os;print(json.loads(os.environ["CONTEXT"]).get("mode",""))' 2>/dev/null || echo "")"
if [ "$MODE" = "answer" ]; then
  TEMPLATE="$HOOK_DIR/prompt-answer-template.md"
else
  TEMPLATE="$HOOK_DIR/prompt-template.md"
fi
[ -f "$TEMPLATE" ] || ask "missing prompt template"

# Build the prompt by substituting the context into the template.
PROMPT="$(CONTEXT="$CONTEXT" python3 - "$TEMPLATE" <<'PY'
import os, sys
tmpl = open(sys.argv[1], encoding="utf-8").read()
sys.stdout.write(tmpl.replace("{CONTEXT}", os.environ["CONTEXT"]))
PY
)" || ask "prompt build failed"

# Run codex non-interactively. Close stdin so codex does not block on it.
RAW="$(codex exec "$PROMPT" </dev/null 2>/dev/null)" || ask "codex exec failed"

# Extract the verdict JSON from codex output (last {... "decision" ...}).
VERDICT="$(RAW="$RAW" python3 <<'PY'
import json, os, re, sys
raw = os.environ.get("RAW", "")
for chunk in reversed(re.findall(r'\{[^{}]*"decision"[^{}]*\}', raw, re.DOTALL)):
    try:
        obj = json.loads(chunk)
    except json.JSONDecodeError:
        continue
    if isinstance(obj, dict) and obj.get("decision") in ("allow", "deny", "ask", "answer"):
        out = {"decision": obj["decision"], "reason": obj.get("reason", "")}
        if obj["decision"] == "answer":
            out["answer"] = obj.get("answer", "")
        print(json.dumps(out))
        break
else:
    print('{"decision":"ask","reason":"no parseable verdict from codex"}')
PY
)" || ask "verdict parse failed"

printf '%s\n' "$VERDICT"
