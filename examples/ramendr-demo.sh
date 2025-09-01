#!/bin/bash

# RamenDR S3 Backup Demo Script
# Demonstrates VolumeReplicationGroup functionality with MinIO S3 storage

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_step() {
    echo -e "${PURPLE}🚀 $1${NC}"
}

log_check() {
    echo -e "${CYAN}🔍 $1${NC}"
}

# Function to wait for resource to be ready
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local timeout=${4:-300}
    
    log_info "Waiting for $resource_type/$resource_name to be ready (timeout: ${timeout}s)..."
    
    local count=0
    while [ $count -lt $timeout ]; do
        if kubectl get $resource_type $resource_name -n $namespace >/dev/null 2>&1; then
            log_success "$resource_type/$resource_name is ready!"
            return 0
        fi
        echo -n "."
        sleep 5
        count=$((count + 5))
    done
    
    log_error "$resource_type/$resource_name not ready after ${timeout}s"
    return 1
}

# Function to check S3 bucket contents
check_s3_contents() {
    log_check "Checking MinIO S3 bucket contents..."
    
    # Start port-forward in background
    kubectl port-forward svc/minio -n minio-system 9000:9000 >/dev/null 2>&1 &
    PF_PID=$!
    
    # Give port-forward time to establish
    sleep 3
    
    # Check bucket contents
    echo "📋 MinIO bucket contents:"
    mc ls minio/ramen-metadata/ 2>/dev/null || echo "   (Bucket empty or still initializing)"
    
    # Kill port-forward
    kill $PF_PID >/dev/null 2>&1 || true
    
    echo ""
}

# Function to show VRG status details
show_vrg_status() {
    local vrg_name=$1
    local namespace=$2
    
    log_check "VRG Status Details:"
    kubectl get vrg $vrg_name -n $namespace -o yaml | grep -A 20 "status:" || echo "No status available yet"
    echo ""
    
    log_check "VRG Events:"
    kubectl get events -n $namespace --field-selector involvedObject.name=$vrg_name --sort-by='.lastTimestamp' || echo "No events found"
    echo ""
}

# Function to show operator logs
show_operator_logs() {
    log_check "RamenDR DR Cluster Operator Logs (last 20 lines):"
    kubectl logs deployment/ramen-dr-cluster-operator -n ramen-system --tail=20 || log_warning "Could not fetch operator logs"
    echo ""
}

