---
name: setup-switch-login
description: Set up a second Claude Code account on this machine for the switch-login skill (claude / claude2). Use only when the user runs /setup-switch-login.
disable-model-invocation: true
---

# Set up switch-login

1. Find the installer, `switch-login/scripts/setup.sh`: `~/.claude/skills/switch-login/scripts/setup.sh` if that exists, otherwise the copy in the user's clone of the skills repo. If the user named a profile directory, pass it as the argument (default `~/.claude-2`).
   ```
   bash <path>/setup.sh [PROFILE_DIR]
   ```
2. Report what it changed (its "changed:" list), or that nothing changed. If it refused, show the "Found:" lines and stop. Don't fix them yourself without asking.
3. Give the user the one step it cannot do, as a code block:
   ```
   claude2
   ```
   Then `/login` with the second account. They have to run this in a **new** shell so the rc lines are loaded.

Never read, copy or print `.credentials.json`, `.claude.json` or `sessions/` in either profile.
