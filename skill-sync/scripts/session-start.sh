#!/usr/bin/env bash
# SessionStart hook for Claude Code and Codex (both read the same JSON shape).
# Syncs the skills repo, then hands the new chat any skill changes and the open
# reminders in ~/remind.md as additional context. Prints nothing when there's nothing to say.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
REMIND="${REMIND_FILE:-$HOME/remind.md}"

changes="$("$here/sync.sh" 2>/dev/null)"
# Open items that are due: no date, or a date of today or earlier.
due=""
[ -f "$REMIND" ] && due="$(awk -v today="$(date +%F)" '
  /^- \[ \]/ { if (match($0, /^- \[ \] [0-9]{4}-[0-9]{2}-[0-9]{2} /) && substr($0, 7, 10) > today) next; print }
' "$REMIND")"

ctx=""
if [ -n "$changes" ]; then
  ctx+="Skills repo synced ($HOME/github/skills); these skills changed and are available from the next chat: $(echo "$changes" | paste -sd, - | sed 's/,/, /g')."$'\n'
fi
if [ -n "$due" ]; then
  ctx+="Due reminders from $REMIND (see the remind skill):"$'\n'"$due"$'\n'
  ctx+="In your first reply, remind the user of each one: one line each, the command and its reason. If you can cheaply check that an item is already done (e.g. a container is gone), check first and offer to tick it off instead."$'\n'
fi
[ -z "$ctx" ] && exit 0

python3 -I -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.stdin.read()}}))' <<<"$ctx"
