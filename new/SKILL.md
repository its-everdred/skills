---
name: new
description: Use when the user says "/new" or asks to open/start a new Claude chat or session in a folder (e.g. "/new open a new chat in ../folder", "... with my other account") so they can reach it from the Claude app without SSH. Launches claude in that directory inside tmux on either Claude account, with Remote Control on, and opens a terminal window when there is a desktop.
---

# New chat in a folder

Open a new Claude Code session in a directory on this machine and turn on Remote Control, so the user can pick it up from the Claude app.

## Steps

1. **Resolve the directory** from the request, relative to the current working directory (`../folder` means a sibling of cwd). `~` means the home directory.
   - If it doesn't exist, stop and say so. Don't create it unless the user asked for that.
2. **Pick the account.** By default, the new chat uses the same login as this session (`--account current`, the script's default): a session on the second profile opens the new chat there too. Add `--account default` for "my main/default account" (`claude`); add `--account second` for "my other/second account", "claude2", or the optional name in `CLAUDE_LOGIN2_NAME`; add `--account other` for "the account this session isn't on". If the current session predates setup, read the exact `CLAUDE_LOGIN2_NAME` export from `~/.bashrc` or `~/.zshrc`. The second account is the switch-login profile in `CLAUDE_LOGIN2_DIR`; if it isn't set up, say so and point to `/setup-switch-login`.
3. **Run the launcher** (it ships with this skill):
   ```
   <skill dir>/scripts/new-chat.sh [--account current|default|second|other] <resolved dir>
   ```
   Add `--no-rc` only if the user asks for Remote Control off.
4. **Report** the session name, the account, the folder, the inherited permission flags, the `remote:` link, and the attach command. Tell the user the chat should now be in the Claude app. If it exited saying claude is waiting on a prompt (for example a first `/login` on the second account), relay that: the user has to answer it once at the machine, or attach to it.

## What the script does

- Names the conversation `<machine> - <project>`, for example `PC - Aiur` or `NUC - GM`, with `scripts/convo-name.sh`. The machine is `PC` on orangekid and `NUC` on a host whose name contains "nuc", or `$CLAUDE_MACHINE_LABEL`. The project is the repository's main checkout name (a worktree names its repo): `aiur` → Aiur, `open-game-maker` → GM, `khala` → Khala, others capitalized, or `$CLAUDE_PROJECT_LABEL`. Remote Control uses the same name.
- Starts `claude` (or `claude2`) in the folder inside a detached tmux session named `claude-<folder>-<time>`. It goes through the switch-login wrapper when that's installed, so `/switch-login` works in the new chat.
- **Inherits permission flags** from the calling claude session: `--dangerously-skip-permissions` and `--permission-mode` are passed on only if this session has them. It never adds them.
- Answers the folder-trust prompt, because the user named the folder. It does not answer any other startup prompt. If one blocks startup, the script exits and prints `tmux attach -t <name>`, so the user can answer it.
- Starts claude with `--remote-control`, which is the same as typing `/rc`, and prints the session link.
- Opens a gnome-terminal window attached to the session when a desktop display is available.

## A fixed set of chats: `claudes`

`scripts/claudes.sh` opens a tmux session named `claude` with one window per chat from a machine-local list, by default `~/.config/claudes/windows` (`$CLAUDES_CONFIG` or the first argument overrides it). Each line is `NAME DIR COMMAND...`, for example `web ~/code/web claude --dangerously-skip-permissions` or `docs ~/code/docs claude2`. Each window runs COMMAND in the user's interactive shell (so shell functions like `claude2` work), continuing that folder's last chat (`--continue`; a fresh chat if there is none) with the same `<machine> - <project>` name and Remote Control on. It only creates missing windows, so it is safe to re-run, and then attaches. To run it as `claudes`, link it onto PATH: `ln -s ~/.claude/skills/new/scripts/claudes.sh ~/.local/bin/claudes`. Folders never go in this repo; they live in the local list.

## Requirements

`tmux`, `claude` on PATH, and Linux (`/proc`). The terminal window is optional. The second account needs the `switch-login` setup (`/setup-switch-login`).
