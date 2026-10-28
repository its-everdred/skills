# Scenario results

| # | Scenario | Result |
|---|---|---|
| 1 | No strategy, background requested: checks repo settings, rebases unapproved PRs and merges approved ones, no writes | PASS |
| 2 | "Merge cascade", dirty caller worktree: no re-ask, clean isolation | PASS |
| 3 | Rebase, A0 -> A1: `--onto A1 A0 B`, explicit-SHA lease, stop on rejection | PASS |
| 4 | No merge permission, closed PR: no merge or auto-merge, report | PASS |
| 5 | Hurry plus merge commits, no strategy: ask with warning | PASS |
| 6 | Stack drifts after the parent is rewritten: `autorebase.sh --dry-run` finds the child's old base from the reflog | PASS |
| 7 | Behind but mergeable PR: `autorebase.sh --once` reports nothing to update; `--eager` plans an update | UNTESTED |
| 8 | Mixed stack, bottom PR unapproved and top PR approved: `autorebase.sh --dry-run --eager` plans `rebase` for the first and `merge` for the second | UNTESTED |
| 9 | Merged parent in the PR list: `autorebase.sh --dry-run --eager 785 786` plans a rebase of 786 onto `develop` from 785's final head | PASS |
| 10 | Unapproved bottom PR one commit behind `develop`: `autorebase.sh --once --dry-run 786` plans a rebase with no flag; an approved one is skipped unless `--eager` or blocked | PASS (unapproved), UNTESTED (approved) |

Defects found and fixed: reassess steps after lease rejection, boundary verification, parent-first publish, merged-parent stale boundary, strategy persistence, read-only inspection before the answer.
