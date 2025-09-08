#!/bin/bash
# RamenDR S3 Configuration Deployment Script
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

# Script setup
SCRIPT_DIR="$(dirname "$0")"
EXAMPLES_DIR="$(dirname "$(dirname "$0")")/yaml"
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

# Function to setup minikube contexts and S3 endpoint
setup_minikube_environment() {
    if command -v minikube >/dev/null 2>&1; then
        log_info "Detected minikube environment"
        # Set minikube contexts
        HUB_CONTEXT="ramen-hub"
        DR1_CONTEXT="ramen-dr1"
        DR2_CONTEXT="ramen-dr2"
        
        # Get hub IP for S3 endpoint
        HUB_IP=$(minikube ip -p ramen-hub)
        if [[ -n "$HUB_IP" ]]; then
            S3_ENDPOINT="http://$HUB_IP:30900"
            log_info "Detected hub cluster IP: $HUB_IP"
            log_info "Using S3 endpoint: $S3_ENDPOINT"
            return 0
        fi
    fi
    log_error "Minikube environment not detected or hub IP not available"
    return 1
}

main() {
    log_info "🚀 Starting RamenDR S3 configuration deployment"
    
    # Setup minikube environment
    setup_minikube_environment || exit 1
    
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
    
    # Step 2: Configure S3 endpoint and profiles
    log_info "🔧 Step 2: Configuring S3 endpoint for cross-cluster access"
    
    # Update S3 profiles with dynamic endpoint
    if [[ -f "$EXAMPLES_DIR/s3-config/s3-profiles.yaml" ]]; then
        sed "s|\"s3Endpoint\": \"http://.*:30900\"|\"s3Endpoint\": \"$S3_ENDPOINT\"|g" \
            "$EXAMPLES_DIR/s3-config/s3-profiles.yaml" > /tmp/s3-profiles-updated.yaml
        run_kubectl apply -f /tmp/s3-profiles-updated.yaml
        rm -f /tmp/s3-profiles-updated.yaml
        log_success "S3 profiles configured with dynamic endpoint"
    else
        log_error "S3 profiles file not found!"
        exit 1
    fi
    
    # Step 3: Create S3 Secret
    log_info "🔐 Step 3: Creating S3 credentials secret"
    if [[ -f "$EXAMPLES_DIR/s3-config/s3-secret.yaml" ]]; then
        run_kubectl apply -f "$EXAMPLES_DIR/s3-config/s3-secret.yaml"
        log_success "S3 secret created successfully"
    else
        log_error "S3 secret file not found!"
        exit 1
    fi
    
    # Step 4: Create DRCluster resources
    log_info "🌐 Step 4: Creating DRCluster resources"
    if [[ -f "$EXAMPLES_DIR/dr-policy/drclusters.yaml" ]]; then
        run_kubectl apply -f "$EXAMPLES_DIR/dr-policy/drclusters.yaml"
        log_success "DRCluster resources created successfully"
    else
        log_error "DRCluster file not found!"
        exit 1
    fi
    
    # Step 5: Create DRPolicy
    log_info "📋 Step 5: Creating DRPolicy for replication"
    if [[ -f "$EXAMPLES_DIR/dr-policy/drpolicy.yaml" ]]; then
        run_kubectl apply -f "$EXAMPLES_DIR/dr-policy/drpolicy.yaml"
        log_success "DRPolicy created successfully"
    else
        log_error "DRPolicy file not found!"
        exit 1
    fi
    
    # Step 6: Create S3 bucket
    log_info "🪣 Step 6: Creating ramen-metadata bucket"
    if [[ "$DRY_RUN" == "false" ]]; then
        if [[ -f "$SCRIPT_DIR/create-minio-bucket.sh" ]]; then
            bash "$SCRIPT_DIR/create-minio-bucket.sh"
            log_success "S3 bucket created successfully"
        else
            log_warning "Bucket creation script not found, bucket will be created automatically"
        fi
    fi
    
    # Verify deployment
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "🔍 Verifying deployment"
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
    
    # Success message
    echo ""
    log_success "🎉 RamenDR S3 configuration deployment completed!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        log_info "📝 Next steps:"
        echo "   1. Access MinIO console: kubectl port-forward -n minio-system service/minio 9001:9001"
        echo "   2. Open browser to: http://localhost:9001"
        echo "   3. Login with: minioadmin / minioadmin"
        echo "   4. Verify 'ramen-metadata' bucket exists"
        echo ""
    fi
}

# Run main function
main "$@"