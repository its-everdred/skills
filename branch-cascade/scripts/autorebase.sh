#!/bin/bash
# Keeps a stack of open PRs up to date with the default branch until each one merges.
# Default mode adds merge commits and pushes fast-forward only: no force-push, no rewritten history.
# --rebase rewrites the branches instead (force-push with leases).
# Pushes only to the stack's own branches. Never merges, comments, retargets or approves.
#
# usage: autorebase.sh --repo OWNER/NAME --worktree DIR [--rebase] [--once] [--interval S] [--max-hours H] [--dry-run] PR...
#   PR...      PR numbers, bottom of the stack first
#   --worktree a clean checkout of the repo this script may detach and reset freely
# One line per event on stdout. Exit codes: 0 done, 1 stopped (needs a human), 2 rebase conflict.
set -u
REPO=""; WT=""; INTERVAL=45; MAXH=12; DRY=0; ONCE=0; MODE=merge; PRS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --worktree) WT="$2"; shift 2;;
    --interval) INTERVAL="$2"; shift 2;;
    --max-hours) MAXH="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    --rebase) MODE=rebase; shift;;
    --once) ONCE=1; shift;;
    *) PRS+=("$1"); shift;;
  esac
done
say(){ echo "$(date +%H:%M:%S) $*"; }
[ -n "$REPO" ] && [ -d "$WT" ] && [ ${#PRS[@]} -gt 0 ] || { say "STOP usage: --repo OWNER/NAME --worktree DIR PR..."; exit 1; }
export GIT_EDITOR=true
cd "$WT" || exit 1
LOCK="${WT}.autorebase.lock"; STATE="${WT}.autorebase.state"
mkdir "$LOCK" 2>/dev/null || { say "STOP another listener holds $LOCK"; exit 1; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
touch "$STATE"
DEFAULT=$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)
[ -n "$DEFAULT" ] || { say "STOP cannot read the default branch of $REPO"; exit 1; }
UP="origin/$DEFAULT"
start=$(date +%s)

info(){ gh pr view "$1" --repo "$REPO" --json state,headRefName,headRefOid,baseRefName,reviewDecision --jq '[.state,.headRefName,.headRefOid,.baseRefName,.reviewDecision]|@tsv' 2>/dev/null; }
# shas this script replaced for a PR, newest first
recorded(){ awk -v p="$1" '$1=="old" && $2==p {a[++n]=$3} END{for(i=n;i>0;i--) print a[i]}' "$STATE"; }
# first candidate sha that is an ancestor of $1
pick(){ child="$1"; shift; for c in "$@"; do [ -n "$c" ] && git cat-file -e "${c}^{commit}" 2>/dev/null && git merge-base --is-ancestor "$c" "$child" && { echo "$c"; return 0; }; done; return 1; }

say "START ${PRS[*]} on $DEFAULT in $REPO (mode=$MODE dry-run=$DRY)"
while [ $(( $(date +%s) - start )) -lt $(( MAXH * 3600 )) ]; do
  git fetch -q origin 2>/dev/null || { sleep "$INTERVAL"; continue; }
  OPEN=(); HEAD=(); BR=(); REV=(); mergedPR=""; mergedHead=""
  for n in "${PRS[@]}"; do
    line=$(info "$n"); [ -z "$line" ] && { sleep "$INTERVAL"; continue 2; }
    IFS=$'\t' read -r st br hd base rev <<<"$line"
    case "$st" in
      OPEN) OPEN+=("$n"); HEAD+=("$hd"); BR+=("$br"); REV+=("$rev");;
      MERGED) mergedPR="$n"; mergedHead="$hd"
              grep -q "^merged $n\$" "$STATE" || { echo "merged $n" >> "$STATE"; say "MERGED #$n"; };;
      *) say "STOP #$n is $st without merging"; exit 1;;
    esac
  done
  [ ${#OPEN[@]} -eq 0 ] && { say "DONE every PR in the stack is merged"; exit 0; }

  need=""
  behind=$(git rev-list --count "${HEAD[0]}..$UP")
  [ "$behind" -gt 0 ] && need="#${OPEN[0]} is behind $DEFAULT by $behind"
  i=1
  while [ $i -lt ${#OPEN[@]} ]; do
    git merge-base --is-ancestor "${HEAD[$((i-1))]}" "${HEAD[$i]}" || need="${need:+$need; }#${OPEN[$i]} is not on top of #${OPEN[$((i-1))]}"
    i=$((i+1))
  done
  [ -z "$need" ] && { [ "$ONCE" = 1 ] && { say "nothing to update"; exit 0; }; sleep "$INTERVAL"; continue; }

  # where each PR's own commits start (its old parent), found before anything is rewritten
  B=()
  if [ -n "$mergedPR" ]; then
    b=$(pick "${HEAD[0]}" "$mergedHead" $(recorded "$mergedPR")) || { say "STOP cannot find where #${OPEN[0]} was based after #$mergedPR merged"; exit 1; }
  else
    b=$(git merge-base "$UP" "${HEAD[0]}")
  fi
  B+=("$b")
  i=1
  while [ $i -lt ${#OPEN[@]} ]; do
    p="${OPEN[$((i-1))]}"
    fp=$(git merge-base --fork-point "origin/${BR[$((i-1))]}" "${HEAD[$i]}" 2>/dev/null)
    b=$(pick "${HEAD[$i]}" "${HEAD[$((i-1))]}" $fp $(recorded "$p")) || { say "STOP cannot find where #${OPEN[$i]} was based on #$p"; exit 1; }
    B+=("$b"); i=$((i+1))
  done

  NEW=(); newparent="$UP"; i=0
  while [ $i -lt ${#OPEN[@]} ]; do
    git checkout -q --detach "${HEAD[$i]}" || exit 1
    if ! git rebase -q --onto "$newparent" "${B[$i]}" >/tmp/autorebase.log 2>&1; then
      git rebase --abort 2>/dev/null
      say "CONFLICT rebasing #${OPEN[$i]} onto ${newparent:0:9} ($need). Nothing pushed. Resolve by hand or hand to an agent."
      exit 2
    fi
    NEW+=("$(git rev-parse HEAD)"); newparent="${NEW[$i]}"; i=$((i+1))
  done

  # merge mode: keep the rebased trees but record them as merge commits on top of the old heads,
  # so every push is a fast-forward and the stack keeps its ancestry
  if [ "$MODE" = merge ]; then
    PT="$UP"; PTNAME="$DEFAULT"; i=0
    while [ $i -lt ${#OPEN[@]} ]; do
      tree=$(git rev-parse "${NEW[$i]}^{tree}")
      NEW[$i]=$(git commit-tree "$tree" -p "${HEAD[$i]}" -p "$PT" -m "Merge $PTNAME into ${BR[$i]}")
      PT="${NEW[$i]}"; PTNAME="${BR[$i]}"; i=$((i+1))
    done
  fi

  args=(); refs=(); changed=0; approved=""; i=0
  while [ $i -lt ${#OPEN[@]} ]; do
    [ "${NEW[$i]}" != "${HEAD[$i]}" ] && changed=1
    [ "$MODE" = rebase ] && args+=("--force-with-lease=refs/heads/${BR[$i]}:${HEAD[$i]}")
    refs+=("${NEW[$i]}:refs/heads/${BR[$i]}")
    [ "${REV[$i]}" = "APPROVED" ] && approved="$approved #${OPEN[$i]}"
    i=$((i+1))
  done
  [ "$changed" = 0 ] && { sleep "$INTERVAL"; continue; }

  if [ "$DRY" = 1 ]; then
    say "DRY-RUN ($MODE) would push [$need]:"
    i=0; while [ $i -lt ${#OPEN[@]} ]; do say "  #${OPEN[$i]} ${BR[$i]} ${HEAD[$i]:0:9} -> ${NEW[$i]:0:9} (diff vs $DEFAULT: $(git diff --shortstat "$UP" "${NEW[$i]}" | sed 's/^ *//'))"; i=$((i+1)); done
    exit 0
  fi

  if git push -q --atomic ${args[@]+"${args[@]}"} origin "${refs[@]}" 2>/tmp/autorebase-push.log; then
    i=0; line=""
    while [ $i -lt ${#OPEN[@]} ]; do echo "old ${OPEN[$i]} ${HEAD[$i]}" >> "$STATE"; line="$line #${OPEN[$i]} ${NEW[$i]:0:9}"; i=$((i+1)); done
    say "UPDATED ($MODE) from $DEFAULT $(git rev-parse --short "$UP") [$need]:$line${approved:+ | were approved before the push:$approved}"
    [ "$ONCE" = 1 ] && exit 0
    sleep 60
  else
    say "STOP push rejected, another writer moved a branch: $(tail -1 /tmp/autorebase-push.log)"; exit 1
  fi
  sleep "$INTERVAL"
done
say "STOP max runtime reached"; exit 0
