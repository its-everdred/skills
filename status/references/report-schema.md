# reports.json

`reports.json` is one object holding the project name and every report, oldest first. The page renders the newest by default. Any field may be omitted; the page then skips that block.

```json
{
  "project": "Project name",
  "reports": [
    {
      "id": "2026-11-28T07:00Z",
      "window": { "from": "2026-11-27T15:50Z", "to": "2026-11-28T07:00Z" },
      "verdict": { "state": "on-track | at-risk | off-track", "headline": "One sentence that decides it" },
      "short": {
        "changes": ["What changed since the last report, one line each"],
        "followups": [{ "item": "Last report's question or risk", "outcome": "done | open | dropped", "note": "…" }]
      },
      "questions": [
        { "q": "Move workers to the backup provider until the reset?", "options": ["yes", "no"], "default": "yes", "ifUnanswered": "Proceeds at 8 AM" }
      ],
      "medium": {
        "milestone": { "name": "Monday launch", "due": "2026-11-30T17:00Z" },
        "goals": [{ "name": "Plain-words must-have", "done": 3, "total": 7, "prev": 1, "note": "Live: …; in progress: …" }],
        "shipped": [{ "title": "What the user can now do or see", "state": "live | merged | design", "image": "media/2026-11-28/voice.jpg" }],
        "inflight": [{ "title": "…", "stage": "building | review | blocked", "eta": "…" }],
        "budgets": [
          { "name": "Model plan, weekly", "provider": "plan-a", "used": 82, "observed": "2026-11-28T07:30Z", "resets": "2026-12-02T16:30Z", "windowHours": 168, "state": "ok | warn | bad", "bridge": "Second provider", "detail": "Credits available" },
          { "name": "Deploy quota", "provider": "host", "used": null, "detail": "No meter" }
        ],
        "models": [{ "backend": "plan-a", "account": "main", "model": "model-x", "effort": "medium", "budget": "Model plan, weekly" }],
        "issues": [{ "symptom": "…", "cause": "…", "fix": "…" }]
      },
      "long": {
        "lanes": ["Launch", "Platform", "Game A"],
        "items": [
          { "lane": "Platform", "title": "…", "start": "2026-12-01", "end": "2026-12-14", "priority": "now | next | later | parked", "state": "planned | building | done", "touched": "2026-11-20", "note": "Why it waits" }
        ]
      }
    }
  ]
}
```

- Times are UTC ISO strings. The page shows them in the viewer's time zone.
- `prev` on a goal shows the change since the last report.
- A budget's run-out forecast is computed by the page from `used`, `observed` (when the figure was read; defaults to the report time), `resets` and `windowHours`; `forecast` text is used when those are missing. `used: null` draws an empty bar with `detail` ("no meter", "not configured"). `state` overrides the computed colour; `bridge` names what covers a shortfall.
- `models` is the order work is dispatched to models, first choice first. `budget` names the budget whose bar and reset each row shows.
- Answers are not part of `reports.json`: the page stores them in its database, collection `answers`, one document per report id: `{ "reportId": "…", "answers": { "1": "yes" }, "notes": "…", "at": "…" }`.
- `priority: "parked"` and `"later"` items are drawn muted. A "touched" date older than 14 days is labelled with its age.
