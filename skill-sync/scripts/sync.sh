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
TARGETS=("$HOME/.claude/skills" "$HOME/.codex/skills")

[ -d "$REPO/.git" ] || exit 0

if [ "$(git -C "$REPO" branch --show-current 2>/dev/null)" = main ] &&
   [ -z "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]; then
  timeout 8 git -C "$REPO" pull --ff-only --quiet >/dev/null 2>&1 || true
fi

for target in "${TARGETS[@]}"; do
  [ -d "$(dirname "$target")" ] || continue   # that agent isn't installed here
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
