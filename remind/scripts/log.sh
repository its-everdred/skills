#!/usr/bin/env bash
# Print a chat transcript (a reminder's ctx path) as plain conversation: the user's and the
# agent's messages plus each command the agent ran, oldest first. Reads Claude Code and Codex
# logs. Usage: log.sh <transcript.jsonl> [max chars per message, default 1500]
set -eu
[ -f "${1:-}" ] || { echo "usage: log.sh <transcript.jsonl> [max chars]" >&2; exit 2; }
python3 -I - "$1" "${2:-1500}" <<'PY'
import json, sys
path, cap = sys.argv[1], int(sys.argv[2])

def show(who, text):
    text = text.strip()
    # Skip tool results, harness tags, and the AGENTS.md block Codex injects as a user turn.
    if text and not text.startswith("<") and not text.startswith("# AGENTS.md instructions"):
        print(f"[{who}] {text[:cap]}\n")

for line in open(path):
    try: d = json.loads(line)
    except ValueError: continue
    # Claude Code: {"message": {"role", "content": str | [blocks]}}
    m = d.get("message")
    if isinstance(m, dict) and m.get("role"):
        c = m.get("content")
        if isinstance(c, str): show(m["role"], c); continue
        for b in c or []:
            if b.get("type") == "text": show(m["role"], b["text"])
            elif b.get("type") == "tool_use" and "command" in (b.get("input") or {}):
                show("ran", b["input"]["command"])
        continue
    # Codex: {"type": "response_item", "payload": {"type": "message", "role", "content": [...]}}
    p = d.get("payload") or {}
    if d.get("type") == "response_item" and p.get("type") == "message" and p.get("role") in ("user", "assistant"):
        for b in p.get("content") or []:
            if b.get("type") in ("input_text", "output_text"): show(p["role"], b.get("text", ""))
    elif d.get("type") == "response_item" and p.get("type") in ("function_call", "local_shell_call"):
        args = p.get("arguments") or json.dumps(p.get("action") or {})
        show("ran", args)
PY
