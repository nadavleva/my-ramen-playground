#!/bin/bash
# cleanup-ocm.sh - Clean up OCM setup to allow fresh re-run of set-ocm-using-clustadmin.sh

set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

HUB_CONTEXT="ramen-hub"
DR_CONTEXTS=("ramen-dr1" "ramen-dr2")

log_step "🧹 Cleaning up OCM setup for fresh re-run..."

# 1. Remove ManagedClusters from hub using utils for finalizer handling
log_info "Removing ManagedClusters from hub..."
for ctx in "${DR_CONTEXTS[@]}"; do
    log_info "Removing ManagedCluster: $ctx"
    safe_delete_with_finalizers "$HUB_CONTEXT" "managedcluster" "$ctx" ""
done

# 2. Remove klusterlets from DR clusters using utils for finalizer handling
log_info "Removing klusterlets from DR clusters..."
for ctx in "${DR_CONTEXTS[@]}"; do
    log_info "Cleaning up klusterlet on $ctx..."
    safe_delete_with_finalizers "$ctx" "klusterlet" "klusterlet" ""
done

# 3. Clean up agent namespaces using utils
log_info "Cleaning up agent namespaces..."
for ctx in "${DR_CONTEXTS[@]}"; do
    log_info "Removing agent namespace on $ctx..."
    safe_delete "$ctx" "namespace" "open-cluster-management-agent" ""
done

# 4. Remove CSRs related to our clusters
log_info "Removing cluster-related CSRs..."
for ctx in "${DR_CONTEXTS[@]}"; do
    # Delete CSRs that contain the cluster name
    CSRS=$(kubectl --context=$HUB_CONTEXT get csr --no-headers 2>/dev/null | awk '$1 ~ /'"$ctx"'/ {print $1}' || echo "")
    if [ -n "$CSRS" ]; then
        for csr in $CSRS; do
            log_info "Removing CSR: $csr"
            kubectl --context=$HUB_CONTEXT delete csr "$csr" --ignore-not-found=true || log_warning "Failed to delete CSR $csr"
        done
    fi
done

# 5. Clean up ManagedClusterSetBindings using utils
log_info "Cleaning up ManagedClusterSetBindings..."
safe_delete "$HUB_CONTEXT" "managedclustersetbinding" "--all" "nginx-test"
safe_delete "$HUB_CONTEXT" "managedclustersetbinding" "--all" "ramen-system"

# 6. Wait for cleanup to complete
log_info "Waiting for cleanup to complete..."
sleep 5

# 7. Verify cleanup
log_info "🔍 Verifying cleanup..."

echo ""
log_info "ManagedClusters remaining:"
REMAINING_MC=$(kubectl --context=$HUB_CONTEXT get managedcluster --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$REMAINING_MC" -eq 0 ]; then
    log_success "✅ No ManagedClusters remaining"
else
    log_warning "⚠️  $REMAINING_MC ManagedClusters still exist"
    kubectl --context=$HUB_CONTEXT get managedcluster
fi

echo ""
log_info "Klusterlets remaining:"
for ctx in "${DR_CONTEXTS[@]}"; do
    REMAINING_KL=$(kubectl --context=$ctx get klusterlet --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$REMAINING_KL" -eq 0 ]; then
        log_success "✅ No klusterlets on $ctx"
    else
        log_warning "⚠️  $REMAINING_KL klusterlets still exist on $ctx"
        kubectl --context=$ctx get klusterlet
    fi
done

echo ""
log_info "Cluster-related CSRs remaining:"
REMAINING_CSRS=0
for ctx in "${DR_CONTEXTS[@]}"; do
    CSR_COUNT=$(kubectl --context=$HUB_CONTEXT get csr --no-headers 2>/dev/null | awk '$1 ~ /'"$ctx"'/' | wc -l || echo "0")
    REMAINING_CSRS=$((REMAINING_CSRS + CSR_COUNT))
done

if [ "$REMAINING_CSRS" -eq 0 ]; then
    log_success "✅ No cluster-related CSRs remaining"
else
    log_warning "⚠️  $REMAINING_CSRS cluster-related CSRs still exist"
    kubectl --context=$HUB_CONTEXT get csr | grep -E "(ramen-dr1|ramen-dr2)" || echo "   (No matches found)"
fi

echo ""
log_info "Hub cluster manager status:"
if kubectl --context=$HUB_CONTEXT get clustermanager >/dev/null 2>&1; then
    log_success "✅ ClusterManager still running (this is expected)"
    kubectl --context=$HUB_CONTEXT get clustermanager --no-headers
else
    log_warning "⚠️  ClusterManager not found"
fi

echo ""
if [ "$REMAINING_MC" -eq 0 ] && [ "$REMAINING_CSRS" -eq 0 ]; then
    log_success "🎉 OCM cleanup completed successfully!"
    log_info "You can now re-run: ./demo/scripts/set-ocm-using-clustadmin.sh"
else
    log_warning "⚠️  Cleanup completed with some remaining resources"
    log_info "You may still be able to re-run the OCM setup script"
fi

echo ""
log_info "💡 Note: The ClusterManager on the hub is intentionally left running"
log_info "   If you need to completely reset OCM, run:"
log_info "   kubectl --context=$HUB_CONTEXT delete clustermanager --all"
