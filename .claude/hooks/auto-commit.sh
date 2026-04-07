#!/bin/bash
# Auto-commit hook for vault changes
# Called after Write/Edit operations on vault files

VAULT_PATH="${VAULT_PATH:-$(pwd)}"
MODIFIED_FILE="${1:-unknown}"

# Only run if auto-commit is enabled
if [ "${GIT_AUTO_COMMIT}" != "true" ]; then
    exit 0
fi

cd "$VAULT_PATH" || exit 0

# Check if this is a git repository
if [ ! -d .git ]; then
    exit 0
fi

# Check if there are changes to commit (tracked modifications, staged changes, or new untracked files)
if [ -z "$(git status --porcelain)" ]; then
    exit 0
fi

# Generate commit message based on file location
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")

DAILY_DIR="${DAILY_NOTES_DIR:-Daily Notes}"
GOALS_DIR_NAME="${GOALS_DIR:-Goals}"
PROJECTS_DIR_NAME="${PROJECTS_DIR:-Projects}"
TEMPLATES_DIR_NAME="${TEMPLATES_DIR:-Templates}"

if [[ "$MODIFIED_FILE" == *"$DAILY_DIR"* ]]; then
    MSG="Update daily note - $TIMESTAMP"
elif [[ "$MODIFIED_FILE" == *"$GOALS_DIR_NAME"* ]]; then
    MSG="Update goals - $TIMESTAMP"
elif [[ "$MODIFIED_FILE" == *"$PROJECTS_DIR_NAME"* ]]; then
    PROJECT=$(echo "$MODIFIED_FILE" | sed "s|.*/$PROJECTS_DIR_NAME/\([^/]*\)/.*|\1|")
    MSG="Update project: $PROJECT - $TIMESTAMP"
elif [[ "$MODIFIED_FILE" == *"$TEMPLATES_DIR_NAME"* ]]; then
    MSG="Update template - $TIMESTAMP"
else
    MSG="Vault update - $TIMESTAMP"
fi

# Stage and commit
git add .
git commit -m "$MSG" --quiet 2>/dev/null

if [ $? -eq 0 ]; then
    echo "Auto-committed: $MSG"
fi
