---
name: branch-cascade
description: Use when upstream branch changes need propagating through stacked PRs, dependent branches need syncing, or the user asks to watch, rebase, merge or cascade a branch stack.
---

# Branch Cascade

Synchronize dependent branches. Updating a branch is not approval to merge its PR.

## Choose before writing

Read-only inspection (fetch, `gh` reads) may run first; no branch writes, pushes or background launch until the strategy is known. Ask: **“Rebase (default) or merge for this stack?”** Recommend rebase by default, but wait for the answer. If the current request already specifies a strategy, acknowledge it instead of asking again. A default is not consent. Explain that rebase rewrites published commits and requires lease-protected pushes; merge preserves history.

Use the answer for this stack and session, and record it with the lock so a resumed or restarted watcher does not re-guess. A background agent inherits that choice, never guesses it. Existing merge history or collaborators warrant a warning, not silently switching strategies. Stop if repository rules forbid the chosen strategy.

## Inspect and scope

1. Read repository instructions. Fetch named refs; confirm live PR heads, bases and states with `gh`. Show the parent-to-child order, strategy, checks and whether pushes/watch mode were requested. Ask about ambiguous dependencies.
2. Check worktree status and active writers. Use clean isolated worktrees and one exclusive cascade lock. Leave dirty worktrees untouched; never stash, reset or delete someone else's work.
3. Snapshot remote SHAs and the **old parent tip each child was based on** before updating anything. Verify that boundary with `git merge-base --is-ancestor <old-parent> <child>`; if the parent was force-pushed, look for the old tip in the PR's earlier head or the reflog; the latest remote parent is not automatically the old boundary. If uncertain, stop rather than replay upstream commits as child work.

## Propagate parent first

Work sequentially along dependencies; independent branches may proceed separately.

| Strategy | Child update | Publish after checks |
|---|---|---|
| Rebase (default) | `git rebase --onto <updated-parent> <old-parent> <child>` | `git push --force-with-lease=refs/heads/<child>:<snapshot-sha> origin HEAD:refs/heads/<child>` |
| Merge | `git merge --no-edit <updated-parent>` | `git push origin HEAD:refs/heads/<child>` |

Snapshot every old boundary before the first update. Publish each parent before its child, and use the newly published parent for the next child. Skip already synchronized branches. Never rebase or force-push protected/default branches. Warn before proceeding with merge-heavy history; preserve intentional merges with `--rebase-merges` when appropriate, otherwise stop for clarification.

Resolve conflicts only when intent is clear, preserving validation, authorization and error handling. Run the repository's affected tests, typechecks and lint before publishing each child. If checks fail, stop that dependency chain and report the failure; never report skipped checks as passing. A lease rejection means another writer moved the branch: stop that chain, fetch, re-snapshot, report the new tip and wait for direction. Never retry with a broader force or a lease against the new tip without review. If a chain fails midway, report each branch's pre-update and current SHA.

## Watch and report

Start a background listener only when requested, using the host's background/monitor facilities. Record the stack, strategy, snapshots and lock ownership. Recheck PR states and remote changes each iteration. A closed or merged PR or a changed base pauses that chain for reassessment, not automatic retargeting. A merged parent makes the recorded old boundary stale. Stop and release owned locks on cancellation; report unresolved operations without discarding them.

Report updated branches/SHAs, checks, blockers and listener status. **Never approve, merge, close or retarget PRs, delete branches, or enable auto-merge without separate explicit authorization.**
