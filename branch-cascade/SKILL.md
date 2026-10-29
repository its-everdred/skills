---
name: branch-cascade
description: Use when upstream branch changes need propagating through stacked PRs, dependent branches need syncing, or the user asks to watch, rebase, merge or cascade a branch stack.
---

# Branch Cascade

Synchronize dependent branches. Updating a branch is not approval to merge its PR.

**Run the cascade in the background, never in the foreground conversation.** Use the listener below or a background agent, so the conversation stays free. The foreground does only the PR the user is focused on, if they ask for it by name.

## Choose before writing

Read-only inspection (fetch, `gh` reads) may run first; no branch writes, pushes or background launch until the strategy is known.

**Propagate upstream changes while PRs are unapproved.** An approved PR with auto-merge set and passing checks is left alone: GitHub merges it, and a push would restart CI. Update an approved PR only when it is actually blocked (conflict, or a required "up to date" rule; `strict_required_status_checks_policy: false` means behind is not blocking).

**Rebase until approved, then merge commits.** A PR with no approval yet is rebased and force-pushed with a lease, which keeps its history clean. Once a PR is approved, a force-push changes the merge-base and dismisses the approval ("The merge-base changed after approval", seen on a squash-only repo with `dismiss_stale_reviews_on_push`), so an approved PR gets a merge commit pushed fast-forward instead. Check `gh api repos/OWNER/NAME` (`allow_squash_merge`, `allow_merge_commit`, `allow_rebase_merge`) and the base branch ruleset first, and ask once if the user has not said which they want. An approved PR is never force-pushed unless the user says so.

Use the answer for this stack and session, and record it with the lock so a resumed or restarted watcher does not re-guess. A background agent inherits that choice, never guesses it. Stop if repository rules forbid the chosen strategy.

## Inspect and scope

1. Read repository instructions. Fetch named refs; confirm live PR heads, bases and states with `gh`. Show the parent-to-child order, strategy, checks and whether pushes/watch mode were requested. Ask about ambiguous dependencies.
2. Check worktree status and active writers. Use clean isolated worktrees and one exclusive cascade lock. Leave dirty worktrees untouched; never stash, reset or delete someone else's work.
3. Snapshot remote SHAs and the **old parent tip each child was based on** before updating anything. Verify that boundary with `git merge-base --is-ancestor <old-parent> <child>`; if the parent was force-pushed, look for the old tip in the PR's earlier head or the reflog; the latest remote parent is not automatically the old boundary. If uncertain, stop rather than replay upstream commits as child work.

## Propagate parent first

Work sequentially along dependencies; independent branches may proceed separately.

| Strategy | Child update | Publish after checks |
|---|---|---|
| Rebase (unapproved PRs) | `git rebase --onto <updated-parent> <old-parent> <child>` | `git push --force-with-lease=refs/heads/<child>:<snapshot-sha> origin HEAD:refs/heads/<child>` |
| Merge (approved PRs) | `git merge --no-edit <updated-parent>` | `git push origin HEAD:refs/heads/<child>` |

Snapshot every old boundary before the first update. Publish each parent before its child, and use the newly published parent for the next child. Skip already synchronized branches. Never rebase or force-push protected/default branches. Warn before proceeding with merge-heavy history; preserve intentional merges with `--rebase-merges` when appropriate, otherwise stop for clarification.

Resolve conflicts only when intent is clear, preserving validation, authorization and error handling. Run the repository's affected tests, typechecks and lint before publishing each child. If checks fail, stop that dependency chain and report the failure; never report skipped checks as passing. A lease rejection means another writer moved the branch: stop that chain, fetch, re-snapshot, report the new tip and wait for direction. Never retry with a broader force or a lease against the new tip without review. If a chain fails midway, report each branch's pre-update and current SHA.

## Automatic listener (default)

Use `scripts/autorebase.sh` for keeping a stack current. **Default `auto`: each PR is rebased and force-pushed with a lease until it is approved, then it gets a merge commit and a fast-forward push.** A force-push changes the merge-base and dismisses approvals on every PR above it; merge-commit updates left them intact. `--merge` treats every PR that way and `--rebase` rebases every PR. **No agent is needed unless it reports a conflict.**

