# Coding principles

Shared by Claude, Codex and subagents. Apply when writing, reviewing or refactoring code, including in skills and background agents. A repo's AGENTS.md wins on conflict.

Before reporting code done, reread the diff as a reviewer against this list and fix what you find. Mechanical fixes inside the change need no approval. Report them after.

## Readability

- A function reads top to bottom as a few named steps. Split it when it mixes steps (fetch, transform, aggregate) or passes about 20 lines of logic.
- No nested loops. Flatten with `flatMap`, `filter` and `map`, or move the inner loop into a named function.
- One idea per `return` or call line. A chain of splat, map, sort and string-building gets helper functions.
- Name an inline callback (`const query = () => ...`) before passing it to a wrapper.
- Prefer early returns over an if/else chain that assigns a variable. Give each state its own function or component.
- Small single-use helpers and components live in the file that uses them. Split a file when it is reused or passes 200 lines.

## Scope

- Keep the diff to what the task needs. Do not touch a shared file or util for a convenience. If a change is not needed for the PR, leave it out.
- Keep each domain value (a time window, a bucket size) in one place and derive the rest from it. Do not hard-code it again elsewhere.

## Naming

- One name per concept. A function never shares its name with the function it calls.
- No vague names (`run`, `ctx`, `data`, or `compliance` for a chain config). A name says what a value holds or what a wrapper does (`runQueryWithMetrics`).
- Identify by ID, never by display name or label.
- For a new shared helper or parameter name, offer 2 to 4 options with a recommendation.

## Inputs

- Pass a function only what it uses (a log source, not the whole chain config).
- Do not make callers pass what the function can work out itself (the current time, a derived tag). Accept it only with a stated reason. Tests use fake timers.
- Derive related strings (log tag, metric label) from one name. Do not hand-write the same name in several places.

## Reuse

- Before adding a helper, regex, dependency or pattern, search the repo, including `shared/` folders, for an existing one. Say what you found.
- When asked whether a pattern is common here, answer with examples from the repo.
- Keep the layers: controllers wire and instrument, services hold the logic, pure functions transform.

## Comments

- Say why. Reread each comment as someone without the diff and reword any that is vague.
- A single-line comment above every regex says what it matches. Name regex constants for what they match.
- No stacked comments, ticket IDs or em-dashes.

## UI

- Elements of the same kind share one style. Extract a class or constant when two titles match.
- Short labels ("1 HR", "24 HR"). Offer only options the backend and design support.

## Pull requests and git

- A description has a one-sentence Problem, a one-sentence Solution summary, at most 5 bullets, and no test plan.
- Push commits on a feature branch when asked, so local and origin never diverge. Never force-push an approved PR.
- Cascade a stack only when a PR is ready and the next one is about to start.

## Working with the user

- Be concise. Verify before asserting: check merged and done claims against git and GitHub, not labels or memory.
- Ask where something lives (controller or service, shared or local) by reading the repo first.
