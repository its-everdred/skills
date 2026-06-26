#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: status-pr-monitor.sh <pull-request-url> [--dir PATH]
USAGE
}

die() {
  echo "pr-monitor: $*" >&2
  exit 1
}

TARGET=""
ROOT_DIR="${PR_MONITOR_DIR:-/tmp/pr-monitor}"

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
PR_URL="https://github.com/$OWNER/$REPO/pull/$PR_NUMBER"
LOCAL_TARGET=""
SMEE_URL=""

if [[ ! -d "$STATE_DIR" ]]; then
  echo "pr-monitor: no state for $TARGET"
  exit 1
fi

echo "pr-monitor: state $STATE_DIR"
if [[ -f "$CONFIG_FILE" ]]; then
  jq . "$CONFIG_FILE"
  LOCAL_TARGET="$(jq -r '.localTarget // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  SMEE_URL="$(jq -r '.smeeUrl // empty' "$CONFIG_FILE" 2>/dev/null || true)"
fi

process_command() {
  ps -p "$1" -o command= 2>/dev/null || true
}

process_matches() {
  local pid="$1"
  local name="$2"
  local command
  command="$(process_command "$pid")"
  case "$name" in
    listener)
      [[ "$command" == *"pr-monitor-webhook.mjs"* && "$command" == *"$PR_URL"* ]]
      ;;
    smee)
      if [[ -n "$LOCAL_TARGET" ]]; then
        [[ "$command" == *"smee-client"* && "$command" == *"$LOCAL_TARGET"* ]]
      elif [[ -n "$SMEE_URL" ]]; then
        [[ "$command" == *"smee-client"* && "$command" == *"$SMEE_URL"* ]]
      else
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

for name in listener smee; do
  file="$STATE_DIR/$name.pid"
  if [[ -f "$file" ]]; then
    pid="$(tr -cd '0-9' <"$file" || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && process_matches "$pid" "$name"; then
      echo "pr-monitor: $name running pid $pid"
    elif [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "pr-monitor: $name stale pid $pid"
    else
      echo "pr-monitor: $name stopped"
    fi
  else
    echo "pr-monitor: $name pid missing"
  fi
done

if [[ -f "$STATE_DIR/events.jsonl" ]]; then
  echo "pr-monitor: recent events"
  tail -n 10 "$STATE_DIR/events.jsonl"
fi
