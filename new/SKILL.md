---
name: new
description: Use when the user says "/new" or asks to open/start a new Claude chat or session in a folder (e.g. "/new open a new chat in ../folder", "... with my other account") so they can reach it from the Claude app without SSH. Launches claude in that directory inside tmux on either Claude account, with Remote Control on, and opens a terminal window when there is a desktop.
---

# New chat in a folder

Open a new Claude Code session in a directory on this machine and turn on Remote Control, so the user can pick it up from the Claude app.

## Steps

1. **Resolve the directory** from the request, relative to the current working directory (`../folder` means a sibling of cwd). `~` means the home directory.
   - If it doesn't exist, stop and say so. Don't create it unless the user asked for that.
2. **Pick the account.** By default, use the default account (`claude`). Add `--account second` for "my other/second account", "claude2", or the optional name in `CLAUDE_LOGIN2_NAME`; add `--account other` for "the account this session isn't on". If the current session predates setup, read the exact `CLAUDE_LOGIN2_NAME` export from `~/.bashrc` or `~/.zshrc`. The second account is the switch-login profile in `CLAUDE_LOGIN2_DIR`; if it isn't set up, say so and point to `/setup-switch-login`.
3. **Run the launcher** (it ships with this skill):
   ```
   <skill dir>/scripts/new-chat.sh [--account default|second|other] <resolved dir>
   ```
   Add `--no-rc` only if the user asks for Remote Control off.
4. **Report** the session name, the account, the folder, the inherited permission flags, the `remote:` link, and the attach command. Tell the user the chat should now be in the Claude app. If it exited saying claude is waiting on a prompt (for example a first `/login` on the second account), relay that: the user has to answer it once at the machine, or attach to it.

## What the script does

- Starts `claude` (or `claude2`) in the folder inside a detached tmux session named `claude-<folder>-<time>`. It goes through the switch-login wrapper when that's installed, so `/switch-login` works in the new chat.
- **Inherits permission flags** from the calling claude session: `--dangerously-skip-permissions` and `--permission-mode` are passed on only if this session has them. It never adds them.
- Answers the folder-trust prompt, because the user named the folder. It does not answer any other startup prompt. If one blocks startup, the script exits and prints `tmux attach -t <name>`, so the user can answer it.
- Starts claude with `--remote-control`, which is the same as typing `/rc`, and prints the session link.
- Opens a gnome-terminal window attached to the session when a desktop display is available.

## Requirements

`tmux`, `claude` on PATH, and Linux (`/proc`). The terminal window is optional. The second account needs the `switch-login` setup (`/setup-switch-login`).
