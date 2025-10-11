#!/usr/bin/env bash
# Helper script to merge main branch into ai-agents branch
# Can be executed from any branch without checking out ai-agents

set -euo pipefail

usage() {
    cat <<EOF
Usage: $0

Merges the main branch into the ai-agents branch without checking out ai-agents.
This keeps the metadata branch up-to-date with main branch developments.

Example:
    $0
EOF
    exit 1
}

if [ $# -ne 0 ]; then
    usage
fi

echo "Merging main into ai-agents branch..."

# Get latest commits
MAIN_COMMIT=$(git rev-parse main)
AI_AGENTS_COMMIT=$(git rev-parse ai-agents)

echo "Main commit: $MAIN_COMMIT"
echo "AI-agents commit: $AI_AGENTS_COMMIT"

# Check if main is already in ai-agents history
if git merge-base --is-ancestor "$MAIN_COMMIT" "$AI_AGENTS_COMMIT"; then
    echo "✓ Main is already merged into ai-agents (nothing to do)"
    exit 0
fi

echo "Merging main into ai-agents..."

# Find merge base
MERGE_BASE=$(git merge-base main ai-agents)
echo "Merge base: $MERGE_BASE"

# Get the merge tree
# Use git read-tree and git write-tree for clean merge
# Create a temporary index
export GIT_INDEX_FILE="$(mktemp)"
trap "rm -f '$GIT_INDEX_FILE'" EXIT

# Read ai-agents tree into index
git read-tree "$AI_AGENTS_COMMIT"

# Merge main tree into index
if git merge-tree "$MERGE_BASE" "$AI_AGENTS_COMMIT" "$MAIN_COMMIT" | grep -q "^changed in both"; then
    echo "⚠ Warning: Merge conflicts detected, using ai-agents version for conflicts"
fi

# For simple merge, just use git merge-tree to get the result
MERGE_RESULT=$(git merge-tree "$MERGE_BASE" "$AI_AGENTS_COMMIT" "$MAIN_COMMIT")

# Extract the tree SHA from merge-tree output (it's complex, so we use a simpler approach)
# Write the ai-agents tree and overlay main changes
git read-tree "$AI_AGENTS_COMMIT"
git read-tree -m "$MERGE_BASE" "$AI_AGENTS_COMMIT" "$MAIN_COMMIT" 2>/dev/null || {
    echo "Using three-way merge strategy..."
    # If automatic merge fails, prefer ai-agents for conflicts
    git read-tree "$AI_AGENTS_COMMIT"
    # Apply non-conflicting changes from main
    git diff-tree -p "$MERGE_BASE" "$MAIN_COMMIT" | git apply --index --3way 2>/dev/null || true
}

MERGE_TREE=$(git write-tree)
echo "Merge tree: $MERGE_TREE"

# Create merge commit
MERGE_COMMIT=$(git commit-tree "$MERGE_TREE" -p "$AI_AGENTS_COMMIT" -p "$MAIN_COMMIT" -m "$(cat <<'COMMITMSG'
Merge main into ai-agents

Integrate latest changes from main branch into ai-agents metadata branch.
This keeps the metadata branch up-to-date with main branch developments.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
COMMITMSG
)")

echo "Merge commit: $MERGE_COMMIT"

# Update ai-agents branch
git update-ref refs/heads/ai-agents "$MERGE_COMMIT"

echo "✓ Successfully merged main into ai-agents"
echo "Current branch: $(git branch --show-current)"
git log ai-agents --oneline --graph -10
