---
name: status
description: Use when the user says "/status", asks "where are we", "status report", "what's in flight", "are we on track", "how are the budgets", or wants a debrief after time away. Writes a visual status report since the last report or debrief: in flight, shipped, on track or not, budgets and their resets with a run-out forecast, process issues, and the questions the user must answer, numbered so they can reply in one line ("1 yes 2 no 3 A 4 punt").
---

# Status

A status report lets someone who has been away catch up in a minute and unblock the work with one line. Every section answers a question the reader would ask. Every claim comes from something just read, never from memory.

## 1. Set the window

The report covers the time since the last status report or debrief.
- Look for the newest file in `docs/status/` (or `~/.status/<repo>/`).
- Failing that, look for the last debrief or voice-handoff file the project keeps, and use its mtime.
- If neither exists, cover the last 24 h.

State the window at the top of the report (`since Fri 07:50 PT`).

## 2. Gather (read, don't recall)

| Section | Source |
|---|---|
| In flight | the work tracker: running, in-rework and in-review tickets. On aiur, `aiur status` on every instance. |
| Shipped | PRs merged in the window, per repo (`gh pr list --state merged --search "merged:>=<window start>"`), plus deploys that reached prod. Merged is not shipped: say which are live. |
| On track | the user's stated goal and deadline, against what's still open on its critical path. |
| Budgets | each provider's usage meter, with used %, window length and reset time. On aiur: `GET /api/v1/usage`. |
| Issues | this window's incidents, repeated failures and process smells (the hourly retro logs, if the project keeps them). |
| Questions | open decisions only the user can make: spend, accounts, licences, taste, priority. |

**Run-out forecast for each budget.** Burn rate = used % ÷ elapsed share of the window. Projected run-out = now + remaining % ÷ burn rate.
- Mark the budget **at risk** when the run-out lands before its reset or before the deadline.
- Say what bridges the gap: the next provider, credits, or slower work.
- Label every forecast as an estimate.

## 3. Write it

Use the template in [references/template.md](references/template.md). Rules:
- **Lead with the verdict:** on track, at risk or off track, then the one reason that decides it.
- **Make it visual:**
  - a progress bar per goal (`████████░░ 80%`), with each % from an observable signal, or `—` if there is none;
  - a gauge per budget;
  - real images from shipped UIs and reviews (screenshots, stills, renders) beside the item they prove.
- **Use plain words.** A ticket number goes in parentheses at most, never alone.
- **Ask questions as a numbered list with fixed answer tokens** (`yes / no`, `A / B / C`, `punt`). Put the default first, and say what happens if the user doesn't answer (the work continues on the default). At most 5 questions; the rest wait for the next report.
- **Leave out anything without news.** A healthy system gets one line, not a section.

## 4. Deliver at the requested depth

| Depth | Format | Contains |
|---|---|---|
| Glance | chat text, ≤10 lines | verdict, 3 bullets, questions |
| Card | one image (HTML rendered to PNG at phone width) | verdict, bars, gauges, 2–3 thumbnails, questions |
| Full | a page (artifact or doc) | every section, images, tables, links |

Without a requested depth, send the glance and offer the card and the full page. Save each report to `docs/status/<YYYY-MM-DD>-<HHMM>.md` (or `~/.status/<repo>/`), which sets the next window.
