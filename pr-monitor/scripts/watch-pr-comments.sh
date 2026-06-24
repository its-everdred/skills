#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: watch-pr-comments.sh <pull-request-url> [--interval N] [--include-existing] [--once] [--state PATH] [--author LOGIN]

Watches a GitHub pull request for new inline review comments, review bodies,
and top-level conversation comments. Existing comments are captured as the
initial baseline unless --include-existing is provided.
USAGE
}

die() {
  echo "pr-monitor: $*" >&2
  exit 1
}

PR_URL=""
INTERVAL=15
INCLUDE_EXISTING=false
RUN_ONCE=false
STATE_FILE=""
AUTHOR_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)
      shift
      [[ $# -gt 0 ]] || die "--interval requires a value"
      INTERVAL="$1"
      ;;
    --interval=*)
      INTERVAL="${1#*=}"
      ;;
    --include-existing)
      INCLUDE_EXISTING=true
      ;;
    --once)
      RUN_ONCE=true
      ;;
    --state)
      shift
      [[ $# -gt 0 ]] || die "--state requires a path"
      STATE_FILE="$1"
      ;;
    --state=*)
      STATE_FILE="${1#*=}"
      ;;
    --author)
      shift
      [[ $# -gt 0 ]] || die "--author requires a GitHub login"
      AUTHOR_FILTER="$1"
      ;;
    --author=*)
      AUTHOR_FILTER="${1#*=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      die "unknown option: $1"
      ;;
    *)
      [[ -z "$PR_URL" ]] || die "unexpected argument: $1"
      PR_URL="$1"
      ;;
  esac
  shift
done

[[ -n "$PR_URL" ]] || {
  usage
  exit 1
}
[[ "$INTERVAL" =~ ^[0-9]+$ && "$INTERVAL" -gt 0 ]] ||
  die "--interval must be a positive integer"

if [[ "$PR_URL" =~ github\.com[:/]([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]%.git}"
  PR_NUMBER="${BASH_REMATCH[3]}"
else
  die "could not parse pull request URL: $PR_URL"
fi

command -v gh >/dev/null 2>&1 || die "gh is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated"

if [[ -z "$STATE_FILE" ]]; then
  CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/pr-monitor"
  mkdir -p "$CACHE_ROOT"
  STATE_FILE="$CACHE_ROOT/${OWNER}-${REPO}-${PR_NUMBER}.seen"
fi
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"

TMP_DIR="${TMPDIR:-/tmp}"

fetch_events() {
  local raw review_comments issue_comments reviews
  raw=$(mktemp "$TMP_DIR/pr-monitor.raw.XXXXXX")
  review_comments=$(mktemp "$TMP_DIR/pr-monitor.review-comments.XXXXXX")
  issue_comments=$(mktemp "$TMP_DIR/pr-monitor.issue-comments.XXXXXX")
  reviews=$(mktemp "$TMP_DIR/pr-monitor.reviews.XXXXXX")

  gh api --paginate "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" \
    --jq '.[]' >"$review_comments"
  gh api --paginate "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" \
    --jq '.[]' >"$issue_comments"
  gh api --paginate "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
    --jq '.[] | select((.body // "") != "")' >"$reviews"

  jq -c '
    {
      key: ("review-comment:" + (.id|tostring)),
      type: "inline",
      created_at,
      author: .user.login,
      url: .html_url,
      path,
      line: (.line // .original_line),
      body
    }
  ' "$review_comments" >>"$raw"

  jq -c '
    {
      key: ("conversation:" + (.id|tostring)),
      type: "conversation",
      created_at,
      author: .user.login,
      url: .html_url,
      path: null,
      line: null,
      body
    }
  ' "$issue_comments" >>"$raw"

  jq -c '
    {
      key: ("review:" + (.id|tostring)),
      type: "review",
      created_at: .submitted_at,
      author: .user.login,
      url: .html_url,
      path: null,
      line: null,
      body
    }
  ' "$reviews" >>"$raw"

  if [[ -n "$AUTHOR_FILTER" ]]; then
    jq -s -c --arg author "$AUTHOR_FILTER" \
      'sort_by(.created_at, .key)[] | select(.author == $author)' "$raw"
  else
    jq -s -c 'sort_by(.created_at, .key)[]' "$raw"
  fi

  rm -f "$raw" "$review_comments" "$issue_comments" "$reviews"
}

print_event() {
  local event="$1"
  local type author created url path line body
  type=$(jq -r '.type' <<<"$event")
  author=$(jq -r '.author' <<<"$event")
  created=$(jq -r '.created_at' <<<"$event")
  url=$(jq -r '.url' <<<"$event")
  path=$(jq -r '.path // ""' <<<"$event")
  line=$(jq -r '.line // ""' <<<"$event")
  body=$(jq -r '.body // ""' <<<"$event")

  printf '\n[%s] new %s comment by %s\n' "$created" "$type" "$author"
  if [[ -n "$path" ]]; then
    printf 'location: %s' "$path"
    [[ -n "$line" ]] && printf ':%s' "$line"
    printf '\n'
  fi
  printf 'url: %s\n' "$url"
  printf '%s\n' "$body"
  printf '%s\n' '---'
}

seen() {
  local key="$1"
  grep -Fxq "$key" "$STATE_FILE"
}

mark_seen() {
  local key="$1"
  printf '%s\n' "$key" >>"$STATE_FILE"
}

echo "pr-monitor: watching https://github.com/$OWNER/$REPO/pull/$PR_NUMBER"
echo "pr-monitor: polling every ${INTERVAL}s"
echo "pr-monitor: state $STATE_FILE"
[[ -n "$AUTHOR_FILTER" ]] && echo "pr-monitor: filtering author $AUTHOR_FILTER"

initial_events=$(fetch_events)
initial_count=0
while IFS= read -r event; do
  [[ -n "$event" ]] || continue
  key=$(jq -r '.key' <<<"$event")
  if ! seen "$key"; then
    mark_seen "$key"
    initial_count=$((initial_count + 1))
    if $INCLUDE_EXISTING; then
      print_event "$event"
    fi
  fi
done <<<"$initial_events"

if ! $INCLUDE_EXISTING; then
  echo "pr-monitor: captured $initial_count existing comment(s) as baseline"
fi

if $RUN_ONCE; then
  exit 0
fi

while true; do
  sleep "$INTERVAL"
  events=$(fetch_events)
  while IFS= read -r event; do
    [[ -n "$event" ]] || continue
    key=$(jq -r '.key' <<<"$event")
    if seen "$key"; then
      continue
    fi
    mark_seen "$key"
    print_event "$event"
  done <<<"$events"
done
