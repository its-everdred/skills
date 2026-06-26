#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: stop-pr-monitor.sh <pull-request-url> [--dir PATH] [--keep-hook]
USAGE
}

die() {
  echo "pr-monitor: $*" >&2
  exit 1
}

TARGET=""
ROOT_DIR="${PR_MONITOR_DIR:-/tmp/pr-monitor}"
KEEP_HOOK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      shift
      [[ $# -gt 0 ]] || die "--dir requires a path"
      ROOT_DIR="$1"
      ;;
    --dir=*)
      ROOT_DIR="${1#*=}"
      ;;
    --keep-hook)
      KEEP_HOOK=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      die "unknown option: $1"
      ;;
    *)
      [[ -z "$TARGET" ]] || die "unexpected argument: $1"
      TARGET="$1"
      ;;
  esac
  shift
done

[[ -n "$TARGET" ]] || {
  usage
  exit 1
}

if [[ "$TARGET" =~ github\.com[:/]([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]%.git}"
  PR_NUMBER="${BASH_REMATCH[3]}"
else
  die "target must be a GitHub pull request URL"
fi

KEY="${OWNER}-${REPO}-${PR_NUMBER}"
KEY="${KEY//[^A-Za-z0-9_.-]/-}"
STATE_DIR="$ROOT_DIR/$KEY"
CONFIG_FILE="$STATE_DIR/start-config.json"
LOCAL_TARGET=""
SMEE_URL=""

if [[ -f "$CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
  LOCAL_TARGET="$(jq -r '.localTarget // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  SMEE_URL="$(jq -r '.smeeUrl // empty' "$CONFIG_FILE" 2>/dev/null || true)"
fi

process_command() {
  ps -p "$1" -o command= 2>/dev/null || true
}

process_matches() {
  local pid="$1"
  local kind="$2"
  local command
  command="$(process_command "$pid")"
  case "$kind" in
    listener)
      [[ "$command" == *"pr-monitor-webhook.mjs"* && "$command" == *"https://github.com/$OWNER/$REPO/pull/$PR_NUMBER"* ]]
      ;;
    smee)
      if [[ -n "$LOCAL_TARGET" ]]; then
        [[ "$command" == *"smee-client"* && "$command" == *"$LOCAL_TARGET"* ]]
      elif [[ -n "$SMEE_URL" ]]; then
        [[ "$command" == *"smee-client"* && "$command" == *"$SMEE_URL"* ]]
      else
        [[ "$command" == *"smee-client"* ]]
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

stop_pid_file() {
  local file="$1"
  local kind="$2"
  if [[ -f "$file" ]]; then
    pid="$(tr -cd '0-9' <"$file" || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      if process_matches "$pid" "$kind"; then
        kill "$pid" 2>/dev/null || true
        echo "pr-monitor: stopped $kind pid $pid"
      else
        echo "pr-monitor: ignored stale $kind pid $pid with command: $(process_command "$pid")" >&2
      fi
    fi
    rm -f "$file"
  fi
}

stop_pid_file "$STATE_DIR/listener.pid" listener
stop_pid_file "$STATE_DIR/smee.pid" smee

if ! $KEEP_HOOK && [[ -f "$STATE_DIR/hook-id" ]]; then
  hook_id="$(tr -cd '0-9' <"$STATE_DIR/hook-id" || true)"
  if [[ -n "$hook_id" ]]; then
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 \
      && gh api "repos/$OWNER/$REPO/hooks/$hook_id" --method DELETE >/dev/null 2>&1; then
      rm -f "$STATE_DIR/hook-id"
      echo "pr-monitor: deleted repository webhook $hook_id"
    else
      echo "pr-monitor: could not delete repository webhook $hook_id; retry after gh auth or pass --keep-hook" >&2
    fi
  fi
fi

echo "pr-monitor: state kept at $STATE_DIR"
