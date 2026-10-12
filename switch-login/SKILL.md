---
name: switch-login
description: Move this Claude Code session to the other Claude account, leaving other sessions alone. Use only when the user runs /switch-login.
disable-model-invocation: true
---

# Switch login

Run this and nothing else, then end your turn with one short line:

```
bash ~/.claude/skills/switch-login/scripts/switch.sh
```

It restarts this session in the same pane on the other account (`claude` = default
profile, `claude2` = the profile in `$CLAUDE_LOGIN2_DIR`; transcripts are shared), with the conversation
resumed. Other panes are not affected.

If it prints a command instead, the session was started before the shell wrapper
(`claude-login.zsh`, sourced from `~/.zshrc`) was loaded: show that command in a code
block and tell the user to exit and run it.

Setup (second profile, `~/.zshrc` lines): see `README.md` in this directory.
