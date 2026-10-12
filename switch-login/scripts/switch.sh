#!/usr/bin/env bash
# Restart this session in place on the other Claude account. A running session
# cannot change account alone (all sessions of a profile share one credentials
# file), so this asks the `claude` shell wrapper (claude-login.zsh) to resume it
# under the other profile, then stops the current process.
set -euo pipefail

id="${CLAUDE_CODE_SESSION_ID:?not inside a Claude Code session}"
if [ -z "${CLAUDE_SWITCH_FILE:-}" ]; then
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then cmd=claude; else cmd=claude2; fi
  echo "This session was not started through the wrapper. Exit and run: $cmd --resume $id"
  exit 0
fi
echo "$id" >"$CLAUDE_SWITCH_FILE"
echo "Restarting on the other account..."
# Detached and delayed so this tool call returns before claude is stopped.
setsid sh -c "sleep 1; kill -TERM $CLAUDE_PID" >/dev/null 2>&1 &
