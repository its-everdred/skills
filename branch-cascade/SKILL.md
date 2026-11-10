---
name: branch-cascade
description: Use when upstream branch changes need propagating through stacked PRs, dependent branches need syncing, or the user asks to watch, rebase, merge or cascade a branch stack.
---

# Branch Cascade

Synchronize dependent branches. Updating a branch is not approval to merge its PR.

**Run `scripts/cascade.mjs` for every cascade and every pre-merge check. Do not hand-run `git rebase`, `git merge` or `git push` on a stack.** The script holds the rules below, so they do not depend on this text being remembered. Run it from any worktree of the repo, `node <skill-dir>/scripts/cascade.mjs`. Its tests are `node --test scripts/cascade.test.mjs`.

## Standing strategy

Rebase, never merge. This is the owner's standing rule, so do not ask. A merge cascade puts every parent's old commits into each child's history. GitHub's rebase after a squash merge then replays them and conflicts, and the PR can pass 100 commits and trip the agent-approval gate. The only exception is a child that has an approval on its head, where `--merge` keeps it. The script refuses `--merge` for any other child.

## Commands

| Need | Command |
|---|---|
| Child branches follow an updated parent | `cascade.mjs rebase <bottom> <child>... [--parent-old SHA] [--verify CMD]` (dry run) then the same with `--push` |
| Check before a parent merges | `cascade.mjs preflight <bottom> <child>...` |

Branches are names or PR numbers, bottom first. Always dry-run first and show the output.

- **`--parent-old`:** pass the bottom's previous tip when the bottom was rewritten, because the merge-base default would then replay its old commits. Find it in the PR's force-push event or the reflog. If it cannot be found, stop and ask.
- **`--verify`:** pass the repo's typecheck and tests, for example `pnpm -C apps/api exec tsc --noEmit`. A failure stops the chain.
- **`--push`:** publishes each branch with an explicit lease. It stops if a branch moved on origin since the snapshot, and it never skips a branch silently.
- **What `rebase` checks:** the child contains the old parent tip, no merge commits, fewer than 100 commits against the base, and the new tree is unchanged for a branch with an approval. It stops on any conflict and reports the files.
- **What `preflight` checks:** merge commits, the commit count, that each child contains its parent's current tip, and a dry run of squashing the bottom onto the base and rebasing each child onto it. Do not tell the user a merge is safe until `preflight` passes.

## Rules the script cannot enforce

1. Read repository instructions and confirm live PR heads, bases and states with `gh` before running.
2. Use clean isolated worktrees. Leave dirty worktrees untouched. Never stash, reset or delete someone else's work.
3. Resolve a conflict only when intent is clear, keeping validation, authorization and error handling. Otherwise stop and report.
4. Report each branch's old and new SHA, the check results and anything skipped. If a chain fails midway, report the pre-update and current SHA of each branch.
5. A lease rejection means another writer moved the branch. Stop, fetch, report the new tip and wait. Never retry with a broader force.
6. Never rebase or force-push protected or default branches.

## Approvals and merging

- Any push dismisses an approval unless the tree is unchanged. A rebase that keeps the tree keeps the approval. Do not claim otherwise without checking. The `approval-guard` hook blocks pushes that would dismiss one and passes the identical retry once after the user approves in chat.
- For an approved stack, recommend `gh stack merge <pr>`. It merges every PR up to the chosen one in one operation, so the children are never retargeted or pushed. All PRs in it must be open, non-draft, approved and green. Do not merge a bottom PR alone when its children are approved.
- Merged alone, the next PR is retargeted and GitHub rebases it. If that conflicts, run `cascade.mjs rebase` for the remaining PRs and say that any push may dismiss approvals.

## Watch and report

Start a background listener only when requested. A closed or merged PR or a changed base pauses that chain for reassessment, and a merged parent makes the recorded old boundary stale. Report updated branches and SHAs, checks, blockers and listener status.

**Never approve, merge, close or retarget PRs, delete branches, or enable auto-merge without separate explicit authorization.**
