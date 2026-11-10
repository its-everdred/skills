---
name: move-chat
description: Move this Claude Code chat into a window of the "claude" tmux session (or a named one), so it survives logout. Use only when the user runs /move-chat.
disable-model-invocation: true
---

# Move chat

Run this and nothing else, then end your turn with one short line:

```
bash ~/.claude/skills/move-chat/scripts/move.sh [SESSION]
```

Pass SESSION only when the user names a tmux session; the default is `claude`, the session `claudes` (from the `new` skill) opens.

It stops this process and resumes the same conversation as a new window of that tmux session (creating the session if needed), on the same account, in the same folder, with this session's permission flags and Remote Control on. The terminal this chat ran in is left at its shell. When no one is attached to the session, a terminal window opens on it; otherwise the window shows up in the session's status bar. If the chat is already in that session, it says so and does nothing.

Needs `tmux` and the `new` skill (`new/scripts/new-chat.sh`).
