// Run with: node --test scripts/cascade.test.mjs
import assert from 'node:assert/strict'
import { execFileSync, spawnSync } from 'node:child_process'
import { mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'

const SCRIPT = new URL('./cascade.mjs', import.meta.url).pathname

const git = (cwd, ...args) =>
  execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim()

function commit(cwd, file, text) {
  writeFileSync(join(cwd, file), text)
  git(cwd, 'add', '-A')
  git(cwd, 'commit', '-qm', `edit ${file}`)
}

// origin plus a clone with develop <- a <- b <- c, one commit each, all pushed.
function makeStack() {
  const root = mkdtempSync(join(tmpdir(), 'cascade-test-'))
  const origin = join(root, 'origin.git')
  const work = join(root, 'work')
  git(root, 'init', '-q', '--bare', '-b', 'develop', origin)
  git(root, 'clone', '-q', origin, work)
  git(work, 'config', 'user.email', 't@example.com')
  git(work, 'config', 'user.name', 't')
  git(work, 'checkout', '-q', '-b', 'develop')
  commit(work, 'base.txt', 'base')
  git(work, 'push', '-q', 'origin', 'develop')
  for (const [name, parent] of [['a', 'develop'], ['b', 'a'], ['c', 'b']]) {
    git(work, 'checkout', '-q', '-b', name, parent)
    commit(work, `${name}.txt`, name)
    git(work, 'push', '-q', 'origin', name)
  }
  return { work }
}

const run = (work, ...args) =>
  spawnSync('node', [SCRIPT, ...args], { cwd: work, encoding: 'utf8' })

function rewriteParent(work) {
  const oldTip = git(work, 'rev-parse', 'a')
  git(work, 'checkout', '-q', 'a')
  commit(work, 'a.txt', 'a amended')
  git(work, 'commit', '-q', '--amend', '--no-edit')
  git(work, 'push', '-q', '--force', 'origin', 'a')
  return oldTip
}

test('rebase cascades children onto a rewritten parent without merge commits', () => {
  const { work } = makeStack()
  const oldTip = rewriteParent(work)
  const dry = run(work, 'rebase', 'a', 'b', 'c', '--parent-old', oldTip)
  assert.equal(dry.status, 0, dry.stderr)
  assert.match(dry.stdout, /dry run/)
  assert.equal(git(work, 'rev-parse', 'origin/b'), git(work, 'rev-parse', 'b'))
  const result = run(work, 'rebase', 'a', 'b', 'c', '--parent-old', oldTip, '--push')
  assert.equal(result.status, 0, result.stderr)
  git(work, 'fetch', '-q', 'origin')
  assert.equal(git(work, 'rev-list', '--count', 'origin/a..origin/b'), '1')
  assert.equal(git(work, 'rev-list', '--count', 'origin/b..origin/c'), '1')
  assert.equal(git(work, 'rev-list', '--merges', '--count', 'origin/develop..origin/c'), '0')
})

test('merge strategy is refused for a child with no approval to keep', () => {
  const { work } = makeStack()
  const oldTip = rewriteParent(work)
  const result = run(work, 'rebase', 'a', 'b', 'c', '--parent-old', oldTip, '--merge')
  assert.equal(result.status, 1)
  assert.match(result.stderr, /--merge refused/)
})

test('a child that does not contain the old parent tip is rejected', () => {
  const { work } = makeStack()
  const result = run(work, 'rebase', 'a', 'b', 'c', '--parent-old', git(work, 'rev-parse', 'develop~0'))
  assert.equal(result.status, 0) // develop's tip is an ancestor of b, so this boundary is valid
  const bogus = run(work, 'rebase', 'a', 'b', 'c', '--parent-old', 'c')
  assert.equal(bogus.status, 1)
  assert.match(bogus.stderr, /does not contain the old parent tip/)
})

test('preflight passes a clean stack and fails one with a merge commit', () => {
  const { work } = makeStack()
  const clean = run(work, 'preflight', 'a', 'b', 'c')
  assert.equal(clean.status, 0, clean.stdout)
  git(work, 'checkout', '-q', 'develop')
  commit(work, 'later.txt', 'later')
  git(work, 'push', '-q', 'origin', 'develop')
  git(work, 'checkout', '-q', 'c')
  git(work, 'merge', '-q', '--no-edit', 'develop')
  git(work, 'push', '-q', 'origin', 'c')
  const dirty = run(work, 'preflight', 'a', 'b', 'c')
  assert.equal(dirty.status, 1)
  assert.match(dirty.stdout, /FAIL c: [1-9]\d* merge commits/)
})

test('--workdir reuses a clean worktree and refuses a dirty one', () => {
  const { work } = makeStack()
  const oldTip = rewriteParent(work)
  git(work, 'checkout', '-q', '--detach', 'develop')
  const ok = run(work, 'rebase', 'a', 'b', 'c', '--parent-old', oldTip, '--workdir', work, '--verify', 'test -f a.txt')
  assert.equal(ok.status, 0, ok.stderr)
  writeFileSync(join(work, 'dirty.txt'), 'x')
  const dirty = run(work, 'rebase', 'a', 'b', 'c', '--parent-old', oldTip, '--workdir', work)
  assert.equal(dirty.status, 1)
  assert.match(dirty.stderr, /is not clean/)
})
