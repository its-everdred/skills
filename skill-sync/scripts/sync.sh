#!/usr/bin/env bash
# Pull the skills repo and link every skill in it into Claude Code and Codex.
#
# Safe to run on every session start: the pull is fast-forward only, skipped when the
# checkout isn't a clean `main`, and capped at a few seconds so an offline machine
# doesn't stall a new chat. Linking never replaces a real directory, only adds missing
# links and removes links whose skill was deleted from the repo.
#
# Prints one line per change ("linked <name>", "unlinked <name>"); silent when nothing changed.
set -u

REPO="${SKILLS_REPO:-$HOME/github/skills}"
TARGETS=("$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills")

[ -d "$REPO/.git" ] || exit 0

# macOS has no `timeout`; python3 is already required by the hook. Kills the whole group on expiry.
with_timeout() {
  python3 -I -c '
import os, signal, subprocess, sys
p = subprocess.Popen(sys.argv[2:], start_new_session=True)
try:
    sys.exit(p.wait(timeout=float(sys.argv[1])))
except subprocess.TimeoutExpired:
    os.killpg(p.pid, signal.SIGKILL)
    sys.exit(124)
' "$@"
}

if [ "$(git -C "$REPO" branch --show-current 2>/dev/null)" = main ] &&
   [ -z "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]; then
  with_timeout 8 git -C "$REPO" pull --ff-only --quiet >/dev/null 2>&1 || true
fi

for target in "${TARGETS[@]}"; do
  # that agent isn't installed here (~/.agents is shared by clients, so always created)
  [ "$target" = "$HOME/.agents/skills" ] || [ -d "$(dirname "$target")" ] || continue
  mkdir -p "$target"

  for skill in "$REPO"/*/SKILL.md; do
    [ -e "$skill" ] || continue
    dir="$(dirname "$skill")"
    name="$(basename "$dir")"
    link="$target/$name"
    if [ -L "$link" ] || [ -e "$link" ]; then continue; fi   # already there (ours or the user's own)
    ln -s "$dir" "$link" && echo "linked $name"
  done

  # A skill removed from the repo leaves a dangling link behind; only ours are touched.
  for link in "$target"/*; do
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in
      "$REPO"/*) [ -e "$link" ] || { rm "$link" && echo "unlinked $(basename "$link")"; } ;;
    esac
  done
done | sort -u

# Shared external skills (pinned in external-skills.json). Only changes and failures are printed.
if [ -x "$REPO/sync-external.sh" ]; then
  out="$(with_timeout 120 "$REPO/sync-external.sh" --shared-only 2>&1)"; rc=$?
  printf '%s\n' "$out" | grep -E '^  (installed|skip|linked|clone failed)' | sed 's/^  /shared: /'
  [ "$rc" = 0 ] || echo "shared: external sync FAILED (exit $rc)"
fi