```bash
git worktree add --detach <dir>   # clean checkout the script may reset freely
bash <skill-dir>/scripts/autorebase.sh --repo OWNER/NAME --worktree <dir> PR1 PR2 PR3   # bottom first
```

Run it under the host's monitor (Monitor in Claude Code, max 30 minutes, re-arm on expiry). Add `--dry-run` first to see the planned heads, and `--once` to update a single time and exit.

- **Acts when** the bottom open PR is behind the default branch and has no approval, so upstream changes propagate through the stack on their own, or GitHub reports it `BEHIND` (required up-to-date rule) or `DIRTY` (conflict), or a child is not on top of its parent. Once the bottom PR is approved, mere lag is ignored, because a push restarts CI and can put the approval at risk, and it acts only when blocked. `--eager` follows every move even when approved; `--only-blocked` acts only when blocked. It then updates the whole open stack in order and publishes it in one `git push --atomic`, so the stack never shows as diverged between pushes. An unapproved PR is rebased onto the new parent. An approved PR gets a merge commit whose tree is what a rebase would produce, with the old head and the new parent as parents, so the push is a fast-forward and the PR's diff stays its own changes.
- **Boundaries** come from the parent's current head, the reflog (`merge-base --fork-point`) and heads the script replaced earlier. After a parent merges, the next PR is rebased onto the default branch from the parent's final head.
- **Events** are single lines: `UPDATED`, `MERGED`, `DONE`, `CONFLICT`, `STOP`. An `UPDATED` line gives each PR's kind (`rebase` or `merge`) and lists PRs that were approved before the push, so check they stayed approved.
- **Exit 2 / `CONFLICT`:** nothing was pushed. Only now start a background agent to resolve it, with the strategy and snapshots from the event. **Exit 1 / `STOP`:** a human decision (closed PR, lease rejection, boundary not found).
- It runs no tests. Use it only when CI is the gate; otherwise verify before pushing as in the sections above.
- It never merges, comments, retargets, approves, or touches a branch outside the listed PRs.

## Always-on daemon (preferred for a long stack)

Use this when the user asks for the cascade to run. Keep the plist in `~/.config/branch-cascade/`, not `~/Library/LaunchAgents/`, so it never starts at login; `launchctl bootstrap` starts it on demand and `bootout` stops it. `scripts/cascade-daemon.sh` runs `autorebase.sh` until stopped, restarts it after a stop, pushes over HTTPS with the `gh` login (no ssh agent needed), and sends one macOS notification per distinct conflict or stop. List a PR number or, for a branch with no PR yet, its branch name, bottom first:

```bash
git worktree add --detach <dir>   # dedicated, never used by hand
# ~/.config/branch-cascade/local.branch-cascade.<name>.plist runs:
#   bash <skill-dir>/scripts/cascade-daemon.sh --repo OWNER/NAME --worktree <dir> PR_OR_BRANCH...
launchctl bootstrap gui/$(id -u) ~/.config/branch-cascade/local.branch-cascade.<name>.plist
```

Logs go to `<dir>.cascade.log` and `~/Library/Logs/branch-cascade/`. Stop it with `launchctl bootout gui/$(id -u)/local.branch-cascade.<name>`. It exits by itself when every listed PR has merged. Add a newly opened PR by adding its number to the plist and re-bootstrapping. A conflict is the only case that needs an agent or a human; the daemon leaves the branches untouched and notifies.

## If an approval gets dismissed

Comment `@OptimismBot please reapprove` on the PR to get it re-approved. The user posts it, or says so; the script and the agent never comment on their own. Use it after a force-push that could not be avoided, or when an approval shows as dismissed for "The merge-base changed after approval". Prefer avoiding the dismissal first: merge commits for approved PRs, never a force-push.

## Watch and report

Start a listener only when requested, and not on PRs with auto-merge set: `scripts/autorebase.sh`, or the host's background/monitor facilities for anything else. Record the stack, strategy, snapshots and lock ownership. Recheck PR states and remote changes each iteration. A closed or merged PR or a changed base pauses that chain for reassessment, not automatic retargeting. A merged parent makes the recorded old boundary stale. Stop and release owned locks on cancellation; report unresolved operations without discarding them.

Report updated branches/SHAs, checks, blockers and listener status. **Never approve, merge, close or retarget PRs, delete branches, or enable auto-merge without separate explicit authorization.**
