#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils.sh
source "$SCRIPT_DIR/../utils.sh"

set -e

CLUSTERS=("ramen-dr1" "ramen-dr2")
NAMESPACE="rook-ceph"

for CONTEXT in "${CLUSTERS[@]}"; do
    log_info "🚀 Setting up Rook Ceph storage in minikube context: $CONTEXT"

    # 1. Ensure rook-ceph namespace exists
    ensure_namespace "$CONTEXT" "$NAMESPACE"

    # 2. Apply Rook CRDs and common resources
    apply_url_safe "$CONTEXT" "https://raw.githubusercontent.com/rook/rook/v1.13.3/deploy/examples/crds.yaml" "Rook CRDs"
    apply_url_safe "$CONTEXT" "https://raw.githubusercontent.com/rook/rook/v1.13.3/deploy/examples/common.yaml" "Rook common resources"

    # 3. Deploy Rook operator
    log_long_operation "Deploying Rook Ceph operator" "2-3 minutes"
    apply_url_safe "$CONTEXT" "https://raw.githubusercontent.com/rook/rook/v1.13.3/deploy/examples/operator.yaml" "Rook Ceph operator"

    # 4. Deploy Ceph cluster using useAllDevices: true, but only if not already present and ready
    if kubectl --context="$CONTEXT" -n rook-ceph get cephcluster rook-ceph &>/dev/null; then
        PHASE=$(kubectl --context="$CONTEXT" -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.phase}')
        if [[ "$PHASE" == "Ready" ]]; then
            log_success "Ceph cluster in $CONTEXT is already ready!"
        else
            log_info "Ceph cluster in $CONTEXT exists but is not ready (phase: $PHASE)."
        fi
    else
        # Use pre-validated Ceph cluster YAML file 
        CEPH_CLUSTER_FILE="$SCRIPT_DIR/../../yaml/storage-demos/ceph-cluster-simple.yaml"
        log_step "Using validated Ceph cluster configuration..."
        
        if [[ ! -f "$CEPH_CLUSTER_FILE" ]]; then
            log_error "Pre-validated Ceph cluster file not found: $CEPH_CLUSTER_FILE"
            return 1
        fi
        
        log_step "Deploying Ceph cluster using validated configuration..."
        apply_with_webhook_retry "$CONTEXT" "$CEPH_CLUSTER_FILE" "Ceph cluster" 5 15
        log_success "Ceph cluster resource applied in $CONTEXT."
    fi

    # 5. Wait for Ceph cluster to be ready if not already
    PHASE=$(kubectl --context="$CONTEXT" -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [[ "$PHASE" != "Ready" ]]; then
        log_long_operation "Waiting for Ceph cluster to be ready in $CONTEXT" "5-15 minutes"
        if kubectl --context="$CONTEXT" -n rook-ceph wait --for=condition=Ready cephcluster rook-ceph --timeout=900s; then
            log_success "Ceph cluster is ready in $CONTEXT!"
        else
            log_warning "Timed out waiting for Ceph cluster to be ready in $CONTEXT. Please check the cluster status."
            log_info "Debug information:"
            kubectl --context="$CONTEXT" -n rook-ceph get cephcluster rook-ceph -o wide
            kubectl --context="$CONTEXT" -n rook-ceph get pods | head -10
        fi
    else
        log_success "Ceph cluster is ready in $CONTEXT!"
    fi

    # 6. Deploy Ceph toolbox for troubleshooting
    apply_url_safe "$CONTEXT" "https://raw.githubusercontent.com/rook/rook/v1.13.3/deploy/examples/toolbox.yaml" "Ceph toolbox"

    # 7. Apply storage classes for RamenDR demos
    STORAGE_CLASSES_FILE="$SCRIPT_DIR/../../yaml/storage-demos/rook-ceph-storage-classes.yaml"
    if [[ -f "$STORAGE_CLASSES_FILE" ]]; then
        log_step "Deploying RamenDR storage classes..."
        if kubectl --context="$CONTEXT" apply -f "$STORAGE_CLASSES_FILE"; then
            log_success "RamenDR storage classes deployed in $CONTEXT"
        else
            log_warning "Failed to deploy storage classes (may already exist)"
        fi
    else
        log_info "Storage classes file not found, using Rook defaults"
    fi

    # 8. Wait for Ceph file system to be ready (for CephFS storage class)
    log_step "Checking for Ceph file system..."
    if ! kubectl --context="$CONTEXT" -n rook-ceph get cephfilesystem myfs >/dev/null 2>&1; then
        log_step "Creating Ceph file system for CephFS storage..."
        CEPH_FS_FILE="$SCRIPT_DIR/../../yaml/storage-demos/ceph-filesystem.yaml"
        apply_yaml_with_timeout_warning "$CONTEXT" "$CEPH_FS_FILE" "Ceph file system" "3-5 minutes"
        
        # Use the improved CephFS wait function with better error handling
        if wait_for_cephfs "$CONTEXT" "myfs" "rook-ceph" 600; then
            log_success "Ceph file system is ready!"
        else
            log_warning "Ceph file system setup timed out or failed"
            log_info "This might be due to:"
            log_info "  - Insufficient OSDs (check: kubectl --context=$CONTEXT -n rook-ceph exec deploy/rook-ceph-tools -- ceph status)"
            log_info "  - MDS pods not starting (check: kubectl --context=$CONTEXT -n rook-ceph get pods -l app=rook-ceph-mds)"
            log_info "  - Storage issues in minikube"
            log_info "You can check the status later with: kubectl --context=$CONTEXT -n rook-ceph get cephfilesystem myfs"
            log_warning "Continuing without CephFS - block storage will still work"
        fi
    else
        log_success "Ceph file system already exists"
        # Check if it's ready
        fs_phase=$(kubectl --context="$CONTEXT" -n rook-ceph get cephfilesystem myfs -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [[ "$fs_phase" != "Ready" ]]; then
            log_info "Existing CephFS is not ready yet (phase: $fs_phase), waiting..."
            wait_for_cephfs "$CONTEXT" "myfs" "rook-ceph" 300
        else
            log_success "Existing CephFS is ready!"
        fi
    fi

    log_info "✅ Rook Ceph storage setup complete in $CONTEXT. You can now use Ceph for SAN/VSAN testing."
    log_info "Available storage classes:"
    kubectl --context="$CONTEXT" get storageclass | grep rook || true
    echo "-------------------------------------------------------------"
done