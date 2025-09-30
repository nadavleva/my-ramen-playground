#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Comprehensive Storage Demo Script for RamenDR
# This script demonstrates all storage scenarios: Block (SAN), File (VSAN), and Object (S3)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils.sh
source "$SCRIPT_DIR/../utils.sh"

set -e

# Configuration
DEMO_YAML_DIR="$SCRIPT_DIR/../../yaml/storage-demos"
CONTEXTS=("ramen-dr1" "ramen-dr2")
DEMO_TYPES=("block-storage" "file-storage" "object-storage")

# Display usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [DEMO_TYPE]

Run comprehensive storage demos for RamenDR with Rook Ceph

DEMO_TYPE options:
  block     - Run Block Storage (SAN) demo only
  file      - Run File Storage (VSAN) demo only  
  object    - Run Object Storage (S3) demo only
  all       - Run all storage demos (default)
  cleanup   - Clean up all storage demos
  test      - Run storage tests only

OPTIONS:
  -h, --help              Show this help message
  -c, --context CONTEXT   Run demo on specific context only (ramen-dr1 or ramen-dr2)
  -s, --skip-setup        Skip initial setup verification
  -v, --verbose           Verbose output
  -w, --wait              Wait for user confirmation between steps

Examples:
  $0                      # Run all storage demos
  $0 block                # Run only block storage demo
  $0 -c ramen-dr1 file    # Run file storage demo on ramen-dr1 only
  $0 cleanup              # Clean up all demos
  $0 test                 # Run storage tests
EOF
}

# Parse command line arguments
SKIP_SETUP=false
VERBOSE=false
WAIT_FOR_USER=false
SPECIFIC_CONTEXT=""
DEMO_TYPE="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -c|--context)
            SPECIFIC_CONTEXT="$2"
            shift 2
            ;;
        -s|--skip-setup)
            SKIP_SETUP=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -w|--wait)
            WAIT_FOR_USER=true
            shift
            ;;
        block|file|object|all|cleanup|test)
            DEMO_TYPE="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Adjust contexts if specific context requested
if [[ -n "$SPECIFIC_CONTEXT" ]]; then
    if [[ "$SPECIFIC_CONTEXT" == "ramen-dr1" ]] || [[ "$SPECIFIC_CONTEXT" == "ramen-dr2" ]]; then
        CONTEXTS=("$SPECIFIC_CONTEXT")
    else
        log_error "Invalid context: $SPECIFIC_CONTEXT. Must be 'ramen-dr1' or 'ramen-dr2'"
        exit 1
    fi
fi

# Verbose logging function
verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "$1"
    fi
}

# Wait for user confirmation
wait_for_user() {
    if [[ "$WAIT_FOR_USER" == "true" ]]; then
        echo ""
        read -p "Press Enter to continue, or Ctrl+C to cancel..."
        echo ""
    fi
}

