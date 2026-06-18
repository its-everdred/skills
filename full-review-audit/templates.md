# Templates & Patterns

Reusable shapes for the `full-review-audit` skill. Adapt paths, skill names, and surfaces to the repo and runtime. Pseudocode uses a generic `agent()` / `parallel()` / workflow vocabulary; map it to your runtime's orchestration tool (or to sequential subagent dispatch if there is none).

---

## 1. Standing-rules preamble (prepended to every pass)

```
You are a subagent in review PASS <N> (<label>) of a cumulative review of <PROJECT>. cwd = repo root.

DOMAIN: <one line — e.g. a DeFi codebase; dominant risk is a user losing funds or signing a malicious tx>. Prioritize that lens above style.

STANDING RULES (hard):
- Flag only the in-scope problem classes agreed in planning (e.g. missing OBVIOUS validation, sibling-inconsistency, real fund-loss/malicious-sign). Do NOT scope-creep into <out-of-scope list, e.g. speculative intent-guessing, RPC-trust>.
- <surface-specific rule — e.g. demo/CLI are REVIEW-ONLY: low-risk fixes vs backlog, no refactors. Core SDK refactors allowed.>
- Ground EVERY finding in a real path:line.

LENS: Apply the methodology of the "<skill>" review skill. If it is directly invocable, invoke it and apply it to your surface; otherwise act as that specialist. Keep your search BROAD — the examples in your assignment are seeds, not a checklist.

CUMULATIVE DEDUP: Read <ledger path> (the running deduped index) and skim prior pass files. Do NOT re-report a finding already there. To sharpen or refute a prior finding, set relatesToPriorFinding to its ID. Also read <open-issues snapshot> and set candidateExistingIssue.

PASS DIRECTIVE: <the per-pass broad lens prompt>
```

Per-finding output schema: `{surface, file, line, severity: critical|high|medium|low, fundSafetyClass|class, title, detail, exploitOrRepro, recommendation, candidateExistingIssue, suggestRefactor, relatesToPriorFinding}`.

---

## 2. Cumulative ledger seed (`docs/reviews/_ledger.md`)

```
# Review — Findings Ledger
Deduped index across all passes. Each pass appends new/refining rows and writes full detail to docs/reviews/review-pass-NN.md.
Status legend: new · refines:Fxxx · dup:Fxxx · verified · demoted.
NEXT_ID: F001

| ID | Pass | Surface | File:Line | Severity | Class | Title | Status | Cand. issue |
|----|------|---------|-----------|----------|-------|-------|--------|-------------|
<!-- merge agents append rows below this line -->
```

---

## 3. Per-pass runner (workflow pattern)

One reusable script. **Edit only the `p` config block per pass**, then re-run. Each pass = fan out one subagent per surface → a merge step writes the pass file and updates the ledger → return a compact summary (so the orchestrator stays lean).

```js
// CONFIG — edit this block each pass
const p = {
  passNumber: 1,
  passLabel: 'baseline code-review',
  skill: '<review skill for this pass>',
  scope: 'core',          // or 'review-only'
  lensPrompt: '<broad lens directive; cite examples as seeds, say "search beyond them">',
  surfaces: [             // partition the codebase; ~6-8 keeps fan-out parallel
    { key: 'domainA', paths: '<glob>' },
    // ...
  ],
}

phase('Review')
const findings = await parallel(p.surfaces.map(s => () =>
  agent(PREAMBLE(p, s), { label: `p${p.passNumber}:${s.key}`, schema: FINDING_SCHEMA })))

phase('Merge')   // ONE agent: read ledger, dedup, assign IDs from NEXT_ID,
                 // WRITE docs/reviews/review-pass-NN.md (full detail),
                 // UPDATE the ledger (append new/refines rows, bump NEXT_ID),
                 // RETURN a short summary {newFindings, topSeverity[], highlights[], handoffNote}.
return await agent(MERGE_PROMPT(p, findings), { schema: SUMMARY_SCHEMA })
```

