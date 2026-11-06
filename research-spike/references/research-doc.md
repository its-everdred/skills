# Research doc template (one per ticket)

```markdown
# <ticket id> — <title>: research

## Outcome
One paragraph: what exists when this ticket is done, as the user or a test sees it.

## Design
How it works. Decisions with the reason for each. Alternatives considered and why not.

## Prior art
Findings from the spike's prior-art reports and any `deep-research` run for this ticket: what others do, the guarantee
or limit that matters here, and the report each claim comes from. "None needed" when the ticket raises no external
question.

## Interfaces
- Consumes: <contract, file, type> from <ticket>
- Provides: <contract, file, type> to <tickets>

## Implementation units
1. <unit>: files <exact paths>; what to change; done when <check>.
2. ...

## Test scenarios
| Scenario | Input | Expected |
|---|---|---|

## Data and assets
Exact ids, paths, formats; known gaps and their fallback.

## Evidence to produce
Tests to run; screenshots or captures only where behaviour is visual.

## Risks
What could go wrong, how to detect it early, the fallback.

## Open questions
| Question | Recommended default | What changes if answered differently |
|---|---|---|
```
