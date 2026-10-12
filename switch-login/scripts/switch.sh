#!/usr/bin/env bash
# Restart this session on the other Claude account. A running session cannot
# change account alone (all sessions of a profile share one credentials file),
# so this asks the `claude` shell wrapper (claude-login.sh) to resume it under
# the other profile, then stops the current process.
#
# Usage: switch.sh [rc|no-rc]
#   The resumed session starts with Remote Control on when this session has it
#   on (CLAUDE_CODE_BRIDGE_SESSION_ID is set), or when "rc" is passed. "no-rc"
#   turns that off.
#
# If the session was not started through the wrapper, it is relaunched in a new
# tmux session on the other account (with Remote Control on) instead, so this
# also works when the user is driving the session remotely from the Claude app.
set -euo pipefail
umask 077

id="${CLAUDE_CODE_SESSION_ID:?not inside a Claude Code session}"
pid="${CLAUDE_PID:?not inside a Claude Code session}"
case "$pid" in ''|*[!0-9]*) echo "switch-login: invalid CLAUDE_PID" >&2; exit 1 ;; esac
[ "$pid" -gt 1 ] || { echo "switch-login: invalid CLAUDE_PID" >&2; exit 1; }
runtime=${XDG_RUNTIME_DIR:-/tmp}
[ -d "$runtime" ] && [ -w "$runtime" ] || runtime=/tmp

rc=
case "${1:-}" in
  rc) rc=rc ;;
  no-rc) rc= ;;
  "") [ -n "${CLAUDE_CODE_BRIDGE_SESSION_ID:-}" ] && rc=rc ;;
  *) echo "usage: switch.sh [rc|no-rc]" >&2; exit 2 ;;
esac

if [ -n "${CLAUDE_SWITCH_FILE:-}" ]; then
  printf '%s\n%s\n' "$id" "$rc" >"$CLAUDE_SWITCH_FILE"
  echo "Restarting on the other account${rc:+ with Remote Control}..."
  # Detached and delayed so this tool call returns before claude is stopped.
  setsid sh -c 'sleep 1; kill -TERM "$1"' _ "$pid" >/dev/null 2>&1 &
  exit 0
fi

# Not under the wrapper: relaunch in tmux on the other account.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then other=default; else other=second; fi
launcher="$HOME/.claude/skills/new/scripts/new-chat.sh"
dir=$(readlink "/proc/$pid/cwd" 2>/dev/null || pwd)
if ! command -v tmux >/dev/null || [ ! -x "$launcher" ]; then
  if [ "$other" = default ]; then cmd=claude; else cmd=claude2; fi
  echo "This session was not started through the wrapper. Exit and run: $cmd --resume $id"
  exit 0
fi
echo "Not started through the wrapper: resuming in a new tmux session on the $other account with Remote Control, then stopping this one..."
# Read this session's permission flags now, before the process is gone, and
# stop it before resuming so two processes never write the same transcript.
mapfile -t flags < <("$launcher" --print-flags "$pid")
log_id=$(printf '%s' "$id" | tr -c 'A-Za-z0-9_-' '_')
setsid bash -c 'sleep 1; kill -TERM "$1"; sleep 2; shift; exec "$@"' \
  _ "$pid" "$launcher" --account "$other" --resume "$id" "$dir" -- "${flags[@]}" >"$runtime/claude-switch-$log_id.log" 2>&1 &
