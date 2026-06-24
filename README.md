# skills

Personal [Claude Code](https://docs.claude.com/en/docs/claude-code) skills.

| Skill | Description | Dependencies |
|-------|-------------|--------------|
| [`full-review-audit`](./full-review-audit) | Multi-pass, multi-skill review of a codebase that compounds findings across passes, adversarially verifies them, and turns them into a prioritized, merge-conflict-minimized ticket backlog. For production-readiness / security / fund-safety hardening at a scale too large for one pass. | [compound-engineering](https://github.com/EveryInc/compound-engineering-plugin) · [engineering-skills + engineering-advanced-skills](https://github.com/alirezarezvani/claude-skills) · [ethskills](https://github.com/austintgriffith/ethskills) · [superpowers](https://github.com/anthropics/claude-plugins-official) · Claude Code built-in `/code-review` & `/security-review` |
| [`pr-monitor`](./pr-monitor) | Watch a GitHub pull request URL for new review feedback while a developer is actively reviewing, then surface new comments quickly for follow-up changes. | `gh` · `jq` |

Dependencies are the review lenses the skill leverages — **recommended, not required**. The skill is skill-agnostic and falls back to role-prompted general agents when a lens isn't installed; it also recommends installing a stronger lens set when the agent is thin. (`superpowers:writing-skills` was used to author it.)
