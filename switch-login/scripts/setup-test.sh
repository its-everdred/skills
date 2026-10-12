#!/usr/bin/env bash
# Self-check for setup.sh and the claude-login.sh wrapper. Everything runs
# against a temporary HOME; the real ~/.claude is never touched.
set -euo pipefail

HERE=$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REAL_HOME=$HOME
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
export HOME="$T/home" SHELL=/bin/bash
export XDG_RUNTIME_DIR="$T/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
[ "$HOME" != "$REAL_HOME" ] || { echo "refusing: HOME is the real home" >&2; exit 1; }

fails=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# A fake ~/.claude with some of the shared entries, per-account files that must
# never be linked, and an empty rc file.
mkdir -p "$HOME/.claude/skills" "$HOME/.claude/projects" "$HOME/.claude/sessions"
echo '{}' > "$HOME/.claude/settings.json"
echo '# rules' > "$HOME/.claude/CLAUDE.md"
echo '{"secret":1}' > "$HOME/.claude/.credentials.json"
echo '{}' > "$HOME/.claude/.claude.json"
: > "$HOME/.bashrc"
P="$HOME/.claude-2"

if bash "$HERE/setup.sh" / >/dev/null 2>&1; then fail "rejects / as the profile"; else ok "rejects / as the profile"; fi
if bash "$HERE/setup.sh" "$HOME" >/dev/null 2>&1; then fail "rejects HOME as the profile"; else ok "rejects HOME as the profile"; fi
if bash "$HERE/setup.sh" --name 'bad/name' >/dev/null 2>&1; then
  fail "rejects an unsafe account name"
else
  ok "rejects an unsafe account name"
fi
check "unsafe account name changes nothing" '[ ! -s "$HOME/.bashrc" ]'

out1=$(bash "$HERE/setup.sh" --name work 2>&1)
out2=$(bash "$HERE/setup.sh" --name work 2>&1)

for f in CLAUDE.md settings.json skills projects; do
  check "links $f" '[ -L "$P/$f" ] && [ "$(readlink "$P/$f")" = "$HOME/.claude/$f" ]'
done
for f in plugins todos file-history history.jsonl session-env shell-snapshots; do
  check "skips missing $f" '[ ! -e "$P/$f" ] && [ ! -L "$P/$f" ]'
done
for f in .credentials.json .claude.json sessions; do
  check "does not create $f" '[ ! -e "$P/$f" ] && [ ! -L "$P/$f" ]'
done
check "never prints credential contents" '! grep -q secret <<<"$out1$out2"'
check "export line appears once after two runs" \
  '[ "$(grep -cxF "export CLAUDE_LOGIN2_DIR=\"$P\"" "$HOME/.bashrc")" = 1 ]'
check "source line appears once after two runs" \
  '[ "$(grep -cxF "source \"\$HOME/.claude/skills/switch-login/claude-login.sh\"" "$HOME/.bashrc")" = 1 ]'
check "account name appears once after two runs" \
  '[ "$(grep -cxF "export CLAUDE_LOGIN2_NAME=\"work\"" "$HOME/.bashrc")" = 1 ]'
check "rc backed up before the first edit" 'ls "$HOME"/.bashrc.bak.* >/dev/null 2>&1'
check "only one backup after two runs" '[ "$(ls "$HOME"/.bashrc.bak.* | wc -l)" = 1 ]'
check "skill installed" '[ -f "$HOME/.claude/skills/switch-login/claude-login.sh" ]'
check "second run says nothing changed" 'grep -q "nothing changed" <<<"$out2"'
check "prints the login step" 'grep -q "/login" <<<"$out1"'

printf '# stale\n' > "$HOME/.claude/skills/switch-login/claude-login.sh"
out3=$(bash "$HERE/setup.sh" --name work 2>&1)
check "refreshes an older installed skill" \
  'cmp -s "$HERE/../claude-login.sh" "$HOME/.claude/skills/switch-login/claude-login.sh"'
check "reports the skill refresh" 'grep -q "updated the skill" <<<"$out3"'

# Refusals: each leaves the found path untouched and exits non-zero.
rm -f "$P/settings.json"; echo real > "$P/settings.json"
if bash "$HERE/setup.sh" >/dev/null 2>&1; then fail "refuses a real file where a link belongs"; else ok "refuses a real file where a link belongs"; fi
check "leaves that file alone" '[ "$(cat "$P/settings.json")" = real ]'
rm -f "$P/settings.json"; ln -s "$HOME/.claude/settings.json" "$P/settings.json"

