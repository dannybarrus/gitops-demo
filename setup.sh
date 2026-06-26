#!/usr/bin/env bash
#
# Usage: ./setup.sh <your-github-repo-url>
#
# Example: ./setup.sh https://github.com/yourname/gitops-demo.git
#
# Spins up a local kind cluster, installs ArgoCD, and points it at
# your own GitHub repo. Safe to re-run -- every step checks whether
# its work is already done before doing it again.

set -euo pipefail

CLUSTER_NAME="gitops-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <your-github-repo-url>"
    echo "Example: $0 https://github.com/yourname/gitops-demo.git"
    exit 1
fi
REPO_URL="$1"

echo "=== Checking prerequisites ==="
for tool in docker kind kubectl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: '$tool' is not installed or not on your PATH."
        echo "  docker: https://docs.docker.com/get-docker/"
        echo "  kind:   https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
        echo "  kubectl: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
done
echo "  docker, kind, kubectl all found."

echo ""
echo "=== Creating kind cluster (if it doesn't already exist) ==="
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    echo "  Cluster '$CLUSTER_NAME' already exists -- skipping creation."
else
    kind create cluster --name "$CLUSTER_NAME" --config "$SCRIPT_DIR/kind/cluster-config.yaml"
fi
kubectl cluster-info --context "kind-$CLUSTER_NAME" >/dev/null

echo ""
echo "=== Installing ArgoCD (if not already installed) ==="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# --server-side --force-conflicts, not a plain apply: ArgoCD's CRDs
# (applicationsets.argoproj.io especially) are large enough that a
# normal client-side apply tries to store the whole manifest in the
# object's own last-applied-configuration annotation -- and that
# pushes the object past Kubernetes' hard 262144-byte annotation
# limit, failing with "metadata.annotations: Too long." Server-side
# apply doesn't use that annotation at all, so the size problem never
# comes up. --force-conflicts is needed alongside it on a fresh
# install because client-side apply isn't involved yet to "own" any
# fields for server-side apply to otherwise conflict with.
kubectl apply -n argocd --server-side --force-conflicts \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo ""
echo "=== Waiting for ArgoCD pods to become ready (this can take a couple of minutes) ==="
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

echo ""
echo "=== Pointing ArgoCD at your repo ==="
sed "s|__REPO_URL__|${REPO_URL}|g" "$SCRIPT_DIR/argocd/hello-world-application.template.yaml" \
    > /tmp/hello-world-application.generated.yaml
kubectl apply -f /tmp/hello-world-application.generated.yaml

echo ""
echo "=== Waiting for the initial sync ==="
for i in $(seq 1 30); do
    STATUS=$(kubectl get application hello-world -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
    if [ "$STATUS" = "Synced" ]; then
        echo "  Synced."
        break
    fi
    sleep 5
done

echo ""
echo "=== Current status ==="
kubectl get application hello-world -n argocd

echo ""
echo "=== ArgoCD admin password (only shown on first install) ==="
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null \
    | base64 -d \
    && echo "" \
    || echo "  (already retrieved in a previous run, or password already changed)"

cat <<'EOF'

=== Done ===

View the demo app:
  http://localhost:30080

View the ArgoCD UI (run this in a separate terminal, then leave it running):
  kubectl port-forward svc/argocd-server -n argocd 8080:443
  then open: https://localhost:8080   (login: admin / the password printed above)
  (your browser will warn about a self-signed cert -- that's ArgoCD's own
  default cert for itself, not a problem; "Advanced > Proceed" is fine.)

See README.md for the actual walkthrough: making a change through Git,
and the drift/self-heal demonstration.

To tear everything down when you're done:
  ./teardown.sh
EOF
