# switch-login

Run two Claude Code accounts on one machine and move a live session between them.

- `claude` runs the default account (`~/.claude`).
- `claude2` runs a second account from its own profile directory.
- `/switch-login` restarts the current session in the same pane on the other
  account, with the conversation resumed. Other panes are not affected.

Both profiles share settings, skills, plugins, project memory and transcripts.
Each keeps its own credentials. Shell: zsh.

## Setup

### 1. Create the second profile

```sh
P="$HOME/.claude-2"          # any directory; this is the second profile
mkdir -p "$P"
for f in CLAUDE.md settings.json skills plugins projects todos \
         file-history history.jsonl session-env shell-snapshots; do
  ln -s "$HOME/.claude/$f" "$P/$f"
done
CLAUDE_CONFIG_DIR="$P" claude   # then run /login with the second account
```

Do not link `.credentials.json`, `.claude.json` or `sessions/`: they stay private
to each profile. `projects` must be linked, or a switched session cannot find
its transcript.

### 2. Install the skill and the shell wrapper

```sh
cp -r switch-login ~/.claude/skills/
```

Add to `~/.zshrc`, then open a new shell:

```sh
export CLAUDE_LOGIN2_DIR="$HOME/.claude-2"
source "$HOME/.claude/skills/switch-login/claude-login.zsh"
```

### 3. Check

- `type claude` prints "shell function".
- `claude2`, then `/status`, shows the second account.
- In a `claude` session, send one message and run `/switch-login`. The pane
  prints `switch-login: resuming on the second account` and the conversation
  continues.

## How it works

A running session cannot change account by itself: every session of a profile
reads the same credentials file. So `scripts/switch.sh` writes the session id
to the file named in `$CLAUDE_SWITCH_FILE` and stops the current `claude`
process. The `claude` shell function (`claude-login.zsh`) sees that file and
starts `claude --resume <id>` under the other profile, with the flags the
session was started with.

A session that was started before the wrapper was loaded has no
`$CLAUDE_SWITCH_FILE`. The skill then prints the command to run by hand.

## Limits

- zsh only.
- Two accounts only.
- `scripts/switch.sh` stops the session through `$CLAUDE_PID`, which Claude Code sets in the session environment.
