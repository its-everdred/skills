#!/usr/bin/env bash
# claudes: open a tmux session ("claude") with one Claude chat per window, each
# continuing that folder's last conversation with Remote Control on. Windows
# are listed in a machine-local file; only missing windows are created, then
# the session is attached.
#
# Usage: claudes.sh [CONFIG]   (default: ${CLAUDES_CONFIG:-~/.config/claudes/windows})
#
# CONFIG has one window per line: NAME DIR COMMAND... ('#' starts a comment,
# a leading ~ in DIR is the home folder). COMMAND runs in your interactive
# shell, so shell functions such as claude2 work. Example:
#   web   ~/code/web    claude --dangerously-skip-permissions
#   docs  ~/code/docs   claude2
set -euo pipefail

config=${1:-${CLAUDES_CONFIG:-$HOME/.config/claudes/windows}}
session=claude
[ -f "$config" ] || { echo "no config file: $config (see the header of $0)" >&2; exit 1; }
command -v tmux >/dev/null || { echo "tmux is required" >&2; exit 1; }
shell=${SHELL:-bash}
# Start tmux outside the desktop's app scopes: a server forked from a terminal
# lives in that terminal's scope, and logging out (uwsm stop) stops it with
# every chat inside. app.slice is left alone at logout.
scope=()
systemctl --user show-environment >/dev/null 2>&1 && scope=(systemd-run --user --scope --quiet --collect --slice=app.slice)
here=$(dirname -- "$(realpath -- "$0")")

# A tmux server started from inside a Claude chat inherits its variables; keep
# them out, above all CLAUDE_CONFIG_DIR, which picks the account.
clean=(env -u CLAUDE_CONFIG_DIR -u CLAUDE_SWITCH_FILE -u CLAUDE_PID -u CLAUDECODE
  -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT)

while read -r name dir cmd; do
  [[ -z $name || $name == \#* ]] && continue
  [[ -n $dir && -n $cmd ]] || { echo "skipping bad line for '$name': need NAME DIR COMMAND" >&2; continue; }
  dir=${dir/#\~/$HOME}
  [ -d "$dir" ] || { echo "skipping $name: no folder $dir" >&2; continue; }
  if tmux has-session -t "=$session" 2>/dev/null &&
    tmux list-windows -t "=$session" -F '#W' | grep -qxF -- "$name"; then
    continue
  fi

  label=$("$here/convo-name.sh" "$dir")
  run="$cmd --name ${label@Q} --remote-control ${label@Q}"
  # --continue fails when the folder has no earlier chat; start a fresh one then.
  # The shell stays open after Claude exits, so the window survives.
  script="$run --continue || $run; exec ${shell@Q}"
  if tmux has-session -t "=$session" 2>/dev/null; then
    tmux new-window -d -t "=$session:" -n "$name" -c "$dir" "${clean[@]}" "$shell" -ic "$script"
  else
    "${scope[@]}" tmux new-session -d -s "$session" -n "$name" -c "$dir" "${clean[@]}" "$shell" -ic "$script"
  fi
  echo "started $name ($label) in $dir"
done < "$config"

tmux has-session -t "=$session" 2>/dev/null || { echo "no windows started; check $config" >&2; exit 1; }
if [ -n "${TMUX:-}" ]; then
  exec tmux switch-client -t "=$session"
elif [ -t 1 ]; then
  exec tmux attach -t "=$session"
else
  echo "attach: tmux attach -t $session"
fi
