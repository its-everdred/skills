#!/usr/bin/env bash
set -euo pipefail

# Reopen a GitHub PR from your own account.
# Takes a PR URL, fetches the branch, cherry-picks all commits onto a new branch,
# pushes it, and opens a new PR with the original title and sanitized body.

usage() {
  echo "Usage: ./reopen.sh <pr-url> [target-repo] [--dry-run] [--title] [--target-issue N]"
  echo ""
  echo "  pr-url       Full GitHub PR URL (e.g. https://github.com/owner/repo/pull/123)"
  echo "  target-repo  Optional repo to open the new PR against, as 'owner/repo' or a full"
  echo "               URL (e.g. target-owner/target-repo). Defaults to the PR's own repo."
  echo "  --dry-run    Show what would happen without pushing or creating the PR"
  echo "  --title      Name the branch from the first 3 words of the PR title"
  echo "               (e.g. your-user/fix-validation-handling) instead of the PR number"
  echo "  --target-issue N"
  echo "               Prefix the branch with the target issue number and rewrite common"
  echo "               closing/reference issue links in the PR body to #N"
  exit 1
}

[[ $# -lt 1 ]] && usage
[[ "$1" == "-h" || "$1" == "--help" ]] && usage

PR_URL="$1"
shift
DRY_RUN=false
USE_TITLE=false
TARGET_ARG=""
TARGET_ISSUE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --title) USE_TITLE=true ;;
    --target-issue|--issue)
      shift
      if [[ $# -eq 0 || "$1" == --* ]]; then
        echo "Error: --target-issue requires a numeric issue number."
        usage
      fi
      TARGET_ISSUE="$1"
      ;;
    --target-issue=*|--issue=*)
      TARGET_ISSUE="${1#*=}"
      ;;
    -h|--help) usage ;;
    --*)
      echo "Error: unknown option: $1"
      usage
      ;;
    *)
      if [[ -n "$TARGET_ARG" ]]; then
        echo "Error: unexpected extra argument: $1"
        usage
      fi
      TARGET_ARG="$1"
      ;;
  esac
  shift
done

if [[ -n "$TARGET_ISSUE" && ! "$TARGET_ISSUE" =~ ^[0-9]+$ ]]; then
  echo "Error: --target-issue must be numeric."
  exit 1
fi

