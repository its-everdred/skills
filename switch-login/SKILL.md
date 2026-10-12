---
name: switch-login
description: Move this Claude Code session to the other Claude account, leaving other sessions alone. Use only when the user runs /switch-login.
disable-model-invocation: true
---

# Switch login

Run this and nothing else, then end your turn with one short line:

```
bash ~/.claude/skills/switch-login/scripts/switch.sh [rc|no-rc]
```

Pass `rc` when the user asks for Remote Control (`/rc`) after the switch, and `no-rc`
when they ask for it off. With no argument, the resumed session gets Remote Control
when this one has it on, so a user on the Claude app keeps access.

It restarts this session in the same pane on the other account (`claude` = default
profile, `claude2` = the profile in `$CLAUDE_LOGIN2_DIR`; transcripts are shared), with the conversation
resumed. Other panes are not affected.

If the session was not started through the shell wrapper (`claude-login.sh`, sourced
from `~/.bashrc` or `~/.zshrc`), the script resumes it in a new tmux session on the
other account with Remote Control on (this needs the `new` skill and tmux), and this
pane's session stops. Tell the user to pick it up in the Claude app. If it prints a
command instead, show that command in a code block and tell the user to exit and run it.

Setup: run `/setup-switch-login`, or `scripts/setup.sh`. See `README.md` in this directory.
