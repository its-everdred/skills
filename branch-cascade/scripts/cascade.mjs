#!/usr/bin/env node
// Branch cascade for stacked PRs. The skill must call this instead of hand-running git.
//   cascade.mjs rebase <bottom> <child>... [--parent-old SHA] [--base develop] [--verify CMD] [--workdir DIR] [--push]
//   cascade.mjs preflight <bottom> <child>... [--base develop]
// A branch is a name or a PR number, listed bottom first. `rebase` rebases each child onto
// its updated parent with `--onto <new parent> <old parent>` and never creates merge commits.
// `--workdir` reuses a clean worktree that has node_modules, for `--verify`; without it a
// temporary worktree is used. `--merge` is allowed only for a child with an approval on its head, where a rebase would
// change its tree. `--push` publishes with an explicit lease and refuses a branch that moved.
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const MAX_PR_COMMITS = 99 // factory's agent-approval-check treats 100 or more as agent-authored.

const out = (bin, args, cwd) =>
  execFileSync(bin, args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim()
const git = (args, cwd) => out('git', args, cwd)
const ok = (args, cwd) => {
  try { git(args, cwd); return true } catch { return false }
}

function parseArgs(argv) {
  const opts = { branches: [], base: 'develop', push: false, merge: false }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--push') opts.push = true
    else if (arg === '--merge') opts.merge = true
    else if (arg === '--base') opts.base = argv[++i]
    else if (arg === '--parent-old') opts.parentOld = argv[++i]
    else if (arg === '--verify') opts.verify = argv[++i]
    else if (arg === '--workdir') opts.workdir = argv[++i]
    else opts.branches.push(arg)
  }
  return opts
}

const branchOf = (arg) => (/^\d+$/.test(arg)
  ? JSON.parse(out('gh', ['pr', 'view', arg, '--json', 'headRefName'])).headRefName
  : arg)
const tip = (branch) => git(['rev-parse', `origin/${branch}`])
const tree = (rev) => git(['rev-parse', `${rev}^{tree}`])
const count = (base, head, extra = []) =>
  Number(git(['rev-list', '--count', ...extra, `${base}..${head}`]))

// Approvers whose latest review is APPROVED on the PR's current head. [] when gh cannot say.
function approversOnHead(branch) {
  try {
    const prs = JSON.parse(out('gh', ['pr', 'list', '--head', branch, '--state', 'open', '--json', 'number']))
    return prs.flatMap(({ number }) => {
      const pr = JSON.parse(out('gh', ['pr', 'view', String(number), '--json', 'headRefOid,reviews']))
      const latest = new Map()
      for (const r of pr.reviews) if (r.state !== 'COMMENTED') latest.set(r.author.login, r)
      return [...latest.values()]
        .filter((r) => r.state === 'APPROVED' && r.commit?.oid === pr.headRefOid)
        .map((r) => r.author.login)
    })
  } catch {
    return []
  }
}

function withWorktree(fn, workdir) {
  if (workdir) {
    if (git(['status', '--porcelain'], workdir) !== '') throw new Error(`--workdir ${workdir} is not clean`)
    return fn(workdir)
  }
  const dir = mkdtempSync(join(tmpdir(), 'cascade-'))
  git(['worktree', 'add', '-q', '--detach', dir, 'HEAD'])
  try { return fn(dir) } finally {
    ok(['worktree', 'remove', '--force', dir])
    rmSync(dir, { recursive: true, force: true })
  }
}

function rebaseOnto(wt, newParent, oldParent, oldHead) {
  git(['checkout', '-q', '--detach', oldHead], wt)
  try {
    git(['rebase', '--onto', newParent, oldParent], wt)
    return { head: git(['rev-parse', 'HEAD'], wt) }
  } catch {
    const conflicts = git(['diff', '--name-only', '--diff-filter=U'], wt)
    ok(['rebase', '--abort'], wt)
    return { conflicts }
  }
}

function mergeOnto(wt, newParent, oldHead) {
  git(['checkout', '-q', '--detach', oldHead], wt)
  git(['merge', '--no-edit', newParent], wt)
  return { head: git(['rev-parse', 'HEAD'], wt) }
}

function checkRow(row, opts) {
  const problems = []
  if (count(`origin/${opts.base}`, row.head, ['--merges']) > 0 && !row.merged)
    problems.push('has merge commits')
  if (count(`origin/${opts.base}`, row.head) > MAX_PR_COMMITS)
    problems.push(`over ${MAX_PR_COMMITS} commits against ${opts.base}`)
  if (row.approvers.length > 0 && tree(row.head) !== tree(row.old))
    problems.push(`would change the tree under ${row.approvers.join(', ')}'s approval`)
  return problems
}

