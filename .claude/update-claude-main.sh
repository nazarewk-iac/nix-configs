#!/usr/bin/env bash
# Helper script to update CLAUDE.md on main branch
# Can be executed from any branch without checking out main

set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 <commit-message>

Updates CLAUDE.md on the main branch without checking out the branch.

Example:
    $0 "docs: update CLAUDE.md guidance"

The updated CLAUDE.md must already exist at /tmp/CLAUDE.md.new before running.
EOF
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

COMMIT_MSG="$1"
TMP_FILE="/tmp/CLAUDE.md.new"

if [ ! -f "$TMP_FILE" ]; then
    echo "Error: $TMP_FILE does not exist"
    echo "Please create the file first with your changes"
    exit 1
fi

echo "Updating CLAUDE.md on main branch..."

# Create blob for new file content
BLOB=$(git hash-object -w "$TMP_FILE")
echo "Created blob: $BLOB"

# Get current main state
PARENT_COMMIT=$(git rev-parse main)
CURRENT_TREE=$(git cat-file -p "$PARENT_COMMIT" | grep '^tree' | cut -d' ' -f2)
echo "Parent commit: $PARENT_COMMIT"

# Create new tree with updated CLAUDE.md
NEW_TREE=$(git mktree <<EOF
$(git ls-tree "$CURRENT_TREE" | grep -v "CLAUDE.md")
100644 blob $BLOB	CLAUDE.md
EOF
)
echo "New root tree: $NEW_TREE"

# Create commit
NEW_COMMIT=$(git commit-tree "$NEW_TREE" -p "$PARENT_COMMIT" -m "$COMMIT_MSG")
echo "New commit: $NEW_COMMIT"

# Update main branch
git update-ref refs/heads/main "$NEW_COMMIT"

echo "✓ Successfully updated CLAUDE.md on main branch"
echo "Current branch: $(git branch --show-current)"
git log main --oneline -3
