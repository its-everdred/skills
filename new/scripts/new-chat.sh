#!/usr/bin/env bash
# Open a Claude Code chat in DIR with Remote Control on, so it shows up in the
# Claude app. Runs claude inside tmux (works with no one at the machine), and
# also opens a terminal window when a desktop display is available.
#
# Usage:
#   new-chat.sh [--account default|second|other] [--resume ID] [--no-rc] DIR [-- FLAGS...]
#   new-chat.sh --print-flags PID
#
# Permission flags (--dangerously-skip-permissions, --permission-mode) are
# inherited from the calling claude session, never added. FLAGS after `--`
# replace the inherited ones. --account second uses the profile in
# CLAUDE_LOGIN2_DIR (see the switch-login skill); "other" is whichever account
# the calling session is not on. --print-flags prints PID's permission flags,
# one per line, for callers that must read them before stopping that process.
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

ACCOUNT=default RESUME= RC=1 DIR= EXPLICIT=0
FLAGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --print-flags) perm_flags "${2:?pid}"; exit 0 ;;
    --account) ACCOUNT=${2:?account}; shift 2 ;;
    --resume) RESUME=${2:?session id}; shift 2 ;;
    --no-rc) RC=0; shift ;;
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
if [ "$ACCOUNT" = other ]; then
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ -n "$L2" ] && [ "$(realpath -m -- "$CLAUDE_CONFIG_DIR")" = "$(realpath -m -- "$L2")" ]; then
    ACCOUNT=default
  else
    ACCOUNT=second
  fi
fi
case "$ACCOUNT" in
  default) ;;
  second) [ -n "$L2" ] && [ -d "$L2" ] || { echo "no second profile: set up switch-login first (CLAUDE_LOGIN2_DIR)" >&2; exit 1; } ;;
  *) echo "--account must be default, second or other" >&2; exit 2 ;;
esac

[ "$EXPLICIT" = 1 ] || mapfile -t FLAGS < <(perm_flags "$PPID")
ARGS=("${FLAGS[@]}")
[ -n "$RESUME" ] && ARGS+=(--resume "$RESUME")
[ "$RC" = 1 ] && ARGS+=(--remote-control)

# Launch through the switch-login wrapper when it is installed, so /switch-login
# works in this session; otherwise run claude directly.
WRAPPER="$HOME/.claude/skills/switch-login/claude-login.sh"
if [ "$ACCOUNT" = second ]; then FN=claude2; else FN=claude; fi
NAME="claude-$(basename -- "$DIR" | tr -d '\n' | tr -c 'A-Za-z0-9_-' '-')-$(date +%H%M%S)-$RANDOM"
# The calling session's own variables must not leak into the new one (a tmux
# server started from here inherits them), above all CLAUDE_CONFIG_DIR, which
# picks the account.
CLEAN=(env -u CLAUDE_CONFIG_DIR -u CLAUDE_SWITCH_FILE -u CLAUDE_PID -u CLAUDECODE
  -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT)
if [ -f "$WRAPPER" ]; then
  tmux new-session -d -s "$NAME" -c "$DIR" "${CLEAN[@]}" CLAUDE_LOGIN2_DIR="$L2" \
    bash -c 'source "$1"; fn=$2; shift 2; "$fn" "$@"' _ "$WRAPPER" "$FN" "${ARGS[@]}"
elif [ "$ACCOUNT" = second ]; then
  tmux new-session -d -s "$NAME" -c "$DIR" "${CLEAN[@]}" CLAUDE_CONFIG_DIR="$L2" claude "${ARGS[@]}"
else
  tmux new-session -d -s "$NAME" -c "$DIR" "${CLEAN[@]}" claude "${ARGS[@]}"
fi

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

if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v gnome-terminal >/dev/null; then
  gnome-terminal --title="$NAME" -- tmux attach -t "$NAME" >/dev/null 2>&1 || true
fi

echo "session: $NAME"
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
