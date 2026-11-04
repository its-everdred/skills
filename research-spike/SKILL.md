---
name: research-spike
description: Use for '/research-spike', "spike this", "research every ticket", or before implementing any multi-ticket project. Runs the compound-engineering brainstorm → plan loop to settle scope with the user (asking clarifications one at a time), hands the plan to a build-order skill to produce tickets, then runs a full brainstorm → plan deep dive on every ticket in parallel research agents and weaves the results into specs that weaker implementation agents can follow. Domain-free; other skills (such as a game or product planner) call it for their domain.
---

# Research spike

Turns an idea or an existing ticket set into researched, implementation-ready tickets. Two halves: **scope** (with the
user) and **deep dives** (in parallel, without the user). Each agent loads only the skills its work needs.

Arguments: a request in plain words, or `tickets:<list or build-order root>` to skip straight to the deep dives.

## 1. Scope with the user

1. Load `ce-brainstorm` (compound-engineering) on the request. Let the user describe it freely first; extract facts
   silently; then ask clarifications **one at a time**, only where the answer changes scope, behaviour, success
   criteria or what gets built first. Recommend an answer with each question. Never re-ask what they already said.
2. Write the requirements doc the brainstorm skill produces. Mark each item: decided by the user, proposed default, or
   open.
3. Load `ce-plan` on that doc: architecture, implementation units, dependencies, risks.

## 2. Build order

Load `build-order` with the plan: it cuts worker-ready tickets, builds the typed graph, computes waves and the critical
path, and files them. A tracker-specific layer (aiur: `aiur-build`) or a domain planner (for example a new-game
planner) adds its own rules on top.

## 3. Deep-dive every ticket, in parallel

Unasked, before any implementation is dispatched:

1. **One research agent per implementation ticket**, all at once (background agents, or `kind:research` tracker tickets
   that block their implementation tickets). Skip tickets that are themselves research.
2. Each research agent runs `ce-brainstorm` (no user questions: record them with a recommended default) then `ce-plan`
   on its ticket, reading the requirements doc, the code and data it touches, and its neighbours' contracts. It writes
   `docs/research/<ticket>.md` with the sections in `references/research-doc.md`.
3. Give each agent only the skills its ticket needs (a design ticket gets design skills, a data ticket gets testing
   skills); point to the rest by name.

## 4. Weave

When a lane's research lands: reconcile contradictions across tickets (shared names, contracts, data formats), write
`docs/spec/<area>.md` as the final design for that area, and rewrite each implementation ticket to point at its research
doc and spec section, with acceptance as checkable items. Questions the research raised go to the user one at a time
with a recommendation; they never block unrelated tickets.

## 5. Write for a weaker implementer

Assume the implementation agent is less capable than the planner: exact paths and names, no "as appropriate", one
obvious next action per unit, test scenarios with expected values. If a ticket still needs judgment, split it or move
the judgment into the spec. Only then release the tickets to implementation.

## Rules

- Keep private material (user transcripts, sensitive context) out of public tickets and docs; reference it.
- Label honestly: decided, proposed default, open, pending evidence. Silence is never approval.
- Depth over speed in research; brevity in tickets.
