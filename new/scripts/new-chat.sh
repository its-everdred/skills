#!/usr/bin/env bash
# Open a Claude Code chat in DIR with Remote Control on, so it shows up in the
# Claude app. Runs claude inside tmux (works with no one at the machine), and
# also opens a terminal window when a desktop display is available.
#
# Usage:
#   new-chat.sh [--account current|default|second|other] [--resume ID] [--no-rc] [--pane PANE | --session NAME] DIR [-- FLAGS...]
#   new-chat.sh --print-flags PID
#
# Permission flags (--dangerously-skip-permissions, --permission-mode) are
# inherited from the calling claude session, never added. FLAGS after `--`
# replace the inherited ones. --account second uses the profile in
# CLAUDE_LOGIN2_DIR (see the switch-login skill); "current" (the default) is
# the account the calling session is on; "other" is the one it is not on. --print-flags prints PID's permission flags,
# one per line, for callers that must read them before stopping that process.
# --pane PANE replaces the process in that tmux pane (respawn-pane -k) instead
# of starting a new session, so a client attached to it stays attached.
# --session NAME opens the chat as a new window of that tmux session (created
# when missing) instead of a session of its own.
set -euo pipefail

usage() { sed -n '6,8p' "$0" | sed 's/^# //' >&2; exit 2; }

# Permission flags of the claude process PID, or of the nearest claude ancestor
# when PID is not a claude process.
perm_flags() {
  local pid=$1 i
  local -a args
  while [ "$pid" -gt 1 ]; do
    mapfile -d '' -t args < "/proc/$pid/cmdline" 2>/dev/null || args=()
    if [ "${#args[@]}" -gt 0 ] && [ "$(basename -- "${args[0]}")" = claude ]; then
      for i in "${!args[@]}"; do
        case "${args[$i]}" in
          --dangerously-skip-permissions) printf '%s\n' "${args[$i]}" ;;
          --permission-mode) printf '%s\n%s\n' --permission-mode "${args[$((i + 1))]:-default}" ;;
          --permission-mode=*) printf '%s\n' "${args[$i]}" ;;
        esac
      done
      return 0
    fi
    pid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || echo 1)
  done
}

# The second profile directory: environment, then the export line that the
# switch-login setup writes to the shell rc file, then the default location.
login2_dir() {
  if [ -n "${CLAUDE_LOGIN2_DIR:-}" ]; then printf '%s\n' "$CLAUDE_LOGIN2_DIR"; return; fi
  local rc line
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    line=$(grep -E '^export CLAUDE_LOGIN2_DIR=' "$rc" | tail -n1 || true)
    if [ -n "$line" ]; then
      line=${line#export CLAUDE_LOGIN2_DIR=}; line=${line#\"}; line=${line%\"}
      printf '%s\n' "${line/#\$HOME/$HOME}"; return
    fi
  done
  [ -d "$HOME/.claude-2" ] && printf '%s\n' "$HOME/.claude-2"
}

ACCOUNT=current RESUME= RC=1 DIR= EXPLICIT=0 PANE= SESSION=
FLAGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --print-flags) perm_flags "${2:?pid}"; exit 0 ;;
    --account) ACCOUNT=${2:?account}; shift 2 ;;
    --resume) RESUME=${2:?session id}; shift 2 ;;
    --no-rc) RC=0; shift ;;
    --pane) PANE=${2:?pane}; shift 2 ;;
    --session) SESSION=${2:?session}; shift 2 ;;
    --) shift; EXPLICIT=1; FLAGS=("$@"); break ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *) [ -z "$DIR" ] || usage; DIR=$1; shift ;;
  esac
done
[ -n "$DIR" ] || usage
DIR=$(realpath -e -- "$DIR") || { echo "no such directory" >&2; exit 1; }
[ -d "$DIR" ] || { echo "not a directory: $DIR" >&2; exit 1; }
command -v tmux >/dev/null || { echo "tmux is required" >&2; exit 1; }

L2=$(login2_dir || true)
# The calling session is on the second account when its CLAUDE_CONFIG_DIR is the second profile.
ON_SECOND=0
if [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ -n "$L2" ] && [ "$(realpath -m -- "$CLAUDE_CONFIG_DIR")" = "$(realpath -m -- "$L2")" ]; then
  ON_SECOND=1
fi
case "$ACCOUNT" in
  current) if [ "$ON_SECOND" = 1 ]; then ACCOUNT=second; else ACCOUNT=default; fi ;;
  other) if [ "$ON_SECOND" = 1 ]; then ACCOUNT=default; else ACCOUNT=second; fi ;;
esac
case "$ACCOUNT" in
  default) ;;
  second) [ -n "$L2" ] && [ -d "$L2" ] || { echo "no second profile: set up switch-login first (CLAUDE_LOGIN2_DIR)" >&2; exit 1; } ;;
  *) echo "--account must be current, default, second or other" >&2; exit 2 ;;
esac

[ "$EXPLICIT" = 1 ] || mapfile -t FLAGS < <(perm_flags "$PPID")
# Conversation name "<machine> - <project>" (for example "PC - Aiur"); a
# resumed session gets the same name back.
LABEL=$("$(dirname -- "$0")/convo-name.sh" "$DIR")
ARGS=("${FLAGS[@]}" --name "$LABEL")
[ -n "$RESUME" ] && ARGS+=(--resume "$RESUME")
[ "$RC" = 1 ] && ARGS+=(--remote-control "$LABEL")