printf 'export CLAUDE_LOGIN2_DIR="/somewhere/else"\n' >> "$HOME/.bashrc"
before=$(cat "$HOME/.bashrc")
if out=$(bash "$HERE/setup.sh" 2>&1); then fail "refuses a different CLAUDE_LOGIN2_DIR"; else ok "refuses a different CLAUDE_LOGIN2_DIR"; fi
check "prints what it found" 'grep -q "/somewhere/else" <<<"$out"'
check "leaves the rc file alone" '[ "$(cat "$HOME/.bashrc")" = "$before" ]'

# Wrapper: a fake claude that asks for a switch on its first run, then records
# the arguments of the resumed run.
mkdir -p "$T/bin"
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
if [ ! -e "$T/ran" ]; then
  : > "$T/ran"
  printf '%s\n' "$CLAUDE_SWITCH_FILE" > "$T/switch-path"
  printf 'sess-1\nrc\n' > "$CLAUDE_SWITCH_FILE"
  exit 0
fi
printf '%s\n' "${CLAUDE_CONFIG_DIR:-default}" "$@" > "$T/args"
EOF
chmod +x "$T/bin/claude"
export T PATH="$T/bin:$PATH" CLAUDE_LOGIN2_DIR="$P"
export CLAUDE_LOGIN2_NAME=work
bash -c 'source "$1"; claude --dangerously-skip-permissions --resume old-id -c' _ "$HERE/../claude-login.sh" >/dev/null
check "wrapper resumes on the second profile" '[ "$(sed -n 1p "$T/args")" = "$P" ]'
check "wrapper keeps permission flags and swaps the session" \
  '[ "$(sed -n "2,\$p" "$T/args" | tr "\n" " ")" = "--dangerously-skip-permissions --resume sess-1 --remote-control " ]'
check "wrapper creates the switch file in the runtime directory" \
  'case "$(cat "$T/switch-path")" in "$XDG_RUNTIME_DIR"/claude-switch.*) true ;; *) false ;; esac'
check "wrapper removes the switch file" '[ ! -e "$(cat "$T/switch-path")" ]'

rm -f "$T/ran"
mkdir -p "$T/read-only-runtime"; chmod 500 "$T/read-only-runtime"
XDG_RUNTIME_DIR="$T/read-only-runtime" \
  bash -c 'source "$1"; claude --version' _ "$HERE/../claude-login.sh" >/dev/null
check "wrapper falls back when XDG_RUNTIME_DIR is not writable" \
  'case "$(cat "$T/switch-path")" in /tmp/claude-switch.*) true ;; *) false ;; esac'
check "wrapper removes the fallback switch file" '[ ! -e "$(cat "$T/switch-path")" ]'

# The optional named command is intentionally equivalent to claude2. It gives
# each machine a memorable command without introducing a third profile.
bash -c 'source "$1"; claude-work --version' _ "$HERE/../claude-login.sh" >/dev/null
check "named command uses the second profile" '[ "$(sed -n 1p "$T/args")" = "$P" ]'
check "named command forwards arguments" '[ "$(sed -n 2p "$T/args")" = --version ]'

# CLAUDE_PID is normally supplied by Claude Code, but it still crosses a shell
# boundary. Reject non-numeric values before building a delayed process signal.
if CLAUDE_CODE_SESSION_ID=sess-1 CLAUDE_PID='2;touch bad' CLAUDE_SWITCH_FILE="$T/switch" \
  bash "$HERE/switch.sh" >/dev/null 2>&1; then
  fail "switch rejects a non-numeric Claude PID"
else
  ok "switch rejects a non-numeric Claude PID"
fi
check "invalid PID does not create a switch request" '[ ! -e "$T/switch" ]'

# The new-chat launcher must select the second wrapper and preserve Remote
# Control without needing a real tmux server in CI.
cat > "$T/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  new-session) printf '%s\n' "$@" > "$T/tmux-args" ;;
  has-session) exit 0 ;;
  capture-pane) printf '%s\n' '? for shortcuts' 'https://claude.ai/code/session_Test123' ;;
  send-keys) ;;
  *) echo "unexpected tmux command: $1" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/bin/tmux"
new_out=$("$HERE/../../new/scripts/new-chat.sh" --account second "$T" 2>&1)
check "new chat selects the second-account wrapper" \
  'grep -qx claude2 "$T/tmux-args" && grep -qx "CLAUDE_LOGIN2_DIR=$P" "$T/tmux-args"'
check "new chat enables Remote Control" \
  'grep -qx -- --remote-control "$T/tmux-args" && grep -q "remote:  https://claude.ai/code/session_Test123" <<<"$new_out"'

echo
if [ "$fails" -eq 0 ]; then echo "all checks passed"; else echo "$fails check(s) failed"; exit 1; fi
