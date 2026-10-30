---
name: meta-improve
description: Use for '/meta-improve', 'meta pass', 'hourly retro', 'what did we learn', or on the hourly timer this skill sets up. Reviews the last hour of work in any repo or process for patterns (what the user pushed back on, iterated on or emphasised; hiccups; manual steps), writes an hourly log for the record, and persists each lesson where future agents will actually act on it (the skill, tool, memory or project rule that governs that step) without letting those files balloon.
---

# Meta-improve

An hourly look back that makes the next hour better. Two outputs, kept apart on purpose:

- **The log** is history: what happened, the patterns, the reasoning. Detailed is fine; nobody acts on it.
- **The persistence** is behaviour: small edits to the skills, tools, memory and project rules that future agents load.
  If a lesson lives only in the log, it is lost. The log never substitutes for an edit.

## 0. Keep the listener running

On first use in a session, and whenever `CronList` shows no meta-improve job, schedule one:
`CronCreate` with cron `<m> * * * *` (any minute except 0 or 30) and prompt `/meta-improve (hourly timer)`.
Session jobs die with the session and expire after 7 days, so recreate it; say once that it is running.

## 1. Gather the hour

```bash
python3 -I ~/.claude/skills/meta-improve/scripts/signals.py --since 60
```
(`--transcript PATH` for another session; set `CLAUDE_CONFIG_DIR` for a second login.) It lists every user message,
interruptions, tool errors, files edited 3+ times and repeated commands. Read it, then skim the transcript where a
signal needs context. Also read the previous log's "to watch" list.

## 2. Find the patterns

Look for these, in this order. Each one is a candidate lesson.

1. **Pushback and corrections.** The user said no, "I don't like", "instead", "again", undid a choice, or repeated an
   ask. What rule would have produced the right thing the first time?
2. **Iteration loops.** The same thing reworked 3+ times (files edited 3+ times, renders redone). What missing step
   (a lineup, options first, a check) would have shortened it?
3. **Emphasis and taste.** What the user stressed, praised or kept choosing: visual taste, process preferences, tone.
4. **Hiccups.** Tool errors, wrong assumptions, a wrong path taken, time lost waiting, a check done wrong (for
   example a montage sorted out of order). What one change prevents the repeat?
5. **Manual steps.** Anything done by hand twice that a script or tool could do. Automate it or note the script.
6. **Carried claims.** Re-verify anything you are about to repeat from an earlier log; mark it "unverified since"
   if you can't.

Drop anything that only mattered once. A lesson needs a reason it will recur.

## 3. Persist each lesson where it will be acted on

Pick the narrowest home that the next agent doing that step will load:

| The lesson is about | Put it in |
|---|---|
| how a recurring task is done | the skill for that task (edit in place) |
| a repeated manual step | a script or tool, and one line in the skill that points to it |
| this user's taste or process preferences | memory (feedback type, with why and how to apply) |
| a fact about this repo or project | memory (project type) or the repo's CLAUDE.md / AGENTS.md if every agent needs it |
| a missing skill the work keeps needing | a new, small skill (only when no existing skill fits) |

**Anti-bloat rules (hard):**
- Edit before adding. Rewrite the sentence that was wrong instead of appending a correction.
- One rule, one place. Link to it elsewhere; never copy it.
- Net growth per pass: at most ~15 lines across all skills. If a lesson needs more, it belongs in a script or a
  `references/` file the skill links to.
- A SKILL.md over ~250 lines gets tightened in the same pass: merge, cut obsolete rules, move detail out.
- Delete rules the user has since reversed. Stale rules are worse than none.
- Check before writing: grep the skills and memory for the idea; update the existing line if it is there.

Commit edits to repos you own (project skills with the project; this skills repo on a branch with one rolling PR,
`meta-improve/updates`, unless its README says otherwise). Never edit the user's product code from this skill.

## 4. Write the log

`<repo>/docs/meta/<YYYY-MM-DD>/<HHMM>.md` when the repo has `docs/`, else `~/.meta-improve/<repo>/<YYYY-MM-DD>/<HHMM>.md`:

- **Hour in brief:** what was worked on, in a few lines.
- **Patterns:** each with its evidence (quote the user, name the file or command).
- **Changes made:** each persisted edit, with its file, so the record shows where the lesson lives now.
- **Considered and dropped:** with why (one-offs, already covered).
- **To watch:** patterns seen once that may recur; the next pass checks them.

## 5. Report

- **Attended** (a user message opened the turn): a short summary of the changes made.
- **Unattended** (the timer fired): one line per persisted change; **nothing** if there were none. The log is written
  either way. Never interrupt in-progress work beyond the pass itself: do it, then resume what you were doing.
