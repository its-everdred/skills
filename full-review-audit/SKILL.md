---
name: full-review-audit
description: Use when a developer wants a rigorous, broad review of a codebase or subsystem that must become a prioritized, parallelizable ticket backlog — production-readiness, security or fund-safety hardening, pre-release sweeps, or turning "review this whole thing" into actionable work — at a scale too large for one pass or one context window. Especially high-stakes code (DeFi, payments, auth, infrastructure).
---

# Full Review Audit

## Overview

A structured way to run a deep review of a codebase that is too large for one pass or one context window, and turn it into a prioritized, conflict-minimized ticket backlog that many agents can work in parallel.

**Core principle:** run **many diverse-lens passes that compound** — each pass reads the prior findings and only *adds or refutes*, never re-derives — then **adversarially verify**, then convert findings into **waved tickets**. Everything is logged to files so the orchestrator carries only pointers and never drowns in its own findings.

**Two phases joined by a handoff `/goal`:**

1. **Plan (collaborative)** — you and the developer agree on scope, the menu of review forms, how many passes each focus gets, and which skill drives each pass. This phase ends by handing the developer a copy-paste **`/goal`**.
2. **Execute (autonomous)** — the developer pastes the `/goal` back; the agent runs every pass, verifies, synthesizes tickets, and schedules waves, to completion.

## Before you start (tell the developer)

Two prerequisites materially change the quality of this review — surface them before Phase 1:

- **Use the strongest model in the strongest mode.** This review fans out dozens of subagents and multi-step workflows and depends on deep reasoning per pass. Recommend the developer run the most capable model available and its most powerful orchestration mode — e.g. **ultracode** (maximal reasoning effort + workflow orchestration). On a lighter model/mode the review is slower and shallower; say so and offer to proceed anyway.
- **Install diverse, powerful skills.** The method's leverage comes from a *different* lens per pass. If few relevant engineering/security/domain skills are installed, recommend a skill pack first (see Suggested lineup); otherwise fall back to role-prompted general agents and tell the dev that's weaker.

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

## Key mechanisms (what makes it work)

- **Cumulative findings ledger.** One file (e.g. `docs/reviews/_ledger.md`) is the deduped index with a stable `NEXT_ID`. Every pass reads it, dedups against it, and appends only new or refining rows. This is what stops 17 passes from re-finding the same 10 things.
- **Diverse lenses beat repetition.** The same skill run twice finds the same things. An API-design lens, a supply-chain lens, and a red-team lens find *different* classes. Map each pass to a different family on purpose.
- **File-based logging + compaction seams.** Subagents (and per-pass merge steps) write full findings to files; the orchestrator keeps only compact summaries. Compact at a clean seam (between passes) when context runs high, leaving handoff notes (last pass #, ledger path, next skill).
- **Adversarial verify gate.** Before findings become tickets, a skeptic tries to *refute* each high finding from the actual code; survivors are confirmed, the rest demoted. A "missing test" is deflated to its own low severity (a missing test cannot move funds; the underlying bug keeps its high).
- **Conflict-minimizing waves.** Tickets are scheduled by *file overlap*, not just hard dependencies: two tickets that edit the same file go in different waves so parallel branches merge cleanly. Hot files (edited by many tickets) drive serialization — accept many small waves over a few conflicting ones.
- **Each pass is a workflow.** If the runtime has a workflow/orchestration tool, make each pass a workflow that fans out by surface and ends in a merge step that writes the files. If not, run subagents sequentially and write the files yourself. Either way, **per-file commits + a draft PR** at the end.

## Suggested skill lineup (agnostic)

Assign a different lens to each pass. This is a *suggested* mapping — substitute whatever the runtime has installed.

| Focus of the pass | Suggested lens (examples) |
|---|---|
| Broad baseline | a general code-review skill, or built-in `/code-review` |
| Domain/business-logic safety | a domain skill (e.g. `ethskills:security` for DeFi) |
| Adversarial / attacker view | `engineering-skills:red-team`, `engineering-skills:adversarial-reviewer` |
| Auth / secrets / boundaries | `engineering-skills:security-pen-testing`, built-in `/security-review` |
| Numeric / data-integrity | `engineering-skills:senior-backend`, a data-integrity reviewer |
| Public API / contracts / types | `engineering-advanced-skills:api-design-reviewer` |
| Supply chain / dependencies | `engineering-advanced-skills:dependency-auditor` |
| Test-coverage adequacy | `engineering-skills:senior-qa` + a testing skill |
| Verify + completeness | an adversarial-reviewer skill |
| Frontend / UX safety | a frontend-ux skill + `engineering-skills:senior-frontend` |

**If the agent is thin on skills:** before running, tell the developer plainly — *"This review is far stronger with a diverse set of engineering/security skills installed. You currently have few. Consider installing an engineering-skills / security / domain skill pack first; otherwise I'll fall back to role-prompted general agents, which is weaker."* Then fall back gracefully: each "lens" becomes a general agent prompted to *act as* that specialist.

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

1. Align scope → 2. Research forms → 3. Size passes → 4. Map skills → 5. Write prompts + **emit `/goal`** → *(dev pastes `/goal`)* → 6. Run passes (cumulative, file-logged) → 7. Verify + complete → 8. Tickets (severity + complexity 1–5) → 9. Conflict-free waves (verified) → 10. Compact, commit per-file, draft PR.

Templates for the standing preamble, the per-pass runner, the verify pass, ticket synthesis, wave scheduling, and the `/goal` live in [templates.md](templates.md).
