#!/usr/bin/env bash
# Quick helper to render manifests, commit, push, and trigger Flux reconciliation.
#
# Usage:
#   ./scripts/gitops-sync.sh "feat(openhands): update LiteLLM secret"
#
# The script executes:
#   1) task configure   – renders & validates manifests/secrets
#   2) git add templates kubernetes
#   3) git commit -m "<message>"
#   4) git push
#   5) task reconcile           – forces Flux to sync
#
# If there are no staged changes after rendering, the commit/push step is skipped.
# -----------------------------------------------------------------------------
set -euo pipefail

# Ensure we always operate from the repository root (script may be called from anywhere).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

if [[ $# -lt 1 ]]; then
    echo "Error: commit message required." >&2
    echo "Usage: $0 \"<commit message>\"" >&2
    exit 1
fi
COMMIT_MSG="$*"

echo "[gitops-sync] Rendering manifests via Taskfile..."
# Render manifests & encrypt secrets (defined in Taskfile)
if ! task configure; then
    echo "[gitops-sync] 'task configure' failed – attempting legacy 'configure' target..."
    task configure
fi

echo "[gitops-sync] Staging generated files..."
# Add key generated paths (update paths as needed)
git add templates kubernetes || true

# Only commit if there are changes
if [[ -n "$(git status --porcelain)" ]]; then
    echo "[gitops-sync] Committing & pushing changes..."
    git commit -m "$COMMIT_MSG"
    git push
else
    echo "[gitops-sync] No changes to commit. Skipping git commit/push."
fi

echo "[gitops-sync] Triggering Flux reconciliation..."
task reconcile

echo "[gitops-sync] Done."
