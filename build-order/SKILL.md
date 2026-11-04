---
name: build-order
description: Use for '/build-order', "break this into tickets", "make a build order", "decompose this feature", or when a plan (from ce-plan or research-spike) must become parallel, worker-ready tickets. Tool-agnostic: produces ticket contracts and a typed dependency graph leveled into waves with a critical path, validates it, and files it in whatever tracker the project uses. Tracker-specific skills (for example aiur-build for aiur) layer their features on top of this one.
---

# Build order

Turns an approved plan into tickets that many agents can execute in parallel without stepping on each other. Input: a
requirements doc and a `ce-plan` plan (or run `research-spike` first). Output: a **planning pack** (see
`references/planning-pack.md`) and, optionally, the tickets filed in the project's tracker.

If the project runs a tracker with its own build-order skill (aiur: `aiur-build`), load that skill too: it adds the
tracker's formats, promotion and Executor hand-off on top of these rules.

## 1. Cut tickets at real boundaries

An executable ticket has **one owning agent, one coherent outcome, one review/acceptance boundary, and a change that
leaves the repository green.** Split work with several independently shippable outcomes, separate bounded contexts,
public contracts, or its own internal phase plan (that is an umbrella, not a ticket). Merge findings that share one
root cause, one write surface and one verification.

Every ticket is worker-ready for a less capable agent: exact files, module and function names, a pattern to copy, one
worked data example, and acceptance as checkable items. A named reuse target that does not exist is a defect.

**Complexity is size and uncertainty only:** 1 localized known pattern; 2 one component, modest multi-file; 3 one bounded
context with a new contract or real integration; 4 cross-context or high uncertainty (split unless indivisible); 5
irreducible cross-system risk or a capstone, with a written reason. Track risk and needed capabilities separately.

## 2. Model the graph

- `depends_on`: only true start or merge prerequisites.
- `serializes_with`: two tickets that would edit the same files or resources (conflict, not order).
- `suggested_after`: advisory order.
- `contains`: hierarchy (feature → epic → ticket).
- gates: external constraints (a decision, an approval, an upstream release).

Design for parallelism: start with a **skeleton/contracts ticket** so later tickets each own their files; depend on
reviewed contracts rather than finished implementations where a temporary path is specified; dissolve same-wave
conflict clusters by re-partitioning write surfaces (one module per section mounted by a shared shell beats many
tickets editing one file). Separate building a piece from integrating it (a component can be built in a test harness
before the place it lives exists). Include an integration/acceptance **capstone** from day one, and make every
release-required ticket reachable from it.

## 3. Level and validate

Compute the **wave profile** (how many tickets are ready together) and the **critical path** before filing. Compare the
widest waves with the real agent capacity; say which waits are dependencies and which are capacity. Phase labels are
presentation hints, never global barriers. Check mechanically: no cycles, no orphans (every ticket reaches the
capstone), no dependency on a missing ticket, every ticket has owner files and acceptance. Then run `ce-doc-review` (or
an adversarial reader) on the pack.

## 4. Discovery policy

Before hand-off, write what happens to findings during execution: acceptance blockers may become new tickets; review
findings go back to the owning ticket; nice-to-haves go to a deferred list. The executor must not grow an open-ended
backlog from useful observations.

## 5. File it

File tickets with their dependencies in the project's tracker (native blocked-by where supported), a feature or epic per
lane, priority for the first playable or shippable slice, and the capstone. Record ticket numbers back into the pack.

## 6. Review view

The plan must be reviewable by a person at a glance: the waves, the critical path, each lane's tickets with status and
dependencies, and open gates. If the tracker shows this (aiur's Build Order view), link it. If not, render it: write a
small self-contained HTML page (or publish it as an artifact) from the pack's graph with a wave table, the critical path
highlighted, and per-ticket rows (title, lane, complexity, depends on, status). Regenerate it when the plan changes.
