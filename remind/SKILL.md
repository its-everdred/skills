---
name: remind
description: Use when the user says "/remind", "remind me to run X", "add that to my reminders", or when you hand them commands they must run themselves later (sudo, interactive login, another machine). Keeps a short checklist of commands with reasons in ~/remind.md; new chats surface due items automatically.
---

# Remind

`~/remind.md` is the user's checklist of things to run on this machine. A SessionStart hook (the `skill-sync` skill) shows every new Claude Code or Codex chat the open items, so the reminder reaches the user wherever they open a chat next.

## Format

Each item is two lines. The first is a checkbox, an optional due date, the command in backticks, a dash, then the reason in a few words. The second, indented, is the `ctx:` line that points back to the chat that added the item.

```
# Reminders

- [ ] 2026-10-14 `cd ~/github/opengym && sudo docker compose down --rmi all` — remove local openGym
  - ctx: claude 379070e2-… · ~/.claude/projects/-home-…-opengym/379070e2-….jsonl · https://claude.ai/code/session_01… · resume: `cd ~/github/opengym && claude --resume 379070e2-…`
```

- The command must be pasteable as is: include the `cd` when it matters, and use absolute or `~` paths.
- The reason is why to run it, not what it does.
- The date (`YYYY-MM-DD`) means "don't remind before". "Tomorrow" is a real date, so compute it with `date -d tomorrow +%F`. No date means remind at the next chat.
- Several commands that must run in order become several items, in order.
- **Never write the `ctx:` line by hand.** Generate it with `~/github/skills/remind/scripts/ctx.sh`, run from the chat's working directory. It works in Claude Code and Codex, and gives the session id, the transcript path, the Remote Control link when there is one, and the resume command. Items added in one batch share the same line.

## Adding

1. Create `~/remind.md` with the `# Reminders` heading if it doesn't exist.
2. Append the items, each with its `ctx:` line from `ctx.sh`. Never rewrite or reorder the user's existing lines.
3. Show the user the lines you added.

## Reminding

When the session-start context lists open items that are due:

1. In your first reply, list them one per line: the command and its reason. Then answer whatever the user asked.
2. When an item needs more background than its reason gives, read the chat that added it: `~/github/skills/remind/scripts/log.sh <transcript path from the ctx line>` prints that chat as plain conversation, in Claude Code or Codex format. Pass a second argument to cap each message's length (default 1500 characters).
3. If an item can be checked cheaply and without side effects (`docker ps`, `ls`, `tailscale serve status`), check first. If it's already done, say so and offer to tick it.
4. Tick an item (`- [x]`) only when the user says it's done or the check proves it. Delete ticked items older than a week when you're editing the file anyway.

Don't run reminded commands yourself unless the user asks: they're on the list because the user has to run them.
