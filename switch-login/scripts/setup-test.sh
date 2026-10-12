#!/usr/bin/env bash
# Self-check for setup.sh and the claude-login.sh wrapper. Everything runs
# against a temporary HOME; the real ~/.claude is never touched.
set -euo pipefail

HERE=$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REAL_HOME=$HOME
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
export HOME="$T/home" SHELL=/bin/bash
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

out1=$(bash "$HERE/setup.sh" 2>&1)
out2=$(bash "$HERE/setup.sh" 2>&1)

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
check "rc backed up before the first edit" 'ls "$HOME"/.bashrc.bak.* >/dev/null 2>&1'
check "only one backup after two runs" '[ "$(ls "$HOME"/.bashrc.bak.* | wc -l)" = 1 ]'
check "skill installed" '[ -f "$HOME/.claude/skills/switch-login/claude-login.sh" ]'
check "second run says nothing changed" 'grep -q "nothing changed" <<<"$out2"'
check "prints the login step" 'grep -q "/login" <<<"$out1"'

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
if [ ! -e "$T/ran" ]; then : > "$T/ran"; printf 'sess-1\nrc\n' > "$CLAUDE_SWITCH_FILE"; exit 0; fi
printf '%s\n' "${CLAUDE_CONFIG_DIR:-default}" "$@" > "$T/args"
EOF
chmod +x "$T/bin/claude"
export T PATH="$T/bin:$PATH" CLAUDE_LOGIN2_DIR="$P"
bash -c 'source "$1"; claude --dangerously-skip-permissions --resume old-id -c' _ "$HERE/../claude-login.sh" >/dev/null
check "wrapper resumes on the second profile" '[ "$(sed -n 1p "$T/args")" = "$P" ]'
check "wrapper keeps permission flags and swaps the session" \
  '[ "$(sed -n "2,\$p" "$T/args" | tr "\n" " ")" = "--dangerously-skip-permissions --resume sess-1 --remote-control " ]'

echo
if [ "$fails" -eq 0 ]; then echo "all checks passed"; else echo "$fails check(s) failed"; exit 1; fi
