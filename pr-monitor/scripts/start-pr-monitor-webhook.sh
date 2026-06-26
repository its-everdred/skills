#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'USAGE'
Usage: start-pr-monitor-webhook.sh <pull-request-url> --thread ID --author LOGIN --yes-use-smee [options]

Starts a Smee-backed GitHub webhook bridge that wakes the same Codex thread with
`codex exec resume` when new PR review comments arrive.

Options:
  --thread ID             Codex session/thread id to resume.
  --port N                Local listener port. Default: choose a free port.
  --path PATH             Local webhook path. Default: /webhook.
  --dir PATH              State directory. Default: /tmp/pr-monitor.
  --smee-url URL          Existing Smee channel. Default: create one.
  --yes-use-smee          Confirm webhook payloads may pass through Smee.
  --secret VALUE          Webhook secret. Default: generate one.
  --author LOGIN          Only wake for comments from this login.
  --allow-any-author      Wake for any author. Use only for trusted repos.
  --ignore-author LOGIN   Ignore comments from this login. Repeatable.
  --catch-up-existing     Wake once for existing unhandled review threads.
  --no-baseline-existing  Do not mark current review comments as already seen.
  --autonomous            Prompt Codex to reply first, then implement if needed.
  --install-hook          Try to create a GitHub repository webhook.
  --keep-hook             Keep an installed repository webhook on stop/restart.
  --restart               Stop an existing monitor for this PR first.
  --dry-run               Do not run codex; log the resume prompt.
  --follow                Tail the monitor log after starting.
USAGE
}

die() {
  echo "pr-monitor: $*" >&2
  exit 1
}

