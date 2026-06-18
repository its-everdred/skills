---
name: full-review-audit
description: Use when a developer wants a rigorous, broad review of a codebase or subsystem that must become a prioritized, parallelizable ticket backlog — production-readiness, security or fund-safety hardening, pre-release sweeps, or turning "review this whole thing" into actionable work — at a scale too large for one pass or one context window. Especially high-stakes code (DeFi, payments, auth, infrastructure).
---

# Full Review Audit

## Overview

A structured way to run a deep review of a codebase that is too large for one pass or one context window, and turn it into a prioritized, conflict-minimized ticket backlog that many agents can work in parallel.

**Core principle:** run **many diverse-lens passes that compound** — each pass reads the prior findings and only *adds or refutes*, never re-derives — then **adversarially verify**, then convert findings into **waved tickets**. Everything is logged to files so the orchestrator carries only pointers and never drowns in its own findings.

**Two phases joined by a handoff `/goal`:**

1. **Plan (collaborative)** — **kick off with `/ce-brainstorm`**, which drives steps 1–5: scope, the menu of review forms, how many passes each focus gets, and which skill drives each pass. Ends by handing the developer a copy-paste **`/goal`**.
2. **Execute (autonomous)** — the developer pastes the `/goal` back; the agent runs every pass, verifies, synthesizes tickets, schedules waves, opens a draft PR, and finally asks the developer to review the tickets and offers to open them as repo issues.

## Before you start (tell the developer)

Two prerequisites materially change the quality of this review — surface them before Phase 1:

- **Use the strongest model in the strongest mode.** This review fans out dozens of subagents and multi-step workflows and depends on deep reasoning per pass. Recommend the developer run the most capable model available and its most powerful orchestration mode — e.g. **ultracode** (maximal reasoning effort + workflow orchestration). On a lighter model/mode the review is slower and shallower; say so and offer to proceed anyway.
- **Install the recommended skills — [compound-engineering](https://github.com/EveryInc/compound-engineering-plugin) first.** This method is built on it: `/ce-brainstorm` runs the planning phase, and `/ce-code-review` plus its persona reviewers (`ce-adversarial-reviewer`, `ce-security-reviewer`, `ce-correctness-reviewer`, `ce-data-integrity-guardian`, `ce-scope-guardian-reviewer`, …) supply most of the lenses. Add complementary packs (engineering-skills, ethskills) for the non-CE lenses (see Suggested lineup). If compound-engineering isn't installed, recommend installing it before proceeding — without it the method degrades to role-prompted general agents, which is materially weaker.

## When to use

- "Review/harden this whole codebase before we ship / call it 1.0."
- High-stakes code where a single review pass is not enough confidence (funds, auth, payments, infra, data integrity).
- You want the output to be *actionable tickets*, not a prose report.
- The surface is bigger than one agent context can hold.

## When NOT to use

- A single file or small diff → use a normal `/code-review`.
- A known, specific bug → use a debugging skill.
- You need a quick gut-check, not a backlog.

## The 10 steps

**Steps 1–5 are the Plan phase — drive them with `/ce-brainstorm`. Steps 6–10 are the Execute phase — run from the emitted `/goal`.**

| # | Step | Mechanism |
|---|------|-----------|
| 1 | **Scope & priorities** | Collaborative dialogue (not a form): definition of done, the dominant risk lens, core vs review-only surfaces, hard constraints, deliverable format. Front-load the few high-leverage decisions as explicit either/or questions. |
| 2 | **Map the solution space** | A parallel research pass: enumerate the *forms* a review can take, evaluate relevant prior art already in the repo/PRs, inventory existing controls, surface residual-risk blind spots. Output: a prep doc + open questions. |
| 3 | **Size the passes per focus** | Decide how many passes each area gets, weighted by risk and concentrated on the highest-value code. More passes where money/trust lives; fewer on review-only surfaces. |
| 4 | **Inventory skills, map skills → passes** | Survey installed skills; assign a *deliberately diverse* lens to each pass (mix families). If few relevant skills are installed, recommend installing more powerful ones first (see Suggested lineup). |
| 5 | **Author the pass prompts + emit the `/goal`** | A shared standing-rules preamble + per-pass lens prompts, plus a cumulative findings ledger so context flows between passes. End the planning phase by giving the dev a ready-to-paste `/goal` (see [templates.md](templates.md)). |
| 6 | **Execute passes, log as you go** | Each pass fans out subagents by surface, then a merge step writes a per-pass review log and updates the deduped ledger. Passes run **sequentially** so learnings compound. |
| 7 | **Adversarially verify + complete** | A dedicated pass: a skeptic per high-severity finding (default = refute), plus completeness lenses that hunt vectors no pass found. Recalibrate severities; drop false positives. |
| 8 | **Boil findings into tickets** | Cluster the ledger into coherent tickets (bundle shared root causes), one doc each with **severity + complexity 1–5**, drop demoted findings, and mark any that should *augment an existing issue* rather than create a new one. |
| 9 | **Schedule conflict-minimizing waves** | Order tickets so **no two in a wave edit the same file** (minimize merge conflict), priority chokepoints first; then *independently* verify zero collisions. |
| 10 | **Stay lean, hand off, persist** | Log to files at healthy seams; compact with handoff notes near context limits; commit each artifact and open a draft PR. |
| 11 | **Review & offer to file** | End by asking the developer to review the full ticket list (`docs/tickets/_INDEX.md`), then offer to open the tickets as repo issues — deduping against existing issues first, and filing nothing without explicit go-ahead. |

## Key mechanisms (what makes it work)

- **Cumulative findings ledger.** One file (e.g. `docs/reviews/_ledger.md`) is the deduped index with a stable `NEXT_ID`. Every pass reads it, dedups against it, and appends only new or refining rows. This is what stops 17 passes from re-finding the same 10 things.
- **Diverse lenses beat repetition.** The same skill run twice finds the same things. An API-design lens, a supply-chain lens, and a red-team lens find *different* classes. Map each pass to a different family on purpose.
- **File-based logging + compaction seams.** Subagents (and per-pass merge steps) write full findings to files; the orchestrator keeps only compact summaries. Compact at a clean seam (between passes) when context runs high, leaving handoff notes (last pass #, ledger path, next skill).
- **Adversarial verify gate.** Before findings become tickets, a skeptic tries to *refute* each high finding from the actual code; survivors are confirmed, the rest demoted. A "missing test" is deflated to its own low severity (a missing test cannot move funds; the underlying bug keeps its high).
- **Conflict-minimizing waves.** Tickets are scheduled by *file overlap*, not just hard dependencies: two tickets that edit the same file go in different waves so parallel branches merge cleanly. Hot files (edited by many tickets) drive serialization — accept many small waves over a few conflicting ones.
- **Each pass is a workflow.** If the runtime has a workflow/orchestration tool, make each pass a workflow that fans out by surface and ends in a merge step that writes the files. If not, run subagents sequentially and write the files yourself. Either way, **per-file commits + a draft PR** at the end.

## Suggested skill lineup (compound-engineering first)

This method is built around **[compound-engineering](https://github.com/EveryInc/compound-engineering-plugin)**: `/ce-brainstorm` runs the planning phase, and `/ce-code-review` plus its persona reviewers supply most of the review lenses. Use the CE lens as the recommended driver for each pass, and add a complementary lens from another pack to keep the passes diverse — diversity is what makes cumulative passes surface *different* classes of issue.

| Pass focus | Compound-engineering lens (recommended) | Complementary lens |
|---|---|---|
| Planning (steps 1–5) | `/ce-brainstorm` | — |
| Broad baseline | `/ce-code-review` | built-in `/code-review` |
| Correctness / logic | `ce-correctness-reviewer` | `engineering-skills:senior-backend` |
| Adversarial / attacker | `ce-adversarial-reviewer` | `engineering-skills:red-team` |
| Security / auth / secrets | `ce-security-reviewer`, `ce-security-sentinel` | `engineering-skills:security-pen-testing`, built-in `/security-review` |
| Data-integrity / numeric | `ce-data-integrity-guardian` | `engineering-skills:senior-backend` |
| Public API / contracts | `ce-api-contract-reviewer` | `engineering-advanced-skills:api-design-reviewer` |
| Architecture / patterns | `ce-architecture-strategist` | — |
| Test-coverage adequacy | `ce-testing-reviewer` | `engineering-skills:senior-qa` |
| Supply chain / dependencies | — | `engineering-advanced-skills:dependency-auditor` |
| Domain (e.g. DeFi) | — | `ethskills:security`, `ethskills:wallets` |
| Frontend / UX safety | — | `ethskills:frontend-ux`, `engineering-skills:senior-frontend` |
| Plan / scope review | `ce-scope-guardian-reviewer` | — |
| External best-practice research | `ce-best-practices-researcher` | — |
| Verify + completeness | `ce-adversarial-reviewer` (skeptic per finding) | — |

The `ce-*` reviewers are compound-engineering persona agents — `/ce-code-review` spawns them internally, and they're also dispatchable directly as agents.

**If the recommended packs aren't installed:** install **compound-engineering** first — it is the backbone. Add **engineering-skills / engineering-advanced-skills** and a domain pack (e.g. **ethskills**) for the complementary lenses. Absent these, fall back gracefully — each lens becomes a general agent told to *act as* that specialist — and tell the developer plainly that's materially weaker.

## Sizing

Weight passes by risk and value. A rough default for a high-stakes core library plus review-only peripherals: ~8–12 passes on the core (one per lens above), 1–2 review-only passes per peripheral surface (backend/frontend/CLI), then 1 verify pass and 1 final whole-flow pass. Expand where money or trust concentrates.

## The handoff `/goal` (the seam)

Phase A's last act is to hand the developer a single copy-paste `/goal` that encodes the whole execution: run passes 1..N sequentially and cumulatively, log each to a file, verify, synthesize tickets with severity+complexity, schedule conflict-free waves, commit and open a draft PR. The developer pastes it back and the agent runs to completion. See the ready-to-fill template in [templates.md](templates.md).

## Common mistakes

| Mistake | Fix |
|---|---|
| One giant "wave 0" of everything independent | Schedule by *file overlap*; two tickets editing the same file must be different waves. |
| Same skill for every pass | Map each pass to a different lens/family; diversity is the whole point. |
| No ledger → every pass re-finds the same issues | One cumulative ledger; each pass dedups and only adds/refutes. |
| Findings pile into the orchestrator's context | Log to files; carry only compact summaries; compact at pass boundaries. |
| A missing test filed at the severity of the bug it misses | The verify pass deflates coverage findings to their own (low) severity. |
| Skipping the verify gate | False positives ship as tickets; always run skeptic-per-high-finding. |
| Filing GitHub issues mid-review | Write ticket *docs* now; file to the tracker later, deduping against existing issues. |
| Committing one giant blob | Per-file commits, draft PR, nothing merged without the dev. |

## Quick reference

**Steps 1–5 via `/ce-brainstorm`:** 1. Align scope → 2. Research forms → 3. Size passes → 4. Map skills → 5. Write prompts + **emit `/goal`** → *(dev pastes `/goal`)* → **steps 6–11 from the `/goal`:** 6. Run passes (cumulative, file-logged) → 7. Verify + complete → 8. Tickets (severity + complexity 1–5) → 9. Conflict-free waves (verified) → 10. Compact, commit per-file, draft PR → 11. Ask dev to review tickets + offer to file as repo issues (dedup first).

Templates for the standing preamble, the per-pass runner, the verify pass, ticket synthesis, wave scheduling, and the `/goal` live in [templates.md](templates.md).
