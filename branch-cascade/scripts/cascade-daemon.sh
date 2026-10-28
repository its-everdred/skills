#!/bin/bash
# Keeps autorebase.sh running for one stack, so nobody has to ask for a rebase.
# Restarts it when it stops, notifies once per distinct problem (conflict or stop), and exits when every PR is merged.
# usage: cascade-daemon.sh --repo OWNER/NAME --worktree DIR [autorebase.sh options] PR_OR_BRANCH...
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/share/mise/shims:/usr/bin:/bin:$PATH"
# push over HTTPS with the gh login, so a missing ssh agent cannot stop a push
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0="url.https://github.com/.insteadOf" GIT_CONFIG_VALUE_0="git@github.com:"
export GIT_CONFIG_KEY_1="credential.helper" GIT_CONFIG_VALUE_1=""
export GIT_CONFIG_KEY_2="credential.helper" GIT_CONFIG_VALUE_2="!gh auth git-credential"
HERE=$(cd "$(dirname "$0")" && pwd)
WT=""; prev=""
for a in "$@"; do [ "$prev" = "--worktree" ] && WT="$a"; prev="$a"; done
[ -d "$WT" ] || { echo "cascade-daemon: --worktree DIR is required" >&2; exit 1; }
LOG="${WT}.cascade.log"
notify(){ osascript -e "display notification \"$1\" with title \"branch-cascade\"" 2>/dev/null; }
last=""
while true; do
  # a leftover lock from a killed run would block every restart
  pgrep -f "autorebase.sh .*${WT}" >/dev/null || rmdir "${WT}.autorebase.lock" 2>/dev/null
  bash "$HERE/autorebase.sh" --max-hours 24 "$@" 2>&1 | tee -a "$LOG"
  code=${PIPESTATUS[0]}
  if tail -n 3 "$LOG" | grep -q ' DONE '; then exit 0; fi
  msg=$(tail -n 1 "$LOG" | cut -c1-200)
  case "$code" in
    0) ;;
    *) if [ "$msg" != "$last" ]; then notify "$msg"; last="$msg"; fi; sleep 300;;
  esac
done