script_dir() {
  local source="${BASH_SOURCE[0]}"
  while [[ -L "$source" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"
    source="$(readlink "$source")"
    [[ "$source" != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd
}

free_port() {
  node -e 'const net=require("node:net"); const s=net.createServer(); s.listen(0,"127.0.0.1",()=>{console.log(s.address().port); s.close();});'
}

random_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    node -e 'console.log(require("node:crypto").randomBytes(32).toString("hex"))'
  fi
}

parse_pr_url() {
  local target="$1"
  if [[ "$target" =~ github\.com[:/]([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]%.git}"
    PR_NUMBER="${BASH_REMATCH[3]}"
    PR_URL="https://github.com/$OWNER/$REPO/pull/$PR_NUMBER"
    return 0
  fi
  return 1
}

start_process() {
  local name="$1"
  local pid_file="$2"
  shift 2
  nohup "$@" >>"$LOG_FILE" 2>&1 </dev/null &
  local pid=$!
  printf '%s\n' "$pid" >"$pid_file"
  STARTED_PID_FILES+=("$pid_file")
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "pr-monitor: $name failed to start; last log lines:" >&2
    tail -n 80 "$LOG_FILE" >&2 || true
    exit 1
  fi
}

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
      [[ "$command" == *"pr-monitor-webhook.mjs"* && "$command" == *"$PR_URL"* ]]
      ;;
    smee)
      if [[ -n "${CONFIG_LOCAL_TARGET:-}" ]]; then
        [[ "$command" == *"smee-client"* && "$command" == *"$CONFIG_LOCAL_TARGET"* ]]
      elif [[ -n "$PORT" ]]; then
        [[ "$command" == *"smee-client"* && "$command" == *"127.0.0.1:$PORT$WEBHOOK_PATH"* ]]
      else
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

kill_pid_file() {
  local file="$1"
  local kind="$2"
  [[ -f "$file" ]] || return 0

  local pid
  pid="$(tr -cd '0-9' <"$file" || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    if process_matches "$pid" "$kind"; then
      kill "$pid" 2>/dev/null || true
    else
      echo "pr-monitor: ignoring stale $kind pid $pid with command: $(process_command "$pid")" >&2
    fi
  fi
  rm -f "$file"
}

delete_recorded_hook() {
  [[ -f "$HOOK_ID_FILE" ]] || return 0
  local hook_id
  hook_id="$(tr -cd '0-9' <"$HOOK_ID_FILE" || true)"
  [[ -n "$hook_id" ]] || {
    rm -f "$HOOK_ID_FILE"
    return 0
  }

  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh api "repos/$OWNER/$REPO/hooks/$hook_id" --method DELETE >/dev/null 2>&1; then
      rm -f "$HOOK_ID_FILE"
      echo "pr-monitor: deleted repository webhook $hook_id" | tee -a "$LOG_FILE"
      return 0
    fi
  fi

  echo "pr-monitor: could not delete recorded repository webhook $hook_id; retry with gh auth" | tee -a "$LOG_FILE" >&2
}

stop_existing() {
  kill_pid_file "$LISTENER_PID_FILE" listener
  kill_pid_file "$SMEE_PID_FILE" smee
  $KEEP_HOOK || delete_recorded_hook
}

cleanup_started() {
  local file
  for file in "${STARTED_PID_FILES[@]:-}"; do
    case "$(basename "$file")" in
      listener.pid) kill_pid_file "$file" listener ;;
      smee.pid) kill_pid_file "$file" smee ;;
    esac
  done
}

has_live_processes() {
  local live=false
  local pid
  if [[ -f "$LISTENER_PID_FILE" ]]; then
    pid="$(tr -cd '0-9' <"$LISTENER_PID_FILE" || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && process_matches "$pid" listener; then
      live=true
    else
      rm -f "$LISTENER_PID_FILE"
    fi
  fi
  if [[ -f "$SMEE_PID_FILE" ]]; then
    pid="$(tr -cd '0-9' <"$SMEE_PID_FILE" || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && process_matches "$pid" smee; then
      live=true
    else
      rm -f "$SMEE_PID_FILE"
    fi
  fi
  $live
}

create_smee_url() {
  curl -Ls -o /dev/null -w '%{url_effective}' https://smee.io/new
}

install_hook() {
  local response hook_id
  response="$(mktemp "${TMPDIR:-/tmp}/pr-monitor-hook.XXXXXX")"
  if ! jq -n \
    --arg url "$SMEE_URL" \
    --arg secret "$SECRET" \
    '{
      name: "web",
      active: true,
      events: ["pull_request_review_comment", "issue_comment", "pull_request_review"],
      config: {url: $url, content_type: "json", secret: $secret}
    }' \
    | gh api "repos/$OWNER/$REPO/hooks" --method POST --input - >"$response"
  then
    echo "pr-monitor: could not install repository webhook; add it manually if needed" | tee -a "$LOG_FILE"
    rm -f "$response"
    return 0
  fi

  hook_id="$(jq -r '.id // empty' "$response")"
  rm -f "$response"
  if [[ -n "$hook_id" ]]; then
    printf '%s\n' "$hook_id" >"$HOOK_ID_FILE"
    HOOK_INSTALLED=true
    echo "pr-monitor: installed repository webhook id $hook_id" | tee -a "$LOG_FILE"
  fi
}

TARGET=""
THREAD=""
PORT=""
WEBHOOK_PATH="/webhook"
ROOT_DIR="${PR_MONITOR_DIR:-/tmp/pr-monitor}"
SMEE_URL=""
SECRET=""
CONFIRM_SMEE=false
AUTHOR=""
ALLOW_ANY_AUTHOR=false
IGNORE_AUTHORS=()
CATCH_UP_EXISTING=false
BASELINE_EXISTING=true
AUTONOMOUS=false
INSTALL_HOOK=false
HOOK_INSTALLED=false
KEEP_HOOK=false
RESTART=false
DRY_RUN=false
FOLLOW=false
SMEE_CLIENT_PACKAGE="${SMEE_CLIENT_PACKAGE:-smee-client@5.0.0}"
STARTED_PID_FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --thread)
      shift
      [[ $# -gt 0 ]] || die "--thread requires a value"
      THREAD="$1"
      ;;
    --thread=*)
      THREAD="${1#*=}"
      ;;
    --last)
      die "--last is not supported for long-running monitors; pass a concrete --thread ID"
      ;;
    --port)
      shift
      [[ $# -gt 0 ]] || die "--port requires a value"
      PORT="$1"
      ;;
    --port=*)
      PORT="${1#*=}"
      ;;
    --path)
      shift
      [[ $# -gt 0 ]] || die "--path requires a value"
      WEBHOOK_PATH="$1"
      ;;
    --path=*)
      WEBHOOK_PATH="${1#*=}"
      ;;
    --dir)
      shift
      [[ $# -gt 0 ]] || die "--dir requires a path"
      ROOT_DIR="$1"
      ;;
    --dir=*)
      ROOT_DIR="${1#*=}"
      ;;
    --smee-url)
      shift
      [[ $# -gt 0 ]] || die "--smee-url requires a value"
      SMEE_URL="$1"
      ;;
    --smee-url=*)
      SMEE_URL="${1#*=}"
      ;;
    --yes-use-smee)
      CONFIRM_SMEE=true
      ;;
    --secret)
      shift
      [[ $# -gt 0 ]] || die "--secret requires a value"
      SECRET="$1"
      ;;
    --secret=*)
      SECRET="${1#*=}"
      ;;
    --author)
      shift
      [[ $# -gt 0 ]] || die "--author requires a value"
      AUTHOR="$1"
      ;;
    --author=*)
      AUTHOR="${1#*=}"
      ;;
    --allow-any-author)
      ALLOW_ANY_AUTHOR=true
      ;;
    --ignore-author)
      shift
      [[ $# -gt 0 ]] || die "--ignore-author requires a value"
      IGNORE_AUTHORS+=("$1")
      ;;
    --ignore-author=*)
      IGNORE_AUTHORS+=("${1#*=}")
      ;;
    --catch-up-existing)
      CATCH_UP_EXISTING=true
      ;;
    --no-baseline-existing)
      BASELINE_EXISTING=false
      ;;
    --autonomous)
      AUTONOMOUS=true
      ;;
    --install-hook)
      INSTALL_HOOK=true
      ;;
    --keep-hook)
      KEEP_HOOK=true
      ;;
    --restart)
      RESTART=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --follow)
      FOLLOW=true
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
parse_pr_url "$TARGET" || die "target must be a GitHub pull request URL"
[[ -n "$THREAD" ]] || die "pass --thread ID"
[[ -n "$AUTHOR" || "$ALLOW_ANY_AUTHOR" == true ]] || die "pass --author LOGIN or --allow-any-author"
[[ -z "$PORT" || "$PORT" =~ ^[0-9]+$ ]] || die "--port must be a positive integer"
[[ "$WEBHOOK_PATH" == /* ]] || die "--path must start with /"

command -v node >/dev/null 2>&1 || die "node is required"
command -v npx >/dev/null 2>&1 || die "npx is required"
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
if ! $DRY_RUN; then
  command -v codex >/dev/null 2>&1 || die "codex is required"
fi
if $INSTALL_HOOK; then
  command -v gh >/dev/null 2>&1 || die "gh is required for --install-hook"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated"
fi

SCRIPT_DIR="$(script_dir)"
LISTENER="$SCRIPT_DIR/pr-monitor-webhook.mjs"
[[ -f "$LISTENER" ]] || die "missing listener script: $LISTENER"

KEY="${OWNER}-${REPO}-${PR_NUMBER}"
KEY="${KEY//[^A-Za-z0-9_.-]/-}"
STATE_DIR="$ROOT_DIR/$KEY"
LOG_FILE="$STATE_DIR/monitor.log"
LISTENER_PID_FILE="$STATE_DIR/listener.pid"
SMEE_PID_FILE="$STATE_DIR/smee.pid"
HOOK_ID_FILE="$STATE_DIR/hook-id"
CONFIG_FILE="$STATE_DIR/start-config.json"
CONFIG_LOCAL_TARGET=""

mkdir -m 700 -p "$STATE_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

if [[ -f "$CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
  CONFIG_LOCAL_TARGET="$(jq -r '.localTarget // empty' "$CONFIG_FILE" 2>/dev/null || true)"
fi

if $RESTART && ! $KEEP_HOOK; then
  delete_recorded_hook
fi

if has_live_processes; then
  if ! $RESTART; then
    echo "pr-monitor: already configured for $PR_URL"
    echo "pr-monitor: state $STATE_DIR"
    echo "pr-monitor: log $LOG_FILE"
    echo "pr-monitor: pass --restart to replace it"
    $FOLLOW && tail -n 0 -F "$LOG_FILE"
    exit 0
  fi
  stop_existing
else
  rm -f "$LISTENER_PID_FILE" "$SMEE_PID_FILE"
fi

[[ -n "$PORT" ]] || PORT="$(free_port)"
if [[ -z "$SMEE_URL" || "$SMEE_URL" == "https://smee.io/new" ]]; then
  $CONFIRM_SMEE || die "Smee relays webhook payloads through a third-party service; pass --yes-use-smee to confirm"
  SMEE_URL="$(create_smee_url)"
fi
if [[ "$SMEE_URL" =~ ^https://smee\.io/ ]]; then
  $CONFIRM_SMEE || die "Smee relays webhook payloads through a third-party service; pass --yes-use-smee to confirm"
fi
[[ -n "$SECRET" ]] || SECRET="$(random_secret)"

IGNORE_ARGS=()
if [[ ${#IGNORE_AUTHORS[@]} -gt 0 ]]; then
  for login in "${IGNORE_AUTHORS[@]}"; do
    IGNORE_ARGS+=(--ignore-author "$login")
  done
fi
listener_args=(env PR_MONITOR_WEBHOOK_SECRET="$SECRET" node "$LISTENER" --pr-url "$PR_URL" --port "$PORT" --path "$WEBHOOK_PATH" --dir "$ROOT_DIR" --secret-env PR_MONITOR_WEBHOOK_SECRET)
listener_args+=(--thread "$THREAD")
[[ -n "$AUTHOR" ]] && listener_args+=(--author "$AUTHOR")
$ALLOW_ANY_AUTHOR && listener_args+=(--allow-any-author)
$CATCH_UP_EXISTING && listener_args+=(--catch-up-existing)
if ! $BASELINE_EXISTING; then
  listener_args+=(--no-baseline-existing)
fi
$AUTONOMOUS && listener_args+=(--autonomous)
$DRY_RUN && listener_args+=(--dry-run)
if [[ ${#IGNORE_ARGS[@]} -gt 0 ]]; then
  listener_args+=("${IGNORE_ARGS[@]}")
fi

smee_args=(npx -y "$SMEE_CLIENT_PACKAGE" --url "$SMEE_URL" --target "http://127.0.0.1:$PORT$WEBHOOK_PATH")

jq -n \
  --arg prUrl "$PR_URL" \
  --arg smeeUrl "$SMEE_URL" \
  --arg localTarget "http://127.0.0.1:$PORT$WEBHOOK_PATH" \
  --arg thread "$THREAD" \
  --arg stateDir "$STATE_DIR" \
  --arg startedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg smeeClientPackage "$SMEE_CLIENT_PACKAGE" \
  --argjson autonomous "$AUTONOMOUS" \
  --argjson baselineExisting "$BASELINE_EXISTING" \
  --argjson catchUpExisting "$CATCH_UP_EXISTING" \
  '{
    prUrl: $prUrl,
    smeeUrl: $smeeUrl,
    localTarget: $localTarget,
    secretConfigured: true,
    thread: $thread,
    stateDir: $stateDir,
    autonomous: $autonomous,
    baselineExisting: $baselineExisting,
    catchUpExisting: $catchUpExisting,
    smeeClientPackage: $smeeClientPackage,
    startedAt: $startedAt
  }' >"$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

trap 'status=$?; if [[ $status -ne 0 ]]; then cleanup_started; fi' EXIT

start_process "listener" "$LISTENER_PID_FILE" "${listener_args[@]}"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null || die "listener did not become healthy"
start_process "smee-client" "$SMEE_PID_FILE" "${smee_args[@]}"
$INSTALL_HOOK && install_hook
trap - EXIT

echo "pr-monitor: watching $PR_URL"
echo "pr-monitor: smee $SMEE_URL"
echo "pr-monitor: local target http://127.0.0.1:$PORT$WEBHOOK_PATH"
echo "pr-monitor: listener pid $(cat "$LISTENER_PID_FILE")"
echo "pr-monitor: smee pid $(cat "$SMEE_PID_FILE")"
echo "pr-monitor: state $STATE_DIR"
echo "pr-monitor: log $LOG_FILE"
if [[ "$HOOK_INSTALLED" != true ]]; then
  echo "pr-monitor: webhook secret $SECRET"
  echo "pr-monitor: add a GitHub webhook for $SMEE_URL with content_type application/json and events pull_request_review_comment, issue_comment, pull_request_review"
fi
echo "pr-monitor: stop with $SCRIPT_DIR/stop-pr-monitor.sh $PR_URL"

if $FOLLOW; then
  tail -n 0 -F "$LOG_FILE"
fi
