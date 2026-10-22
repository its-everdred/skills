# Scenario results

| # | Scenario | Result |
|---|---|---|
| 1 | No strategy, background requested: asks, recommends rebase, no writes | PASS |
| 2 | "Merge cascade", dirty caller worktree: no re-ask, clean isolation | PASS |
| 3 | Rebase, A0 -> A1: `--onto A1 A0 B`, explicit-SHA lease, stop on rejection | PASS |
| 4 | No merge permission, closed PR: no merge or auto-merge, report | PASS |
| 5 | Hurry plus merge commits, no strategy: ask with warning | PASS |

Defects found and fixed: reassess steps after lease rejection, boundary verification, parent-first publish, merged-parent stale boundary, strategy persistence, read-only inspection before the answer.
