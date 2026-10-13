---
name: remind
description: Use when the user says "/remind", "remind me to run X", "add that to my reminders", or when you hand them commands they must run themselves later (sudo, interactive login, another machine). Keeps a short checklist of commands with reasons in ~/remind.md; new chats surface due items automatically.
---

# Remind

`~/remind.md` is the user's checklist of things to run on this machine. A SessionStart hook (the `skill-sync` skill) shows every new Claude Code or Codex chat the open items, so the reminder reaches the user wherever they open a chat next.

## Format

One line per item: a checkbox, an optional due date, the command in backticks, a dash, then the reason in a few words.

```
# Reminders

- [ ] 2026-10-14 `cd ~/github/opengym && sudo docker compose down --rmi all` — remove local openGym
- [ ] `sudo tailscale serve --https=8443 off` — stop serving it on the tailnet
```

- The command must be pasteable as is: include the `cd` when it matters, and use absolute or `~` paths.
- The reason is why to run it, not what it does.
- The date (`YYYY-MM-DD`) means "don't remind before". "Tomorrow" is a real date, so compute it with `date -d tomorrow +%F`. No date means remind at the next chat.
- Several commands that must run in order become several items, in order.

## Adding

1. Create `~/remind.md` with the `# Reminders` heading if it doesn't exist.
2. Append the items. Never rewrite or reorder the user's existing lines.
3. Show the user the lines you added.

## Reminding

When the session-start context lists open items that are due:

1. In your first reply, list them one per line: the command and its reason. Then answer whatever the user asked.
2. If an item can be checked cheaply and without side effects (`docker ps`, `ls`, `tailscale serve status`), check first. If it's already done, say so and offer to tick it.
3. Tick an item (`- [x]`) only when the user says it's done or the check proves it. Delete ticked items older than a week when you're editing the file anyway.

Don't run reminded commands yourself unless the user asks: they're on the list because the user has to run them.
