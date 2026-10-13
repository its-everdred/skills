#!/usr/bin/env bash
# Print the context line for a reminder: which chat added it, where its full transcript
# is, and how to resume it, so a later agent can pull the whole conversation in one step.
# Run from the chat's working directory. Works in Claude Code and Codex.
set -u
tilde() { sed "s|^$HOME|~|"; }
cwd="$(pwd | tilde)"

if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
  id="$CLAUDE_CODE_SESSION_ID"
  conf="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  log="$(find -L "$conf/projects" -maxdepth 2 -name "$id.jsonl" 2>/dev/null | head -1 | tilde)"
  # A second account (switch-login) keeps its own config dir; resuming has to use it.
  env_prefix=""
  [ "$conf" != "$HOME/.claude" ] && env_prefix="CLAUDE_CONFIG_DIR=$(echo "$conf" | tilde) "
  line="ctx: claude $id · ${log:-transcript not found}"
  [ -n "${CLAUDE_CODE_BRIDGE_SESSION_ID:-}" ] && line+=" · https://claude.ai/code/$CLAUDE_CODE_BRIDGE_SESSION_ID"
  line+=" · resume: \`cd $cwd && ${env_prefix}claude --resume $id\`"
else
  # Codex: the newest rollout whose session started in this directory is this chat.
  log=""
  for f in $(ls -t "$HOME"/.codex/sessions/*/*/*/rollout-*.jsonl 2>/dev/null | head -50); do
    head -1 "$f" | grep -q "\"cwd\":\"$(pwd)\"" && { log="$f"; break; }
  done
  [ -z "$log" ] && { echo "ctx: unknown session · cwd $cwd"; exit 0; }
  id="$(basename "$log" .jsonl | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')"
  line="ctx: codex $id · $(echo "$log" | tilde) · resume: \`cd $cwd && codex resume $id\`"
fi
echo "$line"
