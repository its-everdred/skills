#!/usr/bin/env bash
# The hourly listener. It waits in silence and checks once an hour whether the user has written anything since the
# last pass; only then does it print the count and exit, and that exit is what wakes the agent. An hour with no user
# messages costs no turn at all. Run it with the agent's background shell (Bash run_in_background) and re-arm it after
# each pass.   usage: listen.sh [project dir, default .] [minutes, default 60]
dir=${1:-$PWD}; every=${2:-60}; here=$(dirname "$(readlink -f "$0")")
while sleep $((every * 60)); do
  python3 -I "$here/signals.py" --since "$every" --human --cwd "$dir" && exit 0
done