# Launch through the switch-login wrapper when it is installed, so /switch-login
# works in this session; otherwise run claude directly.
WRAPPER="$HOME/.claude/skills/switch-login/claude-login.sh"
if [ "$ACCOUNT" = second ]; then FN=claude2; else FN=claude; fi
NAME="claude-$(basename -- "$DIR" | tr -d '\n' | tr -c 'A-Za-z0-9_-' '-')-$(date +%H%M%S)-$RANDOM"
# The calling session's own variables must not leak into the new one (a tmux
# server started from here inherits them), above all CLAUDE_CONFIG_DIR, which
# picks the account.
# Start tmux outside the desktop's app scopes: a server forked from a terminal
# lives in that terminal's scope, and logging out (uwsm stop) stops it with
# every chat inside. app.slice is left alone at logout.
scope=()
systemctl --user show-environment >/dev/null 2>&1 && scope=(systemd-run --user --scope --quiet --collect --slice=app.slice)
CLEAN=(env -u CLAUDE_CONFIG_DIR -u CLAUDE_SWITCH_FILE -u CLAUDE_PID -u CLAUDECODE
  -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT)
if [ -n "$PANE" ]; then
  NAME=$PANE
  LAUNCH=(tmux respawn-pane -k -t "$PANE" -c "$DIR")
elif [ -n "$SESSION" ]; then
  # -P prints the new pane's id, which then names the chat for the steps below.
  WIN=$(basename -- "$DIR")
  if tmux has-session -t "=$SESSION" 2>/dev/null; then
    LAUNCH=(tmux new-window -d -P -F '#{pane_id}' -t "=$SESSION:" -n "$WIN" -c "$DIR")
  else
    LAUNCH=("${scope[@]}" tmux new-session -d -P -F '#{pane_id}' -s "$SESSION" -n "$WIN" -c "$DIR")
  fi
else
  LAUNCH=("${scope[@]}" tmux new-session -d -s "$NAME" -c "$DIR")
fi
if [ -f "$WRAPPER" ]; then
  OUT=$("${LAUNCH[@]}" "${CLEAN[@]}" CLAUDE_LOGIN2_DIR="$L2" \
    bash -c 'source "$1"; fn=$2; shift 2; "$fn" "$@"' _ "$WRAPPER" "$FN" "${ARGS[@]}")
elif [ "$ACCOUNT" = second ]; then
  OUT=$("${LAUNCH[@]}" "${CLEAN[@]}" CLAUDE_CONFIG_DIR="$L2" claude "${ARGS[@]}")
else
  OUT=$("${LAUNCH[@]}" "${CLEAN[@]}" claude "${ARGS[@]}")
fi
[ -n "$SESSION" ] && NAME=$OUT

# Wait for the session to be ready. The folder-trust prompt is answered (the
# user named this folder); any other prompt (login, bypass warning) is left to
# the user.
ready=0
for _ in $(seq 1 60); do
  sleep 1
  tmux has-session -t "$NAME" 2>/dev/null || { echo "claude exited during startup" >&2; exit 1; }
  pane=$(tmux capture-pane -p -t "$NAME")
  if grep -qiE "trust (the files|this folder)|Do you trust" <<<"$pane"; then
    # The prompt may open on "No, exit"; move to the "Yes" option before confirming.
    if grep -qE "❯ *(1\. *)?Yes" <<<"$pane"; then tmux send-keys -t "$NAME" Enter; else tmux send-keys -t "$NAME" Down; fi
    continue
  fi
  if grep -qiE "\? for shortcuts|shift\+tab to cycle|remote-control is active" <<<"$pane"; then
    ready=1
    break
  fi
done

# A window added to a session someone is already viewing shows up in its
# status bar; open a terminal (on that window) only when no one is attached.
open=1
[ -n "$PANE" ] && open=0
if [ -n "$SESSION" ]; then
  if [ "$(tmux display-message -p -t "$NAME" '#{session_attached}')" = 0 ]; then tmux select-window -t "$NAME"; else open=0; fi
fi
if [ "$open" = 1 ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  if command -v gnome-terminal >/dev/null; then
    gnome-terminal --title="$NAME" -- tmux attach -t "$NAME" >/dev/null 2>&1 || true
  elif command -v xdg-terminal-exec >/dev/null; then # Omarchy and other non-GNOME desktops
    setsid -f xdg-terminal-exec --title="$NAME" -e tmux attach -t "$NAME" </dev/null >/dev/null 2>&1 || true
  fi
fi

echo "session: $NAME"
echo "name:    $LABEL"
echo "account: $ACCOUNT"
echo "dir:     $DIR"
echo "flags:   ${FLAGS[*]:-(none)}"
echo "attach:  tmux attach -t $NAME"
if [ "$ready" != 1 ]; then
  echo "claude is waiting on a prompt (for example /login on a new account); answer it with: tmux attach -t $NAME" >&2
  exit 1
fi
url=
if [ "$RC" = 1 ]; then
  for _ in $(seq 1 15); do
    url=$(tmux capture-pane -p -t "$NAME" | grep -oE 'https://claude\.ai/code/session_[A-Za-z0-9]+' | tail -n1 || true)
    [ -n "$url" ] && break
    sleep 1
  done
fi
echo "remote:  ${url:-(not shown yet; check the Claude app)}"