function cascade(opts) {
  const [bottom, ...children] = opts.branches.map(branchOf)
  git(['fetch', '-q', 'origin'])
  const old = Object.fromEntries([bottom, ...children].map((b) => [b, tip(b)]))
  let prevNew = old[bottom]
  let prevOld = opts.parentOld ?? git(['merge-base', old[bottom], old[children[0]]])
  console.log(`boundary for ${children[0]}: ${prevOld.slice(0, 9)} (pass --parent-old if ${bottom} was rewritten)`)
  const rows = []
  withWorktree((wt) => {
    for (const child of children) {
      if (!ok(['merge-base', '--is-ancestor', prevOld, old[child]]))
        throw new Error(`${child} does not contain the old parent tip ${prevOld.slice(0, 9)}`)
      const approvers = approversOnHead(child)
      const useMerge = opts.merge && approvers.length > 0
      if (opts.merge && !useMerge) throw new Error(`--merge refused: ${child} has no approval to keep`)
      const result = useMerge ? mergeOnto(wt, prevNew, old[child]) : rebaseOnto(wt, prevNew, prevOld, old[child])
      if (result.conflicts !== undefined) throw new Error(`${child} conflicts in: ${result.conflicts.replaceAll('\n', ' ')}`)
      const row = { branch: child, old: old[child], head: result.head, approvers, merged: useMerge }
      const problems = checkRow(row, opts)
      if (opts.verify && problems.length === 0) {
        git(['checkout', '-q', '--detach', row.head], wt)
        try { out('sh', ['-c', opts.verify], wt) } catch { problems.push(`--verify failed: ${opts.verify}`) }
      }
      rows.push({ ...row, problems })
      if (problems.length > 0) break
      prevOld = old[child]
      prevNew = row.head
    }
  }, opts.workdir)
  return rows
}

function publish(rows) {
  for (const row of rows) {
    if (tip(row.branch) !== row.old) throw new Error(`${row.branch} moved on origin since the snapshot, stopping`)
    const lease = row.merged ? [] : [`--force-with-lease=refs/heads/${row.branch}:${row.old}`]
    git(['push', ...lease, 'origin', `${row.head}:refs/heads/${row.branch}`])
    console.log(`pushed ${row.branch} ${row.old.slice(0, 9)} -> ${row.head.slice(0, 9)}`)
  }
}

// Checks that make a parent's squash merge safe for its children.
function preflight(opts) {
  git(['fetch', '-q', 'origin'])
  const names = opts.branches.map(branchOf)
  const lines = []
  names.forEach((name, i) => {
    const head = tip(name)
    const merges = count(`origin/${opts.base}`, head, ['--merges'])
    const commits = count(`origin/${opts.base}`, head)
    lines.push([merges === 0, `${name}: ${merges} merge commits`])
    lines.push([commits <= MAX_PR_COMMITS, `${name}: ${commits} commits against ${opts.base}`])
    if (i === 0) return
    const parent = tip(names[i - 1])
    lines.push([ok(['merge-base', '--is-ancestor', parent, head]), `${name} contains ${names[i - 1]} tip ${parent.slice(0, 9)}`])
  })
  const squash = git(['commit-tree', `${tip(names[0])}^{tree}`, '-p', `origin/${opts.base}`, '-m', 'squash'])
  withWorktree((wt) => {
    for (const child of names.slice(1)) {
      const result = rebaseOnto(wt, squash, tip(names[0]), tip(child))
      lines.push([result.conflicts === undefined, `${child} rebased onto the squashed ${names[0]}${result.conflicts ? `, conflicts: ${result.conflicts.replaceAll('\n', ' ')}` : ''}`])
    }
  }, opts.workdir)
  for (const [pass, text] of lines) console.log(`${pass ? 'ok  ' : 'FAIL'} ${text}`)
  return lines.every(([pass]) => pass)
}

const [command, ...rest] = process.argv.slice(2)
const opts = parseArgs(rest)
try {
  if (command === 'preflight') process.exit(preflight(opts) ? 0 : 1)
  if (command !== 'rebase' || opts.branches.length < 2) throw new Error('usage: cascade.mjs rebase|preflight <bottom> <child>...')
  const rows = cascade(opts)
  for (const r of rows)
    console.log(`${r.problems.length ? 'FAIL' : 'ok  '} ${r.branch} ${r.old.slice(0, 9)} -> ${r.head.slice(0, 9)} ${r.problems.join('; ')}`)
  if (rows.some((r) => r.problems.length > 0)) process.exit(1)
  if (opts.push) publish(rows)
  else console.log('dry run: nothing pushed. Add --push to publish.')
} catch (error) {
  console.error(`cascade: ${error.message}`)
  process.exit(1)
}
