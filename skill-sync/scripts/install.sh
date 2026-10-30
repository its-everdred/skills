#!/usr/bin/env bash
# One-time setup per machine: register session-start.sh as a SessionStart hook in
# Claude Code (~/.claude/settings.json) and Codex (~/.codex/hooks.json), then run a
# first sync. Re-running changes nothing. A second Claude profile set up by
# switch-login shares ~/.claude/settings.json through a link, so it's covered too.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
hook="$here/session-start.sh"
chmod +x "$here"/*.sh

add_hook() {   # add_hook <json file>
  python3 -I - "$1" "$hook" <<'PY'
import json, os, sys
path, cmd = sys.argv[1], sys.argv[2]
data = json.load(open(path)) if os.path.exists(path) and os.path.getsize(path) else {}
groups = data.setdefault("hooks", {}).setdefault("SessionStart", [])
if any(h.get("command") == cmd for g in groups for h in g.get("hooks", [])):
    print(f"hook already in {path}")
    sys.exit()
groups.append({"hooks": [{"type": "command", "command": cmd, "timeout": 30}]})
note = ""
if os.path.exists(path):
    os.replace(path, path + ".bak")
    note = f" (backup: {path}.bak)"
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"hook added to {path}{note}")
PY
}

[ -d "$HOME/.claude" ] && add_hook "$HOME/.claude/settings.json"
[ -d "$HOME/.codex" ] && add_hook "$HOME/.codex/hooks.json"

"$here/sync.sh"

# Load the coding principles guidance: Codex through a symlink, Claude through an @ import.
principles="$HOME/.agents/coding-principles.md"
if [ -d "$HOME/.codex" ]; then
  if [ -e "$HOME/.codex/AGENTS.md" ] || [ -L "$HOME/.codex/AGENTS.md" ]; then
    echo "skipped ~/.codex/AGENTS.md (already exists)"
  elif [ -e "$principles" ]; then
    ln -s "$principles" "$HOME/.codex/AGENTS.md" && echo "linked ~/.codex/AGENTS.md"
  fi
fi
claude_md="$HOME/.claude/CLAUDE.md"
import='@~/.agents/coding-principles.md'
if [ -d "$HOME/.claude" ] && [ -e "$principles" ]; then
  if grep -qxF "$import" "$claude_md" 2>/dev/null; then
    echo "skipped $claude_md (import already there)"
  else
    [ -f "$claude_md" ] && cp "$claude_md" "$claude_md.bak"
    printf '\n# Coding principles\n\n%s\n' "$import" >> "$claude_md"
    echo "import added to $claude_md"
  fi
fi
echo "skill sync installed"
