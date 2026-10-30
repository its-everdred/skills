#!/usr/bin/env bash
# Local-fixture regression tests for sync.sh and sync-external.sh. No network, HOME is a temp dir.
# Usage: skill-sync/tests/sync-test.sh
set -eu
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }
g() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

export HOME="$T/home"; mkdir -p "$HOME/.claude" "$HOME/.codex"

# upstream third-party repo with a skills/ subpath
UP="$T/upstream"; mkdir -p "$UP/skills/sec"; echo v1 > "$UP/skills/sec/SKILL.md"
g -C "$UP" init -q -b main; g -C "$UP" config uploadpack.allowAnySHA1InWant true
g -C "$UP" add -A; g -C "$UP" commit -qm init
SHA="$(g -C "$UP" rev-parse HEAD)"

# bare origin + the skills checkout under test
g init -q --bare -b main "$T/origin.git"
REPO="$T/skills"; mkdir -p "$REPO/mine"; echo x > "$REPO/mine/SKILL.md"
cp "$SRC/sync-external.sh" "$REPO/"
cat > "$T/manifest.json" <<EOF
{"shared":{"skills":[{"repo":"$UP","ref":"$SHA","subpath":"skills","dest":"~/.agents/skills"}]}}
EOF
g -C "$REPO" init -q -b main; g -C "$REPO" remote add origin "$T/origin.git"
g -C "$REPO" add -A; g -C "$REPO" commit -qm init; g -C "$REPO" push -q -u origin main
export SKILLS_REPO="$REPO" EXTERNAL_MANIFEST="$T/manifest.json"
SYNC="$SRC/skill-sync/scripts/sync.sh"

# 1. shared install + claude link + local skill links to all three targets
out="$("$SYNC")"
[ -f "$HOME/.agents/skills/sec/SKILL.md" ] || fail "shared skill not installed"
[ -L "$HOME/.claude/skills/sec" ] || fail "shared skill not linked into claude"
for d in .claude .codex .agents; do [ -L "$HOME/$d/skills/mine" ] || fail "mine not linked in $d"; done
ok "shared install and local links"

# 2. idempotent: second run prints nothing
[ -z "$("$SYNC")" ] || fail "second run not silent"
ok "idempotent"

# 3. differing existing skill preserved and reported
echo local > "$HOME/.agents/skills/sec/SKILL.md"
out="$("$SYNC")"
grep -q 'shared: skip sec' <<<"$out" || fail "conflict not reported: $out"
[ "$(cat "$HOME/.agents/skills/sec/SKILL.md")" = local ] || fail "conflict overwritten"
ok "conflict preserved"

# 4. deleted owned skill unlinks from every target
g -C "$REPO" rm -rq mine; g -C "$REPO" commit -qm rm; g -C "$REPO" push -q origin main; rm -rf "$REPO/mine"
"$SYNC" >/dev/null
for d in .claude .codex .agents; do [ ! -e "$HOME/$d/skills/mine" ] && [ ! -L "$HOME/$d/skills/mine" ] || fail "mine not unlinked in $d"; done
ok "deleted link removed"

# 5. pull works with no `timeout` binary on PATH
mkdir -p "$T/bin"
for c in git python3 jq bash dirname basename sort grep sed ln rm mkdir readlink diff cmp cp mktemp cat printf; do
  p="$(command -v "$c")" && ln -sf "$p" "$T/bin/$c"
done
CL="$T/clone"; g clone -q "$T/origin.git" "$CL"; mkdir "$CL/new"; echo n > "$CL/new/SKILL.md"
g -C "$CL" add -A; g -C "$CL" commit -qm new; g -C "$CL" push -q origin main
PATH="$T/bin" "$SYNC" >/dev/null
[ -f "$REPO/new/SKILL.md" ] || fail "pull did not happen without timeout"
[ -L "$HOME/.agents/skills/new" ] || fail "pulled skill not linked"
ok "pull without timeout CLI"

# 6. failed external sync is reported
echo '{"shared":{"skills":[{"repo":"/nonexistent","ref":"abc","subpath":"skills"}]}}' > "$T/bad.json"
out="$(EXTERNAL_MANIFEST="$T/bad.json" "$SYNC")"
grep -q 'shared: .*FAILED' <<<"$out" || fail "failure not reported: $out"
ok "failure reported"

# 7. guidance file is linked into ~/.agents
echo v1 > "$HOME/.agents/skills/sec/SKILL.md"   # undo test 3 so only guidance output is left
mkdir -p "$REPO/guidance"; echo g1 > "$REPO/guidance/pre.md"
out="$("$SYNC")"
grep -q 'linked guidance pre' <<<"$out" || fail "guidance not linked: $out"
[ -L "$HOME/.agents/pre.md" ] || fail "guidance link missing"
out="$("$SYNC")"; [ -z "$out" ] || fail "guidance second run not silent: $out"
ok "guidance linked"

# 8. an identical real file is replaced by the link
rm "$HOME/.agents/pre.md"; cp "$REPO/guidance/pre.md" "$HOME/.agents/pre.md"
out="$("$SYNC")"
grep -q 'linked guidance pre' <<<"$out" || fail "identical file not replaced: $out"
[ -L "$HOME/.agents/pre.md" ] || fail "identical file still real"
ok "identical guidance file replaced"

# 9. a differing real file is kept and reported
rm "$HOME/.agents/pre.md"; echo mine > "$HOME/.agents/pre.md"
out="$("$SYNC")"
grep -q 'guidance: pre differs from the repo copy, kept' <<<"$out" || fail "differing file not reported: $out"
[ ! -L "$HOME/.agents/pre.md" ] && [ "$(cat "$HOME/.agents/pre.md")" = mine ] || fail "differing file overwritten"
ok "differing guidance file kept"

# 10. a guidance link to a deleted file is removed
rm "$HOME/.agents/pre.md"; ln -s "$REPO/guidance/pre.md" "$HOME/.agents/pre.md"; rm "$REPO/guidance/pre.md"
out="$("$SYNC")"
grep -q 'unlinked guidance pre' <<<"$out" || fail "dangling guidance link not removed: $out"
[ ! -L "$HOME/.agents/pre.md" ] || fail "dangling guidance link still there"
ok "deleted guidance link removed"

# 11. install links Codex and imports into Claude, idempotently, never replacing a real AGENTS.md
echo p > "$REPO/guidance/coding-principles.md"
export HOME="$T/home2"; mkdir -p "$HOME/.claude" "$HOME/.codex"; echo mine > "$HOME/.claude/CLAUDE.md"
"$SRC/skill-sync/scripts/install.sh" >/dev/null
[ "$(cat "$HOME/.codex/AGENTS.md")" = p ] && [ -L "$HOME/.codex/AGENTS.md" ] || fail "codex AGENTS.md not linked"
grep -qxF '@~/.agents/coding-principles.md' "$HOME/.claude/CLAUDE.md" || fail "claude import missing"
[ "$(cat "$HOME/.claude/CLAUDE.md.bak")" = mine ] || fail "claude backup missing"
"$SRC/skill-sync/scripts/install.sh" >/dev/null
[ "$(grep -cxF '@~/.agents/coding-principles.md' "$HOME/.claude/CLAUDE.md")" = 1 ] || fail "import duplicated"
rm "$HOME/.codex/AGENTS.md"; echo real > "$HOME/.codex/AGENTS.md"
"$SRC/skill-sync/scripts/install.sh" >/dev/null
[ ! -L "$HOME/.codex/AGENTS.md" ] && [ "$(cat "$HOME/.codex/AGENTS.md")" = real ] || fail "real AGENTS.md replaced"
ok "install wires guidance"