Run passes **sequentially** (each needs the prior ledger). Between passes the orchestrator keeps only the returned summary. Compact at a pass boundary if context runs high, leaving a handoff note (last pass #, ledger path, next skill).

Notes: pass an explicit **config block as a literal** (some runtimes don't bind an external args object); keep surfaces stable across same-scope passes and only swap them when the scope changes (e.g. core → backend → frontend → cli).

---

## 4. Verify + completeness pass

```js
phase('Triage')      // read ledger → list every high/critical finding
phase('Verify')      // one skeptic per finding, DEFAULT = refute:
  // "Read the actual code. Try to prove this is a false positive, already-guarded,
  //  unreachable, or over-severe. Confirm only if real and reachable via the public API.
  //  Return confirmed | refined(correctedSeverity) | demoted."
phase('Complete')    // a few lenses, each: "Given the full ledger, what fund-loss /
                     //  malicious-sign vector has NO finding yet? Return only novel gaps."
phase('Merge')       // mark rows verified/demoted/refined, append novel gaps, write review-pass-NN.md
```

Rule: a *missing test* is deflated to its own (usually low) severity — it cannot move funds; the underlying logic bug keeps its high.

---

## 5. Ticket synthesis

```js
phase('Plan')   // ONE strong agent reads the ledger → clusters into ~30-55 tickets.
  // Bundle findings that share a root cause into ONE ticket. Cross-cutting fix = ONE ticket, single owner.
  // DROP status=demoted. FOLD refines into parents.
  // Per ticket: slug, title, severity (verified max), complexity 1-5, domain, findingIds,
  //   candidateExistingIssue, augmentExisting (bool), scopeOneLine, roughBlockers[].
phase('Write')  // parallel, one agent per ticket → writes docs/tickets/<slug>.md:
  // metadata block (Severity, Complexity 1-5, Domain, Resolves findings, Candidate issue, Blocked by)
  // IF augmentExisting: a banner ">  AUGMENT existing issue #N — NOT a new ticket; add this color, flag important."
  // sections: Problem · Findings (F-id, path:line) · Root cause · Recommended approach (respect scope) ·
  //           Affected files (repo-relative) · Acceptance criteria/tests · Notes
phase('Order')  // see §6
```

Complexity 1–5: 5 = cross-module / signing-path / new infrastructure; 1 = a localized one-file fix.

---

## 6. Conflict-minimizing wave schedule (+ independent verify)

```js
phase('Extract')  // per ticket, the SET of files it will EDIT (from its "## Affected files" section)
phase('Schedule') // greedy, deterministic:
  //  Hard rule A: no two tickets in a wave share ANY file.
  //  Hard rule B: a ticket waits until all its blockers are in earlier waves.
  //  Each wave: maximal set with pairwise-disjoint files + satisfied blockers.
  //  Tie-break: is-chokepoint > higher severity > unblocks-more > touches-hotter-file > lower complexity.
  //  Expand to as many waves as needed. Compute hotFiles (edited by >=2 tickets) — they drive serialization.
phase('Confirm')  // an INDEPENDENT agent re-extracts files + parses waves and asserts ZERO
                  // (wave, file) collisions. Repair and re-confirm if any remain.
```

Write `docs/tickets/_INDEX.md`: the canonical ticket table + the wave lists (state "within any wave, no two tickets edit the same file") + a Hot files section explaining why the schedule has the wave count it does.

---

## 7. The handoff `/goal` (copy-paste; emitted at the end of planning)

Fill the `<...>` from the planning phase and give it to the developer to paste back:

```
/goal — Execute the <PROJECT> review end to end.

Run <N> cumulative review passes, then synthesize tickets and schedule waves. Each pass = one skill
that fans out ~6 subagents by surface, loads the running ledger, dedups, and only adds/refutes findings
(never re-derives). Lens prompts stay BROAD: cite examples only as seeds and search beyond them.

Standing rules (every pass): <domain + dominant risk>. In scope: <problem classes>. Out of scope:
<exclusions>. <surface rules: core refactors OK; demo/CLI review-only, no refactors>. Ground every
finding in path:line.

Passes (sequential, cumulative):
1 <skill> (<focus>) · 2 <skill> (<focus>) · ... · <verify pass> (skeptic per high finding + completeness)
· <final whole-flow pass>.
<plus any review-only passes per peripheral surface, each a specialist pass then a broad code-review pass>

Logging/compaction: each pass writes full findings to docs/reviews/review-pass-NN.md and updates the
deduped index docs/reviews/_ledger.md. Compact before a pass if near ~90% context, leaving handoff
notes (last pass #, paths, next skill).

Tickets: cluster the ledger into docs/tickets/<slug>.md — one per ticket, each with a severity label and
a complexity label 1-5. Drop demoted findings. If a finding maps to an important existing issue, still
write the doc but mark it "AUGMENT existing issue #N — NOT a new ticket". Then schedule into
conflict-minimizing waves (no two tickets in a wave edit the same file; chokepoints first) and write
docs/tickets/_INDEX.md; independently verify zero collisions. Do NOT file to the issue tracker (that is
a later dedup phase).

Persist: per-file commits on a new branch, push, open a DRAFT PR. Nothing merged.

<any open product decision, with its default — e.g. "Decision X: defaulted to <A>; flag <B> in the ticket for sign-off.">

Ends when: <N> review-pass logs + the ledger + the docs/tickets/ set (with _INDEX.md) all exist and the draft PR is open.
```
