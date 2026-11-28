---
name: status
description: Use when the user says "/status", asks "where are we", "status report", "what's in flight", "are we on track", "how are the budgets", or wants a debrief after time away. Writes a status report since the last one at three horizons (short: now; medium: the current milestone; long: a roadmap timeline that includes low-priority work the user may want to pull forward), with questions the user answers in a form on the page, and appends it to one searchable dashboard page that keeps every report.
---

# Status

A status report lets someone who has been away catch up in a minute and unblock the work with one line. Every claim comes from something just read, never from memory. Every report goes on the same page, so the user can switch between days, search them, and copy from several at once.

## 1. Read the previous report first

Find the status page and read its newest report before gathering anything.
- The page's address is in `.status/page` at the project root, or `~/.status/<project>/page` when the project isn't a repo.
- The data is `reports.json`, with a local copy in `.status/reports.json`.
- If there's no page yet, the window is the last 24 h, or since the last debrief the project records.

**Read the answers first.** If the page stores answers (see step 4), list its `answers` collection; each document is keyed by report id. Act on every answer to an earlier report, and treat a note as the user's words. A project may run a watcher that notifies the agent when an answer lands; without one, the agent checks when it next runs.

The previous report sets:
- **the window:** since its time;
- **what to follow up:** its open questions, risks and "next" items each get an outcome in the new report (done, still open, dropped);
- **the baseline:** progress and budget figures are compared with it ("3/7 → 5/7").

## 2. Gather (read, don't recall)

| Topic | Read |
|---|---|
| In flight | the tracker: running, in-review and blocked work |
| Shipped | merged and deployed changes in the window, per repo. Merged is not shipped: say what's live. |
| Goal | the user's stated goal and deadline, against what's open on its critical path |
| Budgets | every metered provider the orchestrator or project uses (model plans, API credits, voice or image APIs, CI minutes, deploy quotas): used %, window length, reset time. Read each live, for example from the orchestrator's usage API or the provider's own usage endpoint. A provider with a key but no readable meter is listed as "no meter"; one without a key as "not configured". |
| Models | the order work is dispatched to models (backend, account, model, effort), from the orchestrator's config |
| Issues | incidents, repeated failures and process smells in the window, with root cause and fix |
| Backlog | parked, low-priority and someday items, with when they were last touched |
| Questions | decisions only the user can make: spend, accounts, licences, taste, priority |

**Run-out forecast for each budget.** Burn rate = used % ÷ elapsed share of the window. Run-out = now + remaining % ÷ burn rate. The page computes it from `used`, `observed`, `resets` and `windowHours`.
- Mark the budget **at risk** when the run-out lands before its reset or before the deadline.
- Name what bridges the gap.
- Label every forecast as an estimate.

## 3. Write three horizons

Each horizon gets its own depth. Together they fit one page.
- **Short (now), ≤6 lines.**
  - The verdict (on track / at risk / off track) and the one reason that decides it.
  - What changed since the last report.
  - The questions.
- **Medium (this milestone).**
  - A progress bar per must-have, with done/total parts from observable signals, or `—` when there are none.
  - Shipped work with real images: screenshots, stills, renders.
  - In flight, budgets with forecasts, the models order with each provider's bar, issues.
- **Long (the roadmap).**
  - A timeline of projects, features and tickets by lane and expected time.
  - It deliberately includes parked and low-priority items, muted, each with its age. Seeing them jogs the user's memory, so they can pull one forward.

**Questions:** a form on the page, one radio group per question with fixed answer tokens (`yes / no`, `A / B / C`, `punt`), and an optional note.
- The default comes first and is preselected.
- Say what proceeds without an answer.
- At most 5 questions; the rest wait.
- Submitting stores one document per report in the page's `answers` collection: `{reportId, answers: {"1": "yes", …}, notes, at}`, keyed by the report id. The page then shows "Sent" and pre-fills the saved answers.
- The one-line reply (`1 yes 2 no 3 A 4 punt`) stays as a copyable fallback for chat.

**Writing:**
- Use plain words, and put identifiers in parentheses at most.
- Leave out anything without news.
- The schema is in [references/report-schema.md](references/report-schema.md).

## 4. Publish: append to the one page

The page is [assets/status-page.html](assets/status-page.html), a single dashboard that renders `reports.json`:
- a verdict chip and headline, then KPI tiles (milestone countdown, goals done/total, open questions, budget at risk);
- the questions form;
- sections collapsed to one-line summaries (shipped, changes, goals, in flight, budgets, models, issues, roadmap); shipped is a horizontal strip of screenshots that open in a lightbox;
- a report picker, a history table, search across every report, and a copy button on each section plus "copy results".

Steps:
1. Append the new report to `.status/reports.json`. Never rewrite earlier reports: correct one only with a note.
2. Put its images under `media/<YYYY-MM-DD>/`. Keep about 6 per report, compressed, at most 720 px wide.
3. Publish to the same address every time, so the user keeps one link.
   - **Claude:** one Artifact with `capabilities: {db: {}, user: {}}` (the form stores answers in its database). On the first report, publish `status-page.html` as the page, with `reports.json` and the media as supporting files, and save the URL to `.status/page`. After that, republish to that URL with the updated `reports.json` and the new media only. Mind the artifact's file limit: drop media older than about 30 days from the publish, and keep their reports.
   - **Codex:** publish the same page and data with Codex's Sites feature, updating the same site each time.
   - **Anywhere else:** a static folder in the repo (`docs/status/`) that opens in a browser. Without a database the form hides its submit button and the copyable reply is the answer path.
4. In chat, send the short horizon and its questions, followed by the page link.
