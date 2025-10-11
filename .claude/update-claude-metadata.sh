#!/usr/bin/env bash
# Helper script to update files in .claude/ directory on ai-agents branch
# Can be executed from any branch without checking out ai-agents

set -euo pipefail

TMP_DIR="/tmp/kdn/nix-configs"

usage() {
    cat <<EOF
Usage: $0 <file-in-claude-dir> <commit-message>

Updates a file in the .claude/ directory on the ai-agents branch
without checking out the branch.

Example:
    $0 analysis-summary.md "docs(claude): update analysis summary"

The file path should be relative to .claude/ directory.
The file must already exist in $TMP_DIR/<filename>.new before running.
EOF
    exit 1
}

if [ $# -ne 2 ]; then
    usage
fi

FILE_IN_CLAUDE="$1"
COMMIT_MSG="$2"
TMP_FILE="$TMP_DIR/${FILE_IN_CLAUDE##*/}.new"

if [ ! -f "$TMP_FILE" ]; then
    echo "Error: $TMP_FILE does not exist"
    echo "Please create the file first with your changes"
    exit 1
fi

echo "Updating .claude/$FILE_IN_CLAUDE on ai-agents branch..."

# Create blob for new file content
BLOB=$(git hash-object -w "$TMP_FILE")
echo "Created blob: $BLOB"

# Get current ai-agents state
PARENT_COMMIT=$(git rev-parse ai-agents)
CURRENT_TREE=$(git cat-file -p "$PARENT_COMMIT" | grep '^tree' | cut -d' ' -f2)
echo "Parent commit: $PARENT_COMMIT"

# Get .claude directory tree
CLAUDE_DIR_SHA=$(git ls-tree "$CURRENT_TREE" | grep ".claude" | awk '{print $3}')
echo "Current .claude tree: $CLAUDE_DIR_SHA"

# Create new .claude tree with updated file
NEW_CLAUDE_TREE=$(git mktree <<EOF
$(git ls-tree "$CLAUDE_DIR_SHA" | grep -v "$FILE_IN_CLAUDE")
100644 blob $BLOB	$FILE_IN_CLAUDE
EOF
)
echo "New .claude tree: $NEW_CLAUDE_TREE"

# Create new root tree with updated .claude
NEW_TREE=$(git mktree <<EOF
$(git ls-tree "$CURRENT_TREE" | grep -v ".claude")
040000 tree $NEW_CLAUDE_TREE	.claude
EOF
)
echo "New root tree: $NEW_TREE"

# Create commit
NEW_COMMIT=$(git commit-tree "$NEW_TREE" -p "$PARENT_COMMIT" -m "$COMMIT_MSG")
echo "New commit: $NEW_COMMIT"

# Update ai-agents branch
git update-ref refs/heads/ai-agents "$NEW_COMMIT"

echo "✓ Successfully updated .claude/$FILE_IN_CLAUDE on ai-agents branch"
echo "Current branch: $(git branch --show-current)"
git log ai-agents --oneline -3
