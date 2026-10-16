#!/usr/bin/env bash
# Install third-party skills listed in external-skills.json. Idempotent.
# Usage: ./sync-external.sh [--dry-run]
# Never executes anything from cloned repos; it only copies files out of them.
set -euo pipefail

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
DIR="$(cd "$(dirname "$0")" && pwd)"
M="$DIR/external-skills.json"
added=0 present=0 skipped=0 failed=0

command -v jq >/dev/null || { echo "jq required"; exit 1; }
run() { if [ "$DRY" = 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }

if command -v claude >/dev/null; then
  echo "== Claude Code"
  have_mp=$(claude plugin marketplace list --json | jq -r '.[].name')
  have_pl=$(claude plugin list --json | jq -r '.[] | select(.scope=="user") | .id')
  while IFS=$'\t' read -r name src; do
    if grep -qxF "$name" <<<"$have_mp"; then present=$((present+1)); continue; fi
    echo "marketplace add $name ($src)"
    if run claude plugin marketplace add "$src" --scope user >/dev/null; then added=$((added+1)); else failed=$((failed+1)); fi
  done < <(jq -r '.claude.marketplaces[] | [.name,.source] | @tsv' "$M")
  while IFS=$'\t' read -r id ver; do
    if grep -qxF "$id" <<<"$have_pl"; then present=$((present+1)); continue; fi
    echo "plugin install $id (recorded version $ver)"
    if run claude plugin install "$id" --scope user >/dev/null; then added=$((added+1)); else failed=$((failed+1)); fi
  done < <(jq -r '.claude.plugins[] | [.id,.version] | @tsv' "$M")
else
  echo "claude CLI not found, skipping Claude Code"; skipped=$((skipped+1))
fi

if command -v codex >/dev/null; then
  echo "== Codex"
  while IFS=$'\t' read -r repo ref sub dest; do
    dest="${dest/#\~/$HOME}"
    tmp=$(mktemp -d)
    if [ "$DRY" = 1 ]; then
      echo "  [dry-run] would clone $repo @ ${ref:0:10} and copy $sub/* into $dest"
      rm -rf "$tmp"; continue
    fi
    # fetch only the pinned commit; hooks and scripts in the clone are never run
    if ! { git -C "$tmp" init -q && git -C "$tmp" fetch -q --depth 1 "$repo" "$ref" && git -C "$tmp" checkout -q FETCH_HEAD; }; then
      echo "  clone failed: $repo"; failed=$((failed+1)); rm -rf "$tmp"; continue
    fi
    mkdir -p "$dest"
    for s in "$tmp/$sub"/*/; do
      n=$(basename "$s")
      if [ -e "$dest/$n" ]; then
        if diff -rq "$s" "$dest/$n" >/dev/null; then present=$((present+1)); else
          echo "  skip $n: exists and differs (local changes kept)"; skipped=$((skipped+1)); fi
      else
        cp -R "$s" "$dest/$n"; added=$((added+1)); echo "  installed $n"
      fi
    done
    rm -rf "$tmp"
  done < <(jq -r '.codex.skills[] | [.repo,.ref,.subpath,.dest] | @tsv' "$M")
else
  echo "codex CLI not found, skipping Codex"; skipped=$((skipped+1))
fi

echo "== Summary: added=$added already-present=$present skipped=$skipped failed=$failed$([ "$DRY" = 1 ] && echo ' (dry-run)')"
[ "$failed" = 0 ]