# Verify prerequisites
verify_prerequisites() {
    log_info "🔍 Verifying prerequisites for storage demos..."
    
    # Check required tools
    local required_tools=("kubectl" "minikube")
    check_required_tools "${required_tools[@]}"
    
    # Verify contexts exist
    for context in "${CONTEXTS[@]}"; do
        if ! context_exists "$context"; then
            log_error "Context '$context' not found. Please run minikube setup first."
            exit 1
        fi
    done
    
    # Check if Rook Ceph is installed
    for context in "${CONTEXTS[@]}"; do
        if ! kubectl --context="$context" get namespace rook-ceph >/dev/null 2>&1; then
            log_error "Rook Ceph namespace not found on $context. Please run Ceph setup first:"
            echo "  ./demo/scripts/storage/set_ceph_storage.sh"
            exit 1
        fi
        
        # Check if Ceph cluster is ready
        local ceph_phase=$(kubectl --context="$context" -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        if [[ "$ceph_phase" != "Ready" ]]; then
            log_warning "Ceph cluster on $context is not ready (phase: $ceph_phase)"
            log_info "Waiting for Ceph cluster to become ready..."
            if ! kubectl --context="$context" -n rook-ceph wait --for=condition=Ready cephcluster rook-ceph --timeout=300s; then
                log_error "Ceph cluster failed to become ready on $context"
                exit 1
            fi
        fi
        
        verbose_log "✅ Ceph cluster ready on $context"
    done
    
    # Verify storage classes exist
    for context in "${CONTEXTS[@]}"; do
        local expected_classes=("rook-ceph-block" "rook-cephfs")
        for sc in "${expected_classes[@]}"; do
            if ! kubectl --context="$context" get storageclass "$sc" >/dev/null 2>&1; then
                log_warning "StorageClass '$sc' not found on $context. This may cause demo failures."
            else
                verbose_log "✅ StorageClass '$sc' available on $context"
            fi
        done
    done
    
    log_success "Prerequisites verified successfully!"
}

# Deploy storage demo
deploy_demo() {
    local demo_type="$1"
    local context="$2"
    
    log_info "🚀 Deploying $demo_type storage demo on $context..."
    
    local demo_file="$DEMO_YAML_DIR/${demo_type}-demo.yaml"
    local vrg_file="$DEMO_YAML_DIR/${demo_type}-vrg.yaml"
    
    if [[ ! -f "$demo_file" ]]; then
        log_error "Demo file not found: $demo_file"
        return 1
    fi
    
    # Apply demo application
    log_step "Applying $demo_type demo application..."
    if kubectl --context="$context" apply -f "$demo_file"; then
        log_success "$demo_type demo application deployed on $context"
    else
        log_error "Failed to deploy $demo_type demo application on $context"
        return 1
    fi
    
    # Wait for deployment to be ready
    local namespace="${demo_type}-demo"
    log_step "Waiting for $demo_type demo to be ready on $context..."
    
    # Wait for namespace to be active
    if ! kubectl --context="$context" wait --for=condition=Active namespace/$namespace --timeout=60s; then
        log_warning "Namespace $namespace did not become active within timeout"
    fi
    
    # Wait for deployments to be ready (give more time for storage provisioning)
    if kubectl --context="$context" -n "$namespace" get deployment >/dev/null 2>&1; then
        if kubectl --context="$context" -n "$namespace" wait --for=condition=available deployment --all --timeout=300s; then
            log_success "$demo_type demo deployments ready on $context"
        else
            log_warning "$demo_type demo deployments not ready within timeout on $context"
            # Show debug information
            log_info "Debug information for $demo_type on $context:"
            kubectl --context="$context" -n "$namespace" get pods
            kubectl --context="$context" -n "$namespace" get pvc
        fi
    fi
    
    # Apply VRG if it's the primary context (ramen-dr1)
    if [[ "$context" == "ramen-dr1" ]] && [[ -f "$vrg_file" ]]; then
        log_step "Applying VolumeReplicationGroup for $demo_type..."
        if kubectl --context="$context" apply -f "$vrg_file"; then
            log_success "VRG deployed for $demo_type demo"
        else
            log_warning "Failed to deploy VRG for $demo_type demo"
        fi
    fi
    
    verbose_log "✅ $demo_type demo deployment completed on $context"
}

# Test storage demo
test_demo() {
    local demo_type="$1"
    local context="$2"
    
    log_info "🧪 Testing $demo_type storage demo on $context..."
    
    local namespace="${demo_type}-demo"
    
    # Check if namespace exists
    if ! kubectl --context="$context" get namespace "$namespace" >/dev/null 2>&1; then
        log_warning "Namespace $namespace not found on $context - skipping tests"
        return 0
    fi
    
    # Test based on demo type
    case "$demo_type" in
        block-storage)
            test_block_storage "$context" "$namespace"
            ;;
        file-storage)
            test_file_storage "$context" "$namespace"
            ;;
        object-storage)
            test_object_storage "$context" "$namespace"
            ;;
        *)
            log_warning "Unknown demo type for testing: $demo_type"
            ;;
    esac
}

