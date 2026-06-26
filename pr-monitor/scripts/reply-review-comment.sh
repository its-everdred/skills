#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: reply-review-comment.sh <pull-request-url> <review-comment-id> (--body TEXT | --body-file PATH)

Replies to an existing pull request review comment and verifies by re-fetching
the thread-shaped comment list. The script does not resolve review threads.
USAGE
}

die() {
  echo "pr-monitor: $*" >&2
  exit 1
}

PR_URL=""
COMMENT_ID=""
BODY=""
BODY_FILE=""
GH_BIN="${GH_BIN:-gh}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --body)
      shift
      [[ $# -gt 0 ]] || die "--body requires text"
      BODY="$1"
      ;;
    --body=*)
      BODY="${1#*=}"
      ;;
    --body-file)
      shift
      [[ $# -gt 0 ]] || die "--body-file requires a path"
      BODY_FILE="$1"
      ;;
    --body-file=*)
      BODY_FILE="${1#*=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      die "unknown option: $1"
      ;;
    *)
      if [[ -z "$PR_URL" ]]; then
        PR_URL="$1"
      elif [[ -z "$COMMENT_ID" ]]; then
        COMMENT_ID="$1"
      else
        die "unexpected argument: $1"
      fi
      ;;
  esac
  shift
done

[[ -n "$PR_URL" && -n "$COMMENT_ID" ]] || {
  usage
  exit 1
}
[[ "$COMMENT_ID" =~ ^[0-9]+$ ]] || die "review-comment-id must be numeric"
[[ -n "$BODY" || -n "$BODY_FILE" ]] || die "pass --body or --body-file"
[[ -z "$BODY" || -z "$BODY_FILE" ]] || die "pass only one of --body or --body-file"

if [[ -n "$BODY_FILE" ]]; then
  [[ -f "$BODY_FILE" ]] || die "body file does not exist: $BODY_FILE"
  BODY="$(cat "$BODY_FILE")"
fi
[[ -n "$BODY" ]] || die "reply body must not be empty"

if [[ "$PR_URL" =~ github\.com[:/]([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]%.git}"
  PR_NUMBER="${BASH_REMATCH[3]}"
else
  die "could not parse pull request URL: $PR_URL"
fi

command -v "$GH_BIN" >/dev/null 2>&1 || die "$GH_BIN is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
"$GH_BIN" auth status >/dev/null 2>&1 || die "$GH_BIN is not authenticated"

BOT_LOGIN="$("$GH_BIN" api user --jq .login)"
ORIGINAL="$("$GH_BIN" api "repos/$OWNER/$REPO/pulls/comments/$COMMENT_ID")"
ROOT_ID="$(jq -r '.in_reply_to_id // .id' <<<"$ORIGINAL")"

RESPONSE="$("$GH_BIN" api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies" \
  --method POST \
  -f body="$BODY")"
REPLY_ID="$(jq -r '.id' <<<"$RESPONSE")"

for attempt in 1 2 3; do
  COMMENTS="$("$GH_BIN" api --paginate "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" --jq '.[]')"
  VERIFIED="$(jq -s --argjson root "$ROOT_ID" --argjson reply "$REPLY_ID" --arg author "$BOT_LOGIN" --arg body "$BODY" '
    map(select(.id == $root or .in_reply_to_id == $root))
    | map(select(.id == $reply and .user.login == $author and .body == $body))
    | first // {}
  ' <<<"$COMMENTS")"

  verified_id="$(jq -r '.id // empty' <<<"$VERIFIED")"
  verified_author="$(jq -r '.user.login // empty' <<<"$VERIFIED")"

  if [[ "$verified_id" == "$REPLY_ID" && "$verified_author" == "$BOT_LOGIN" ]]; then
    jq -n \
      --arg status "verified" \
      --arg reply_id "$REPLY_ID" \
      --arg author "$verified_author" \
      --arg url "$(jq -r '.html_url' <<<"$RESPONSE")" \
      '{status: $status, reply_id: $reply_id, author: $author, url: $url}'
    exit 0
  fi

  sleep "$attempt"
done

die "reply was posted but thread verification failed for comment $COMMENT_ID"
