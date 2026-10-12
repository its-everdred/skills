#!/usr/bin/env bash
# Set up a second Claude Code account on this machine for switch-login.
#
# Usage: setup.sh [PROFILE_DIR] [--rc FILE]
#   PROFILE_DIR  the second profile directory (default: $HOME/.claude-2)
#   --rc FILE    shell rc file to edit (default: ~/.zshrc for zsh, else ~/.bashrc)
#
# Creates PROFILE_DIR, links the shared entries of ~/.claude into it, installs
# the skill under ~/.claude/skills/, and adds the two wrapper lines to the rc
# file. Safe to run again: a second run changes nothing. Refuses to touch a path
# that exists but is not what it would create. Never links, copies or prints the
# per-account files (.credentials.json, .claude.json, sessions/).
set -euo pipefail

SHARED=(CLAUDE.md settings.json skills plugins projects todos file-history
  history.jsonl session-env shell-snapshots)

P= RC=
while [ $# -gt 0 ]; do
  case "$1" in
    --rc) RC=${2:?--rc needs a file}; shift 2 ;;
    -h|--help) sed -n '4,6p' "$0" | sed 's/^# //'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) [ -z "$P" ] || { echo "only one PROFILE_DIR" >&2; exit 2; }; P=$1; shift ;;
  esac
done
P=${P:-$HOME/.claude-2}
case "$P" in /*) ;; *) P="$PWD/$P" ;; esac
P=${P%/}
if [ -z "$RC" ]; then
  case "$(basename -- "${SHELL:-bash}")" in zsh) RC="$HOME/.zshrc" ;; *) RC="$HOME/.bashrc" ;; esac
fi

SRC="$HOME/.claude"
SKILL_SRC=$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SKILL_DST="$SRC/skills/switch-login"
NEW_SRC="$(dirname -- "$SKILL_SRC")/new"
NEW_DST="$SRC/skills/new"
EXPORT_LINE="export CLAUDE_LOGIN2_DIR=\"$P\""
SOURCE_LINE='source "$HOME/.claude/skills/switch-login/claude-login.sh"'

[ -d "$SRC" ] || { echo "setup: $SRC does not exist; run claude once first" >&2; exit 1; }
[ "$(realpath -m -- "$P")" != "$(realpath -m -- "$SRC")" ] || { echo "setup: the second profile cannot be $SRC" >&2; exit 1; }

# 1. Check everything first, so a refusal leaves nothing half done.
problems=()
if [ -e "$P" ] || [ -L "$P" ]; then
  [ -d "$P" ] && [ ! -L "$P" ] || problems+=("$P exists and is not a directory: $(ls -ld -- "$P")")
fi
for f in "${SHARED[@]}"; do
  [ -e "$SRC/$f" ] || continue
  t="$P/$f"
  if [ -L "$t" ]; then
    [ "$(readlink -- "$t")" = "$SRC/$f" ] || problems+=("$t links to $(readlink -- "$t"), not $SRC/$f")
  elif [ -e "$t" ]; then
    problems+=("$t is a real $( [ -d "$t" ] && echo directory || echo file ), where a link to $SRC/$f belongs")
  fi
done
if [ -e "$SKILL_DST" ] && [ ! -d "$SKILL_DST" ]; then
  problems+=("$SKILL_DST exists and is not a directory")
fi
if [ -f "$RC" ]; then
  while IFS= read -r line; do
    [ "$line" = "$EXPORT_LINE" ] || problems+=("$RC already sets a different CLAUDE_LOGIN2_DIR: $line")
  done < <(grep -E '^[[:space:]]*export[[:space:]]+CLAUDE_LOGIN2_DIR=' "$RC" || true)
fi
if [ "${#problems[@]}" -gt 0 ]; then
  echo "setup: refusing to change anything. Found:" >&2
  printf '  - %s\n' "${problems[@]}" >&2
  exit 1
fi

# 2. Apply.
changes=()
if [ ! -d "$P" ]; then
  mkdir -p -- "$P"; chmod 700 -- "$P"; changes+=("created $P")
fi
for f in "${SHARED[@]}"; do
  if [ ! -e "$SRC/$f" ]; then
    [ -L "$P/$f" ] || echo "setup: skipping $f (not in $SRC)"
    continue
  fi
  [ -L "$P/$f" ] && continue
  ln -s -- "$SRC/$f" "$P/$f"; changes+=("linked $P/$f -> $SRC/$f")
done
if [ ! -d "$SKILL_DST" ]; then
  mkdir -p -- "$SRC/skills"; cp -R -- "$SKILL_SRC" "$SKILL_DST"; changes+=("installed the skill in $SKILL_DST")
fi
# The `new` skill lets switch-login relaunch a session that was not started
# through the wrapper (for example when the user is remote). Install it too.
if [ -d "$NEW_SRC" ] && [ ! -e "$NEW_DST" ]; then
  cp -R -- "$NEW_SRC" "$NEW_DST"; changes+=("installed the new skill in $NEW_DST")
fi
need_export=1 need_source=1
if [ -f "$RC" ]; then
  grep -qxF -- "$EXPORT_LINE" "$RC" && need_export=0
  grep -qxF -- "$SOURCE_LINE" "$RC" && need_source=0
fi
if [ "$need_export$need_source" != 00 ]; then
  if [ -f "$RC" ]; then
    bak="$RC.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    cp -p -- "$RC" "$bak"; changes+=("backed up $RC to $bak")
  fi
  {
    [ ! -s "$RC" ] || [ -z "$(tail -c1 -- "$RC")" ] || echo
    echo "# switch-login: second Claude account"
    [ "$need_export" = 0 ] || echo "$EXPORT_LINE"
    [ "$need_source" = 0 ] || echo "$SOURCE_LINE"
  } >> "$RC"
  [ "$need_export" = 0 ] || changes+=("added to $RC: $EXPORT_LINE")
  [ "$need_source" = 0 ] || changes+=("added to $RC: $SOURCE_LINE")
fi

if [ "${#changes[@]}" -eq 0 ]; then
  echo "setup: already set up, nothing changed."
else
  echo "setup: changed:"
  printf '  - %s\n' "${changes[@]}"
fi
cat <<EOF

One step left (setup cannot do it): open a new shell, run claude2, and run
/login with the second account. Then check: type claude and type claude2 both
say "function", and /status in claude2 shows the second account.
EOF
