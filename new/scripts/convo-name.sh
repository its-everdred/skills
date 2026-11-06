#!/usr/bin/env bash
# Print the Claude conversation name for DIR (default: the current directory):
# "<machine> - <project>", for example "PC - Aiur" or "NUC - GM".
#
#   machine: $CLAUDE_MACHINE_LABEL, else PC on orangekid, NUC on a host whose
#            name contains "nuc", else the host name in capitals.
#   project: $CLAUDE_PROJECT_LABEL, else the repository's main checkout name
#            (a worktree under <repo>-worktrees/ names its repo), mapped below;
#            an unmapped name is used with its first letter in capitals.
set -euo pipefail

dir=${1:-$PWD}

machine=${CLAUDE_MACHINE_LABEL:-}
if [ -z "$machine" ]; then
  host=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo host)
  case "${host,,}" in
    orangekid) machine=PC ;;
    *nuc*) machine=NUC ;;
    *) machine=${host^^} ;;
  esac
fi

project=${CLAUDE_PROJECT_LABEL:-}
if [ -z "$project" ]; then
  # The common git dir is the main checkout's .git, also from a worktree.
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [ -n "$common" ] && [ "$(basename -- "$common")" = .git ]; then
    repo=$(basename -- "$(dirname -- "$common")")
  else
    repo=$(basename -- "$(realpath -m -- "$dir")")
  fi
  case "${repo,,}" in
    aiur) project=Aiur ;;
    open-game-maker|uncle-kevins-game-maker-2000) project=GM ;;
    open-games) project=OG ;;
    khala) project=Khala ;;
    *) project=${repo^} ;;
  esac
fi

printf '%s - %s\n' "$machine" "$project"
