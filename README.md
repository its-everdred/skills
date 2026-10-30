# skills

Personal [Claude Code](https://docs.claude.com/en/docs/claude-code) skills.

| Skill | Description | Dependencies |
|-------|-------------|--------------|
| [`black-october`](./black-october) | `/black-october`: runs the `security-audit` skill with the October 2026 incident context (PHP2Shell, Node.js, eMudhra, npm worms) and live sources to refresh it. | [`security-audit`](https://github.com/cloudflare/security-audit-skill) · `gh` · `curl` |
| [`branch-cascade`](./branch-cascade) | `/branch-cascade`: synchronize stacked branches or watch upstream changes. Rebase is the default recommendation; asks for rebase or merge before updating branches. Never merges PRs without separate authorization. | git · `gh` |
| [`full-review-audit`](./full-review-audit) | Multi-pass, multi-skill review of a codebase that compounds findings across passes, adversarially verifies them, and turns them into a prioritized, merge-conflict-minimized ticket backlog. For production-readiness / security / fund-safety hardening at a scale too large for one pass. | [compound-engineering](https://github.com/EveryInc/compound-engineering-plugin) · [engineering-skills + engineering-advanced-skills](https://github.com/alirezarezvani/claude-skills) · [ethskills](https://github.com/austintgriffith/ethskills) · [superpowers](https://github.com/anthropics/claude-plugins-official) · Claude Code built-in `/code-review` & `/security-review` |
| [`new`](./new) | `/new open a new chat in ../folder` (optionally "with my other account"): starts Claude in that folder inside tmux on either account, inheriting the calling session's permission flags, with Remote Control on so it shows up in the Claude app, and opens a terminal window when there is a desktop. | `tmux` · Linux `/proc` · optional `gnome-terminal` |
| [`pr-monitor`](./pr-monitor) | Watch a GitHub pull request URL for new review feedback while a developer is actively reviewing, then surface new comments quickly for follow-up changes. | `gh` · `jq` |
| [`publish-mobile-app`](./publish-mobile-app) | Bootstrap an app-agnostic set of deploy/screenshot scripts into an Expo React Native + web project and run the full lifecycle of publishing a mobile app to both the Apple App Store (TestFlight) and Google Play — iOS/Android setup + upload, store screenshots, and version bumps. App identity is derived at runtime from `app.json`/`.env`. | `expo`/`eas` CLI · `xcodebuild` · `keytool` · `sips` · Playwright · `jq`/`node` |
| [`remind`](./remind) | `/remind`: keeps `~/remind.md`, a checklist of commands to run on this machine (command, reason, optional due date, and a link back to the chat that added it, so a later agent can read that chat's log). Every new Claude Code or Codex chat surfaces the due items through the `skill-sync` hook. | the `skill-sync` hook |
| [`setup-switch-login`](./setup-switch-login) | `/setup-switch-login`: creates the second profile, links shared entries, installs the skill, and adds the wrapper to your shell rc. An optional machine-local name exposes `claude-<name>` alongside `claude2`. | bash · the `switch-login` skill |
| [`skill-sync`](./skill-sync) | Links every skill in this repo into `~/.claude/skills`, `~/.codex/skills` and `~/.agents/skills`, installs the pinned `shared` external skills, and installs a SessionStart hook in both so each new chat pulls the repo and links new skills. Set up a machine once with `skill-sync/scripts/install.sh`. | bash · git · python3 · Claude Code and/or Codex |
| [`switch-login`](./switch-login) | Run two Claude Code accounts on one machine (`claude` for the default account; `claude2` or an optional `claude-<name>` for the second, with shared settings, skills and transcripts) and move a live session to the other account in place with `/switch-login`, keeping Remote Control on so it still works from the Claude app. | bash or zsh · optional `tmux` + the `new` skill |

Dependencies are the review lenses the skill leverages — **recommended, not required**. The skill is skill-agnostic and falls back to role-prompted general agents when a lens isn't installed; it also recommends installing a stronger lens set when the agent is thin. (`superpowers:writing-skills` was used to author it.)

## Guidance

Advice and pre-prompts that are not skills live in [`guidance/`](./guidance). Each `guidance/<name>.md` is linked to `~/.agents/<name>.md` on every sync. Claude loads it through an `@` import in `~/.claude/CLAUDE.md` and Codex through a `~/.codex/AGENTS.md` symlink.

| Guidance | Description |
|----------|-------------|
| [`coding-principles`](./guidance/coding-principles.md) | Readability, naming, scope, reuse and review habits for any coding task, from the user's PR feedback. |

## External skills

Skills from third-party plugins and marketplaces are not stored here. They are listed in [`external-skills.json`](./external-skills.json) (Claude Code marketplaces and plugins, plus Codex skill sources pinned to a commit). After a `git pull` on any machine, run:

```bash
./sync-external.sh --dry-run   # preview
./sync-external.sh             # apply
```

It needs `jq`, and uses the `claude` and `codex` CLIs when present. It is idempotent: it only adds missing marketplaces and plugins, never overwrites an existing Codex skill that differs from the pinned copy, and never runs code from the cloned repos. Claude plugin versions in the manifest are recorded, not enforced (`claude plugin install` cannot pin). Internal marketplaces sit under the `private` key, which the script ignores.

### Shared skills

The `shared` section lists pinned skill sources (`repo`, `ref`, `subpath`, optional `dest`, default `~/.agents/skills`, which Codex and OpenCode scan). Each skill is copied there and linked into `~/.claude/skills`. A differing existing skill is kept and reported. Pins change only by editing the manifest.

```bash
./sync-external.sh --shared-only   # shared section only; combine with --dry-run to preview
```

`skill-sync/scripts/sync.sh` runs this on every sync and prints changes and failures. Tests: `skill-sync/tests/sync-test.sh`.
