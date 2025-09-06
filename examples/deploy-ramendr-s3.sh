#!/bin/bash
# RamenDR S3 Configuration Deployment Script
# 
# This script deploys MinIO S3 storage and configures RamenDR
# for disaster recovery between Kubernetes clusters.
#
# Usage:
#   ./deploy-ramendr-s3.sh [--dry-run]
#
# Prerequisites:
#   - 3 Kubernetes clusters with contexts: hub-cluster, dr1-cluster, dr2-cluster
#   - RamenDR operators installed on all clusters
#   - kubectl configured with appropriate contexts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Load cluster configuration
SCRIPT_DIR="$(dirname "$0")"
if [[ -f "$SCRIPT_DIR/cluster-config.sh" ]]; then
    source "$SCRIPT_DIR/cluster-config.sh" 2>/dev/null || {
        # Fallback to kind contexts with environment variable override
        HUB_CONTEXT="${HUB_CONTEXT:-kind-ramen-hub}"
        DR1_CONTEXT="${DR1_CONTEXT:-kind-ramen-dr1}"
        DR2_CONTEXT="${DR2_CONTEXT:-kind-ramen-dr2}"
    }
else
    # Fallback to kind contexts with environment variable override
    HUB_CONTEXT="${HUB_CONTEXT:-kind-ramen-hub}"
    DR1_CONTEXT="${DR1_CONTEXT:-kind-ramen-dr1}"
    DR2_CONTEXT="${DR2_CONTEXT:-kind-ramen-dr2}"
fi
EXAMPLES_DIR="$(dirname "$0")"
DRY_RUN=false

# Parse arguments
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    log_info "Running in dry-run mode (no changes will be made)"
fi

# Function to run kubectl with optional dry-run
run_kubectl() {
    if [[ "$DRY_RUN" == "true" ]]; then
        kubectl "$@" --dry-run=client
    else
        kubectl "$@"
    fi
}

# Function to wait for deployment
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local context=$3
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Waiting for $deployment in $namespace to be ready..."
        kubectl --context="$context" wait --for=condition=available --timeout=300s "deployment/$deployment" -n "$namespace"
    fi
}

# Function to check context exists
check_context() {
    local context=$1
    if ! kubectl config get-contexts "$context" >/dev/null 2>&1; then
        log_error "Context '$context' not found. Please check your kubectl configuration."
        exit 1
    fi
}

main() {
    log_info "🚀 Starting RamenDR S3 configuration deployment"
    
    # Check prerequisites
    log_info "📋 Checking prerequisites..."
    
    check_context "$HUB_CONTEXT"
    check_context "$DR1_CONTEXT"  
    check_context "$DR2_CONTEXT"
    
    if [[ ! -d "$EXAMPLES_DIR" ]]; then
        log_error "Examples directory not found: $EXAMPLES_DIR"
        exit 1
    fi
    
    log_success "Prerequisites satisfied"
    
    # Step 1: Deploy MinIO S3 Storage
    log_info "📦 Step 1: Deploying MinIO S3 storage to hub cluster"
    kubectl config use-context "$HUB_CONTEXT"
    
    if [[ -f "$EXAMPLES_DIR/minio-deployment/minio-s3.yaml" ]]; then
        run_kubectl apply -f "$EXAMPLES_DIR/minio-deployment/minio-s3.yaml"
        wait_for_deployment "minio-system" "minio" "$HUB_CONTEXT"
        log_success "MinIO deployed successfully"
    else
        log_error "MinIO deployment file not found!"
        exit 1
    fi
    
    # Step 2: Create S3 Secret
    log_info "🔐 Step 2: Creating S3 credentials secret"
    
    if [[ -f "$EXAMPLES_DIR/s3-config/s3-secret.yaml" ]]; then
        run_kubectl apply -f "$EXAMPLES_DIR/s3-config/s3-secret.yaml"
        log_success "S3 secret created successfully"
    else
        log_error "S3 secret file not found!"
        exit 1
    fi
    
    # Step 3: Create DRCluster resources
    log_info "🌐 Step 3: Creating DRCluster resources"
    
    if [[ -f "$EXAMPLES_DIR/dr-policy/drclusters.yaml" ]]; then
        run_kubectl apply -f "$EXAMPLES_DIR/dr-policy/drclusters.yaml"
        log_success "DRCluster resources created successfully"
    else
        log_error "DRCluster file not found!"
        exit 1
    fi
    
    # Step 4: Create DRPolicy
    log_info "📋 Step 4: Creating DRPolicy for replication"
    
    if [[ -f "$EXAMPLES_DIR/dr-policy/drpolicy.yaml" ]]; then
        run_kubectl apply -f "$EXAMPLES_DIR/dr-policy/drpolicy.yaml"
        log_success "DRPolicy created successfully"
    else
        log_error "DRPolicy file not found!"
        exit 1
    fi
    
    # Step 5: Create S3 bucket for RamenDR metadata
    log_info "🪣 Step 5: Creating ramen-metadata bucket"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Run the bucket creation script
        if [[ -f "$EXAMPLES_DIR/s3-config/create-minio-bucket.sh" ]]; then
            bash "$EXAMPLES_DIR/s3-config/create-minio-bucket.sh"
            log_success "S3 bucket created successfully"
        else
            log_warning "Bucket creation script not found, bucket will be created automatically by RamenDR"
        fi
    fi
    
    # Step 6: Verification
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "🔍 Step 6: Verifying deployment"
        
        echo ""
        log_info "MinIO Status:"
        kubectl --context="$HUB_CONTEXT" get pods -n minio-system
        
        echo ""
        log_info "RamenDR Resources:"
        kubectl --context="$HUB_CONTEXT" get drclusters,drpolicies -n ramen-system
        
        echo ""
        log_info "S3 Secret:"
        kubectl --context="$HUB_CONTEXT" get secret ramen-s3-secret -n ramen-system
    fi
    
    # Success message with next steps
    echo ""
    log_success "🎉 RamenDR S3 configuration deployment completed!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        log_info "📝 Next steps:"
        echo "   1. Access MinIO console: kubectl port-forward -n minio-system service/minio 9001:9001"
        echo "   2. Open browser to: http://localhost:9001"
        echo "   3. Login with: minioadmin / minioadmin"
        echo "   4. Look for 'ramen-metadata' bucket in the console"
        echo "   5. Run: ./examples/ramendr-demo.sh to test applications with PVCs"
        echo ""
        log_info "📚 Documentation: See examples/README.md for detailed usage"
    fi
}

# Run main function
main "$@"
