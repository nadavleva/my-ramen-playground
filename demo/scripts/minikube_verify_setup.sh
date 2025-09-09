#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

# Verify Minikube profiles
verify_minikube_contexts

# Check cluster-manager placement
check_cluster_manager_placement

# Verify ManagedCluster status
kubectl --context=ramen-hub get managedcluster -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[?\(@.type==\"Available\"\)].status

# Check for stray DRPolicy on DR clusters
for ctx in ramen-dr1 ramen-dr2; do
    if kubectl --context=$ctx get drpolicy &>/dev/null; then
        log_error "Found DRPolicy on $ctx - should only be on hub"
        exit 1
    fi
done