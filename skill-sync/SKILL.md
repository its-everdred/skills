---
name: skill-sync
description: Use when the user asks to set up, run, or debug syncing of their skills repo (~/github/skills) into Claude Code, Codex and ~/.agents/skills, or says a skill added to the repo isn't showing up on this machine. Pulls the repo, links every skill into ~/.claude/skills, ~/.codex/skills and ~/.agents/skills, and installs the pinned `shared` skills from external-skills.json; a SessionStart hook does this automatically in every new chat.
---

# Skill sync

Every skill in this repo is linked into `~/.claude/skills/<name>`, `~/.codex/skills/<name>` and `~/.agents/skills/<name>`, so adding a skill to the repo and pushing it makes it available on every machine that has this set up.

## How it runs

- `scripts/session-start.sh` is a SessionStart hook in both Claude Code and Codex. On every new chat it runs `scripts/sync.sh`, then passes the chat any skill changes and the open items in `~/remind.md` (see the `remind` skill).
- `scripts/sync.sh` pulls fast-forward only, and only when the checkout is a clean `main` (8-second cap via python3, so offline and macOS without `timeout` are fine). Then it links missing skills and removes links to skills deleted from the repo. It never replaces a real directory: a skill installed some other way under the same name wins.
- `sync.sh` then runs `sync-external.sh --shared-only`: pinned third-party skills from the manifest's `shared` section are copied into `~/.agents/skills` (never overwriting a differing one) and linked into `~/.claude/skills`. Conflicts and failures are printed as `shared: ...`.
- A skill linked during a chat is available from the next chat.

## Set up a machine (once)

```
git clone git@github.com:its-everdred/skills.git ~/github/skills
~/github/skills/skill-sync/scripts/install.sh
```

The installer adds the hook to `~/.claude/settings.json` and `~/.codex/hooks.json` (each backed up to `.bak` first), and runs a first sync. Running it again changes nothing. Codex may ask once to trust the new hook.

## When asked to sync now

Run `~/github/skills/skill-sync/scripts/sync.sh` and report what it printed (silence means nothing changed). If a skill doesn't link, check for a real directory with the same name in the target. Don't delete it without asking.