# Main demo function
main() {
    echo "🎭 RamenDR S3 Backup Demo"
    echo "========================="
    echo "This demo shows how RamenDR protects PVCs and stores metadata in S3"
    echo ""
    
    # Check current cluster context
    log_info "Current cluster: $(kubectl config current-context)"
    echo ""
    
    # Prerequisites check
    log_step "Prerequisites: Checking RamenDR operators..."
    
    # Check if RamenDR CRDs are installed
    if ! kubectl get crd volumereplicationgroups.ramendr.openshift.io >/dev/null 2>&1; then
        log_error "RamenDR CRDs not found!"
        echo ""
        log_info "RamenDR operators must be installed first. Run:"
        echo "   1. ./scripts/setup.sh kind           # Setup kind clusters"
        echo "   2. ./scripts/quick-install.sh        # Install RamenDR operators" 
        echo "   3. ./examples/ramendr-demo.sh        # Run this demo"
        echo ""
        echo "Or use the automated workflow:"
        echo "   ./scripts/fresh-demo.sh              # Complete setup + demo"
        echo ""
        exit 1
    fi
    
    # Check if ramen-system namespace exists
    if ! kubectl get namespace ramen-system >/dev/null 2>&1; then
        log_error "ramen-system namespace not found!"
        echo ""
        log_info "RamenDR operators not installed. See instructions above."
        exit 1
    fi
    
    log_success "RamenDR operators are installed"
    
    # Step 1: Ensure MinIO S3 storage is running
    log_step "Step 1: Setting up MinIO S3 storage..."
    
    # Check if MinIO is already running
    if kubectl get pod -n minio-system -l app=minio 2>/dev/null | grep -q Running; then
        log_success "MinIO is already running"
    else
        log_info "MinIO not found - deploying S3 storage..."
        
        # Switch to hub cluster context for MinIO
        kubectl config use-context kind-ramen-hub >/dev/null 2>&1 || true
        
        # Deploy MinIO S3 storage
        log_info "Creating MinIO deployment..."
        kubectl apply -f minio-deployment/minio-s3.yaml
        
        # Deploy S3 configuration
        log_info "Configuring S3 credentials and RamenConfig..."
        kubectl apply -f s3-config/s3-secret.yaml
        kubectl apply -f s3-config/ramenconfig.yaml
        
        # Wait for MinIO to be ready
        log_info "Waiting for MinIO to be ready..."
        wait_for_resource deployment minio minio-system 120
        
        # Create S3 bucket
        log_info "Creating ramen-metadata bucket..."
        ./s3-config/create-minio-bucket.sh >/dev/null 2>&1 || log_warning "Bucket creation may have failed - will retry later"
        
        log_success "MinIO S3 storage deployed and configured"
    fi
    
    # Step 2: Deploy test application with correct labels
    log_step "Step 2: Deploying nginx test application with PVC..."
    kubectl apply -f test-application/nginx-with-pvc.yaml
    
    # Add the required label to the PVC for VRG selection
    log_info "Adding protection label to nginx PVC..."
    kubectl label pvc nginx-pvc -n nginx-test app=nginx-test --overwrite
    
    # Wait for application to be ready
    wait_for_resource pod nginx-test nginx-test 60 || true
    log_success "Test application deployed"
    
    # Step 3: Show initial state
    log_step "Step 3: Showing initial state (before VRG)..."
    log_check "PVCs in nginx-test namespace:"
    kubectl get pvc -n nginx-test
    echo ""
    
    log_check "Initial S3 bucket state:"
    check_s3_contents
    
    # Step 4: Create VolumeReplicationGroup
    log_step "Step 4: Creating VolumeReplicationGroup (VRG)..."
    kubectl apply -f test-application/nginx-vrg-correct.yaml
    
    # Wait for VRG to be created
    wait_for_resource vrg nginx-test-vrg nginx-test 30
    
    # Step 5: Monitor VRG processing
    log_step "Step 5: Monitoring VRG processing..."
    
    log_check "VRG Resource Created:"
    kubectl get vrg -n nginx-test
    echo ""
    
    # Wait a bit for processing to begin
    log_info "Waiting 30 seconds for VRG to start processing..."
    sleep 30
    
    # Show detailed status
    show_vrg_status nginx-test-vrg nginx-test
    
    # Step 6: Check for S3 metadata
    log_step "Step 6: Checking S3 bucket for RamenDR metadata..."
    for i in {1..3}; do
        log_info "Check $i/3..."
        check_s3_contents
        sleep 15
    done
    
    # Step 7: Show VolumeReplication resources (if any)
    log_step "Step 7: Checking for VolumeReplication resources..."
    log_check "VolumeReplications in nginx-test namespace:"
    kubectl get volumereplication -n nginx-test 2>/dev/null || log_info "No VolumeReplications found (expected in kind without storage replication)"
    echo ""
    
    # Step 8: Show operator activity
    log_step "Step 8: Checking RamenDR operator logs..."
    show_operator_logs
    
    # Step 9: Final status summary
    log_step "Step 9: Final Status Summary"
    echo "==============================="
    
    log_check "RamenDR Resources:"
    echo "DRClusters: $(kubectl get drclusters -n ramen-system --no-headers | wc -l)"
    echo "DRPolicies: $(kubectl get drpolicies -n ramen-system --no-headers | wc -l)"
    echo "VRGs: $(kubectl get vrg -A --no-headers | wc -l)"
    echo ""
    
    log_check "Protected Application:"
    echo "Namespace: nginx-test"
    echo "PVCs: $(kubectl get pvc -n nginx-test --no-headers | wc -l)"
    echo "Application Status: $(kubectl get pod -n nginx-test -l app=nginx-test --no-headers 2>/dev/null | awk '{print $3}' | head -1 || echo 'Unknown')"
    echo ""
    
    log_check "S3 Storage:"
    echo "MinIO Status: $(kubectl get pod -n minio-system -l app=minio --no-headers | awk '{print $3}' | head -1)"
    echo "S3 Profile: minio-s3"
    echo ""
    
    log_success "Demo completed!"
    log_info "💡 Next steps:"
    echo "   1. Check MinIO web console: kubectl port-forward svc/minio -n minio-system 9001:9001"
    echo "   2. Access at http://localhost:9001 (minioadmin/minioadmin)"
    echo "   3. Look for 'ramen-metadata' bucket and browse its contents"
    echo "   4. Run './monitoring/check-ramendr-status.sh' for detailed status"
    echo ""
    
    log_info "🧹 To clean up:"
    echo "   kubectl delete -f test-application/nginx-vrg-correct.yaml"
    echo "   kubectl delete -f test-application/nginx-with-pvc.yaml"
    echo ""
}

# Help function
show_help() {
    cat << EOF
RamenDR S3 Backup Demo Script

Usage: $0 [OPTION]

OPTIONS:
    demo        Run the complete demo (default)
    cleanup     Clean up demo resources
    status      Show current status only
    help        Show this help message

EXAMPLES:
    $0                    # Run complete demo
    $0 demo              # Run complete demo  
    $0 cleanup           # Clean up demo resources
    $0 status            # Show current status

PREREQUISITES:
    - RamenDR operators installed
    - MinIO S3 storage running
    - kubectl configured for target cluster

This demo shows how RamenDR:
    ✅ Protects PVCs using VolumeReplicationGroups
    ✅ Stores Kubernetes metadata in S3
    ✅ Manages application disaster recovery state
EOF
}

# Cleanup function
cleanup_demo() {
    log_step "Cleaning up demo resources..."
    
    log_info "Removing VRG..."
    kubectl delete -f test-application/nginx-vrg-correct.yaml --ignore-not-found=true
    
    log_info "Removing test application..."
    kubectl delete -f test-application/nginx-with-pvc.yaml --ignore-not-found=true
    
    log_success "Demo cleanup completed!"
}

# Status only function
status_only() {
    log_step "RamenDR Current Status"
    
    ./monitoring/check-ramendr-status.sh
    
    log_info "S3 bucket contents:"
    check_s3_contents
}

# Parse command line arguments
case "${1:-demo}" in
    demo)
        main
        ;;
    cleanup)
        cleanup_demo
        ;;
    status)
        status_only
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