# Parse owner/repo and PR number from URL
if [[ "$PR_URL" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
  PR_NUMBER="${BASH_REMATCH[3]}"
else
  echo "Error: Could not parse PR URL: $PR_URL"
  usage
fi

FULL_REPO="$OWNER/$REPO"

# Determine the target repo to open the new PR against (defaults to the PR's own repo).
if [[ -n "$TARGET_ARG" ]]; then
  if [[ "$TARGET_ARG" =~ github\.com[:/]([^/]+)/([^/]+) ]]; then
    TARGET_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
  elif [[ "$TARGET_ARG" =~ ^([^/[:space:]]+)/([^/[:space:]]+)$ ]]; then
    TARGET_REPO="${TARGET_ARG%.git}"
  else
    echo "Error: Could not parse target repo: $TARGET_ARG"
    usage
  fi
else
  TARGET_REPO="$FULL_REPO"
fi

echo "==> Fetching PR #$PR_NUMBER from $FULL_REPO..."

# Get PR metadata
PR_JSON=$(gh pr view "$PR_NUMBER" --repo "$FULL_REPO" --json title,body,headRefName,baseRefName,labels,author)

TITLE=$(echo "$PR_JSON" | jq -r '.title')
BODY=$(echo "$PR_JSON" | jq -r '.body')
HEAD_REF=$(echo "$PR_JSON" | jq -r '.headRefName')
BASE_REF=$(echo "$PR_JSON" | jq -r '.baseRefName')
AUTHOR=$(echo "$PR_JSON" | jq -r '.author.login')
COMMITS=$(gh api --paginate "repos/$FULL_REPO/pulls/$PR_NUMBER/commits" --jq '.[].sha')
COMMIT_COUNT=$(printf '%s\n' "$COMMITS" | sed '/^$/d' | wc -l | tr -d ' ')

if [[ -z "$COMMITS" ]]; then
  echo "Error: No commits found in PR commit list."
  exit 1
fi

# Get current user
MY_USER=$(gh api user --jq '.login')

echo "    Title:    $TITLE"
echo "    Source:   $FULL_REPO"
echo "    Target:   $TARGET_REPO"
echo "    Author:   $AUTHOR"
echo "    Branch:   $HEAD_REF"
echo "    Base:     $BASE_REF"
echo "    Commits:  $COMMIT_COUNT"
echo "    Your user: $MY_USER"
if [[ -n "$TARGET_ISSUE" ]]; then
  echo "    Target issue: #$TARGET_ISSUE"
fi
echo ""

if [[ -n "$TARGET_ISSUE" ]]; then
  if ! gh issue view "$TARGET_ISSUE" --repo "$TARGET_REPO" >/dev/null 2>&1; then
    echo "Error: target issue #$TARGET_ISSUE was not found in $TARGET_REPO."
    exit 1
  fi
fi

# New branch name, prefix with your username to avoid collision. By default use
# only the last path segment of the source branch (e.g. "feature/fix" -> "your-user/fix").
# With --title, slugify the first 3 words of the PR title instead
# (e.g. "Fix validation handling..." -> "your-user/fix-validation-handling").
if $USE_TITLE; then
  SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//' | cut -d- -f1-3)
else
  SLUG=$(echo "${HEAD_REF##*/}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')
fi
if [[ -n "$TARGET_ISSUE" ]]; then
  SLUG="$TARGET_ISSUE-$SLUG"
fi
NEW_BRANCH="$MY_USER/$SLUG"
echo "==> New branch will be: $NEW_BRANCH"

PR_BODY="$BODY"
if [[ -n "$TARGET_ISSUE" ]]; then
  REWRITTEN_BODY=$(SOURCE_REPO="$FULL_REPO" TARGET_ISSUE="$TARGET_ISSUE" perl -0pe '
    my $repo = quotemeta($ENV{SOURCE_REPO});
    my $ref = qr/(?:#\d+|$repo\#\d+|https:\/\/github\.com\/$repo\/(?:issues|pull)\/\d+)/;
    s/\b(close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?|references)\s+$ref/$1 #$ENV{TARGET_ISSUE}/gi;
  ' <<< "$PR_BODY")
  if [[ "$REWRITTEN_BODY" == "$PR_BODY"$'\n' ]]; then
    PR_BODY="Refs #$TARGET_ISSUE"$'\n\n'"$PR_BODY"
  else
    PR_BODY="$REWRITTEN_BODY"
  fi
fi

PR_BODY=$(SOURCE_REPO="$FULL_REPO" SOURCE_PR="$PR_NUMBER" perl -0pe '
  my $repo = quotemeta($ENV{SOURCE_REPO});
  my $pr = quotemeta($ENV{SOURCE_PR});
  s{^[^\n]*(?:https://github\.com/$repo/pull/$pr|$repo\#$pr)[^\n]*\n?}{}gim;
  s{https://github\.com/$repo/pull/$pr\b}{}gi;
  s{\b$repo\#$pr\b}{}gi;
  s{\n{3,}}{\n\n}g;
  s{\A[ \t\n]+}{};
  s{[ \t\n]+\z}{\n};
' <<< "$PR_BODY")

# Check we're in a git repo that matches
CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || true)
if [[ -z "$CURRENT_REMOTE" ]]; then
  echo "Error: Not in a git repository, or no 'origin' remote."
  exit 1
fi

# Verify remote matches the target repo (loose check)
if ! echo "$CURRENT_REMOTE" | grep -qiF "$TARGET_REPO"; then
  echo "Warning: Current origin ($CURRENT_REMOTE) may not match target $TARGET_REPO"
  read -rp "Continue anyway? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

# Save current branch to return to on failure
ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Fetch the PR's commits from the repo where the PR lives, and main from origin
# (the repo we push to / open the PR against). These differ in cross-repo mode.
if [[ "$FULL_REPO" == "$TARGET_REPO" ]]; then
  PR_FETCH_FROM="origin"
else
  PR_FETCH_FROM="https://github.com/$FULL_REPO.git"
fi
echo "==> Fetching PR branch from $FULL_REPO and main from origin..."
git fetch "$PR_FETCH_FROM" "+pull/$PR_NUMBER/head:refs/heads/pr-$PR_NUMBER-temp" --no-tags
git fetch origin main --no-tags

# Replay only the commits GitHub reports as part of this PR. Do not derive a
# merge-base range from fork history, because the source fork's main branch may
# contain unrelated PRs that are not present in the target repository.
echo "==> Found $COMMIT_COUNT commit(s) to replay:"
for c in $COMMITS; do
  echo "    $(git log --oneline -1 "$c")"
done
echo ""

if $DRY_RUN; then
  echo "[DRY RUN] Would create branch '$NEW_BRANCH' from origin/main"
  echo "[DRY RUN] Would cherry-pick the above commits"
  if [[ -n "$TARGET_ISSUE" ]]; then
    echo "[DRY RUN] Would rewrite common PR body issue references to #$TARGET_ISSUE"
  fi
  echo "[DRY RUN] Would push branch to origin and open PR on $TARGET_REPO titled: $TITLE"
  git branch -D "pr-$PR_NUMBER-temp" 2>/dev/null
  exit 0
fi

# Create new branch from main (works regardless of current branch)
echo "==> Creating branch $NEW_BRANCH from origin/main..."
git checkout -B "$NEW_BRANCH" "origin/main"

# Cherry-pick each commit, re-committing as ourselves but keeping the original
# message and the original author/committer timestamps.
echo "==> Cherry-picking commits..."
for c in $COMMITS; do
  if ! git cherry-pick "$c" --allow-empty --no-commit; then
    echo "Error: Cherry-pick failed. Aborting..."
    git cherry-pick --abort 2>/dev/null
    git checkout "$ORIGINAL_BRANCH"
    git branch -D "$NEW_BRANCH" 2>/dev/null
    git branch -D "pr-$PR_NUMBER-temp" 2>/dev/null
    exit 1
  fi
  # Re-commit as ourselves, keeping the original message and original date.
  # --date sets the author date; GIT_COMMITTER_DATE sets the committer date.
  MSG=$(git log -1 --format='%s' "$c")
  BODY_MSG=$(git log -1 --format='%b' "$c")
  ORIG_DATE=$(git log -1 --format='%aI' "$c")
  if [[ -n "$BODY_MSG" ]]; then
    GIT_COMMITTER_DATE="$ORIG_DATE" git commit --allow-empty --date "$ORIG_DATE" -m "$MSG" -m "$BODY_MSG"
  else
    GIT_COMMITTER_DATE="$ORIG_DATE" git commit --allow-empty --date "$ORIG_DATE" -m "$MSG"
  fi
done

# Push
echo "==> Pushing $NEW_BRANCH to origin..."
git push -u origin "$NEW_BRANCH"

# Create the PR
echo "==> Opening PR..."
NEW_PR_URL=$(gh pr create \
  --repo "$TARGET_REPO" \
  --head "$NEW_BRANCH" \
  --base "main" \
  --title "$TITLE" \
  --body "$PR_BODY" \
  --draft)

echo ""
echo "✅ New PR: $NEW_PR_URL"

# Cleanup temp branch
git branch -D "pr-$PR_NUMBER-temp" 2>/dev/null

echo "==> You are now on branch: $NEW_BRANCH"
