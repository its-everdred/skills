---
name: reopen-pr
description: Replay a source pull request's exact GitHub PR commits onto a fresh branch in another repository, then open a draft pull request there with the current gh-authenticated user.
---

# Reopen PR

Promote a reviewed pull request from one repository into a new draft pull request on another repository. The bundled `reopen.sh` script reads the source PR metadata, fetches only the exact commits GitHub reports for that PR, cherry-picks them onto the target repository's `origin/main`, pushes a new branch, and opens a draft PR against the target repository's `main`.

When given `--target-issue N`, the script also prefixes the branch with `N` and rewrites common closing/reference issue links in the PR body to `#N`.

## When to use

Use this after a source PR has been reviewed and explicitly approved for promotion to a target repository. Do not reopen unreviewed or unsigned-off PRs.

## Preconditions

- `gh auth status` shows the account that should author and push the target PR.
- `jq`, `gh`, and `git` are available.
- Run from a clean checkout of the target repository.
- The target checkout's `origin` remote points at the target repository.
- Record the current branch before running; the script leaves the checkout on the new branch after success.

## Procedure

1. Dry-run first to preview the new branch name and exact commits:

   ```bash
   /path/to/reopen.sh <source-pr-url> <target-owner/target-repo> --title --target-issue <issue-number> --dry-run
   ```

2. Confirm the dry-run lists only commits that belong to the source PR.

3. Confirm any target issue references before opening the PR. Source and target repositories may have different issue numbers. Pass the target issue as `--target-issue <issue-number>` when the new PR should reference a target issue.

4. Run for real by dropping `--dry-run`:

   ```bash
   /path/to/reopen.sh <source-pr-url> <target-owner/target-repo> --title --target-issue <issue-number>
   ```

5. Inspect the new PR body. If `--target-issue` was used, common closing/reference issue links should already point at the target issue. Manually review any other source-repository references that were not part of a closing/reference phrase.

6. Record the source PR, target issue, and new target PR mapping wherever the project tracks promotion status.

7. Return the target checkout to the previous branch if needed.

## Gotchas

- The script validates that the checkout's `origin` appears to match the requested target repository. If it does not, it prompts before continuing.
- The new PR is a draft by design.
- Run one PR at a time. The script changes branches in the target checkout.
- If a cherry-pick conflicts, the script aborts the cherry-pick, deletes the new branch, and returns to the original branch.
- Always dry-run after changing the source PR, because the exact PR commit list may have changed.
- `--target-issue` only rewrites common closing/reference phrases such as `Closes #123`, `Fixes #123`, `Resolves #123`, and `Refs #123`. It does not rewrite every issue-like string in the body.
