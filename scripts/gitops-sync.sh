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
if ! task configure --yes; then
    echo "[gitops-sync] 'task configure' failed – attempting legacy 'configure' target..."
    task configure --yes
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

# Optional post-checks and helpers
echo "[gitops-sync] Post-check: Flux Kustomizations and HelmReleases"
flux get ks -A || true
flux get hr -A || true

# Optional rollout restart to force init containers to re-run (e.g., copy ConfigMap to PVC)
# Set GITOPS_ROLLOUT="<namespace>/<deployment>" to enable
if [[ -n "${GITOPS_ROLLOUT:-}" ]]; then
  ns="${GITOPS_ROLLOUT%/*}"
  dep="${GITOPS_ROLLOUT#*/}"
  if [[ -n "$ns" && -n "$dep" && "$ns" != "$dep" ]]; then
    echo "[gitops-sync] Performing rollout restart: namespace=$ns, deployment=$dep"
    kubectl -n "$ns" rollout restart deploy "$dep" || true
  else
    echo "[gitops-sync] Warning: GITOPS_ROLLOUT must be in 'namespace/deployment' format"
  fi
fi

# Optional short watch for a label selector in a namespace
# Set GITOPS_WATCH_NS and GITOPS_WATCH_LABEL (and optionally GITOPS_WATCH_SECONDS)
if [[ -n "${GITOPS_WATCH_NS:-}" && -n "${GITOPS_WATCH_LABEL:-}" ]]; then
  secs="${GITOPS_WATCH_SECONDS:-0}"
  echo "[gitops-sync] Watching pods in $GITOPS_WATCH_NS matching '$GITOPS_WATCH_LABEL' ${secs:+for $secs seconds}..."
  if [[ "$secs" -gt 0 ]] 2>/dev/null; then
    # Run watch for a bounded time
    timeout "$secs" kubectl -n "$GITOPS_WATCH_NS" get pods -l "$GITOPS_WATCH_LABEL" -w || true
  else
    kubectl -n "$GITOPS_WATCH_NS" get pods -l "$GITOPS_WATCH_LABEL" || true
  fi
fi
