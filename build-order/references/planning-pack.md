# Planning pack

A directory (for example `docs/plans/<slug>/`) holding:

- `requirements.md`: from the brainstorm; each item marked decided, proposed default or open.
- `decisions.md`: technical decisions with reasons and rejected alternatives.
- `tickets/<id>.md`: one contract per ticket (outcome, owner files, implementation pointers, worked example, acceptance
  as checkable items, complexity, risk, capabilities needed, research doc link if a deep dive ran).
- `graph.json`: the typed graph.
- `validation.md`: wave profile, critical path, capacity comparison, mechanical checks, review findings and what was
  done about them, discovery policy.

`graph.json` shape:

```json
{
  "version": 1,
  "capstone": "T-40",
  "tickets": [
    { "id": "T-01", "title": "Skeleton and contracts", "lane": "foundation", "complexity": 3,
      "depends_on": [], "serializes_with": [], "suggested_after": [], "gates": [], "tracker": null }
  ],
  "contains": [ { "parent": "feature:example", "children": ["epic:foundation"] } ]
}
```