# Test block storage demo
test_block_storage() {
    local context="$1"
    local namespace="$2"
    
    log_step "Testing block storage functionality..."
    
    # Check PVC status
    local pvc_status=$(kubectl --context="$context" -n "$namespace" get pvc nginx-block-pvc -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [[ "$pvc_status" == "Bound" ]]; then
        log_success "✅ PVC is bound"
    else
        log_warning "⚠️ PVC status: $pvc_status"
    fi
    
    # Check if deployment is running
    local ready_replicas=$(kubectl --context="$context" -n "$namespace" get deployment nginx-block -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$ready_replicas" -gt 0 ]]; then
        log_success "✅ Block storage demo pod is running"
        
        # Test data persistence
        verbose_log "Testing data persistence..."
        local pod_name=$(kubectl --context="$context" -n "$namespace" get pods -l app=nginx-block -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -n "$pod_name" ]]; then
            if kubectl --context="$context" -n "$namespace" exec "$pod_name" -- test -f /data/san-test/test-file.txt >/dev/null 2>&1; then
                log_success "✅ Data persistence test passed"
            else
                log_warning "⚠️ Data persistence test failed"
            fi
        fi
    else
        log_warning "⚠️ Block storage demo deployment not ready"
    fi
    
    # Check VRG if on primary cluster
    if [[ "$context" == "ramen-dr1" ]]; then
        if kubectl --context="$context" -n "$namespace" get vrg block-storage-vrg >/dev/null 2>&1; then
            local vrg_status=$(kubectl --context="$context" -n "$namespace" get vrg block-storage-vrg -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")
            log_info "VRG status: $vrg_status"
        fi
    fi
}

# Test file storage demo
test_file_storage() {
    local context="$1"
    local namespace="$2"
    
    log_step "Testing file storage functionality..."
    
    # Check PVC status (RWX)
    local pvc_status=$(kubectl --context="$context" -n "$namespace" get pvc shared-file-pvc -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [[ "$pvc_status" == "Bound" ]]; then
        log_success "✅ Shared PVC is bound"
    else
        log_warning "⚠️ Shared PVC status: $pvc_status"
    fi
    
    # Check if multiple writers are running
    local ready_replicas=$(kubectl --context="$context" -n "$namespace" get deployment file-writer -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$ready_replicas" -gt 1 ]]; then
        log_success "✅ Multiple file writers are running ($ready_replicas replicas)"
        
        # Test shared file access
        verbose_log "Testing shared file access..."
        local pod_name=$(kubectl --context="$context" -n "$namespace" get pods -l app=file-writer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -n "$pod_name" ]]; then
            if kubectl --context="$context" -n "$namespace" exec "$pod_name" -- test -f /shared/logs/activity.log >/dev/null 2>&1; then
                log_success "✅ Shared file access test passed"
                local log_lines=$(kubectl --context="$context" -n "$namespace" exec "$pod_name" -- wc -l /shared/logs/activity.log 2>/dev/null | awk '{print $1}' || echo "0")
                verbose_log "Activity log has $log_lines lines"
            else
                log_warning "⚠️ Shared file access test failed"
            fi
        fi
    else
        log_warning "⚠️ File storage demo not fully ready ($ready_replicas replicas)"
    fi
}

# Test object storage demo
test_object_storage() {
    local context="$1"
    local namespace="$2"
    
    log_step "Testing object storage functionality..."
    
    # Check ObjectBucketClaim status
    if kubectl --context="$context" -n "$namespace" get obc vsan-bucket-claim >/dev/null 2>&1; then
        local obc_status=$(kubectl --context="$context" -n "$namespace" get obc vsan-bucket-claim -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [[ "$obc_status" == "Bound" ]]; then
            log_success "✅ Object bucket claim is bound"
        else
            log_info "Object bucket claim status: $obc_status"
        fi
    else
        log_warning "⚠️ Object bucket claim not found"
    fi
    
    # Check if s3-client is running
    local ready_replicas=$(kubectl --context="$context" -n "$namespace" get deployment s3-client -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$ready_replicas" -gt 0 ]]; then
        log_success "✅ S3 client is running"
    else
        log_warning "⚠️ S3 client not ready"
    fi
}

# Clean up storage demo
cleanup_demo() {
    local demo_type="$1"
    local context="$2"
    
    log_info "🧹 Cleaning up $demo_type storage demo on $context..."
    
    local namespace="${demo_type}-demo"
    
    # Delete VRG first (if exists)
    local vrg_name="${demo_type}-vrg"
    if kubectl --context="$context" -n "$namespace" get vrg "$vrg_name" >/dev/null 2>&1; then
        log_step "Deleting VolumeReplicationGroup..."
        kubectl --context="$context" -n "$namespace" delete vrg "$vrg_name" --wait=true >/dev/null 2>&1 || true
    fi
    
    # Delete the entire namespace (this will clean up all resources)
    if kubectl --context="$context" get namespace "$namespace" >/dev/null 2>&1; then
        log_step "Deleting namespace $namespace..."
        kubectl --context="$context" delete namespace "$namespace" --wait=true >/dev/null 2>&1 || true
        log_success "✅ $demo_type demo cleaned up on $context"
    else
        verbose_log "Namespace $namespace not found on $context"
    fi
}

# Main execution functions
run_all_demos() {
    log_info "🚀 Running all storage demos..."
    
    for demo_type in "${DEMO_TYPES[@]}"; do
        log_info "Starting $demo_type storage demo..."
        wait_for_user
        
        for context in "${CONTEXTS[@]}"; do
            deploy_demo "$demo_type" "$context"
        done
        
        # Wait a bit for resources to stabilize
        sleep 10
        
        # Test the demos
        for context in "${CONTEXTS[@]}"; do
            test_demo "$demo_type" "$context"
        done
        
        log_success "$demo_type storage demo completed!"
        echo ""
    done
    
    log_success "🎉 All storage demos completed successfully!"
}

run_single_demo() {
    local demo_type="$1"
    
    log_info "🚀 Running $demo_type storage demo..."
    wait_for_user
    
    for context in "${CONTEXTS[@]}"; do
        deploy_demo "$demo_type" "$context"
    done
    
    # Wait for resources to stabilize
    sleep 15
    
    # Test the demo
    for context in "${CONTEXTS[@]}"; do
        test_demo "$demo_type" "$context"
    done
    
    log_success "🎉 $demo_type storage demo completed successfully!"
}

run_tests_only() {
    log_info "🧪 Running storage tests only..."
    
    for demo_type in "${DEMO_TYPES[@]}"; do
        for context in "${CONTEXTS[@]}"; do
            test_demo "$demo_type" "$context"
        done
    done
    
    log_success "🎉 All storage tests completed!"
}

cleanup_all_demos() {
    log_info "🧹 Cleaning up all storage demos..."
    
    for demo_type in "${DEMO_TYPES[@]}"; do
        for context in "${CONTEXTS[@]}"; do
            cleanup_demo "$demo_type" "$context"
        done
    done
    
    log_success "🎉 All storage demos cleaned up!"
}

# Main execution
main() {
    echo ""
    log_info "🗄️ RamenDR Storage Demos with Rook Ceph"
    echo "=========================================="
    echo ""
    
    # Verify prerequisites unless skipped
    if [[ "$SKIP_SETUP" != "true" ]]; then
        verify_prerequisites
        echo ""
    fi
    
    # Execute based on demo type
    case "$DEMO_TYPE" in
        all)
            run_all_demos
            ;;
        block)
            run_single_demo "block-storage"
            ;;
        file)
            run_single_demo "file-storage"
            ;;
        object)
            run_single_demo "object-storage"
            ;;
        test)
            run_tests_only
            ;;
        cleanup)
            cleanup_all_demos
            ;;
        *)
            log_error "Unknown demo type: $DEMO_TYPE"
            usage
            exit 1
            ;;
    esac
    
    echo ""
    log_success "Storage demo execution completed!"
    echo ""
    log_info "📚 Next Steps:"
    echo "  • Monitor applications: kubectl get pods -A"
    echo "  • Check storage: kubectl get pvc -A" 
    echo "  • View VRGs: kubectl get vrg -A"
    echo "  • Test failover: ./demo/scripts/minikube_demo-failover.sh"
    echo ""
}

# Run main function
main "$@"
