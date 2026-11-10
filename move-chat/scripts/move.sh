#!/usr/bin/env bash
# Move this Claude Code chat into a window of a tmux session (default "claude",
# the one `claudes` uses), so it survives logout and sits with the other chats.
# Stops this process, then resumes the same conversation there on the same
# account, with this session's permission flags and Remote Control on.
#
# Usage: move.sh [SESSION]
set -euo pipefail
umask 077

id="${CLAUDE_CODE_SESSION_ID:?not inside a Claude Code session}"
pid="${CLAUDE_PID:?not inside a Claude Code session}"
case "$pid" in ''|*[!0-9]*) echo "move-chat: invalid CLAUDE_PID" >&2; exit 1 ;; esac
[ "$pid" -gt 1 ] || { echo "move-chat: invalid CLAUDE_PID" >&2; exit 1; }
session=${1:-claude}
launcher="$HOME/.claude/skills/new/scripts/new-chat.sh"
command -v tmux >/dev/null || { echo "move-chat: tmux is required" >&2; exit 1; }
[ -x "$launcher" ] || { echo "move-chat: needs the new skill ($launcher)" >&2; exit 1; }

if [ -n "${TMUX_PANE:-}" ] && [ "$(tmux display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null)" = "$session" ]; then
  echo "This chat is already in the tmux session '$session'."
  exit 0
fi

runtime=${XDG_RUNTIME_DIR:-/tmp}
[ -d "$runtime" ] && [ -w "$runtime" ] || runtime=/tmp
dir=$(readlink "/proc/$pid/cwd" 2>/dev/null || pwd)
# Read the permission flags now, before the process is gone.
mapfile -t flags < <("$launcher" --print-flags "$pid")
log="$runtime/claude-move-$(printf '%s' "$id" | tr -c 'A-Za-z0-9_-' '_').log"

echo "Moving this chat to a window of the tmux session '$session' (tmux attach -t $session)..."
# Stop this process before resuming so two processes never write the same
# transcript. Detached and delayed so this tool call returns first.
setsid bash -c 'sleep 1; kill -TERM "$1"; sleep 2; shift; exec "$@"' \
  _ "$pid" "$launcher" --resume "$id" --session "$session" "$dir" -- "${flags[@]}" >"$log" 2>&1 &
