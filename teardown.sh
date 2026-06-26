#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="gitops-demo"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    echo "Deleting kind cluster '$CLUSTER_NAME'..."
    kind delete cluster --name "$CLUSTER_NAME"
    echo "Done. Nothing else was touched on your machine -- the cluster"
    echo "and everything in it lived entirely inside that one kind cluster."
else
    echo "No cluster named '$CLUSTER_NAME' found -- nothing to do."
fi
