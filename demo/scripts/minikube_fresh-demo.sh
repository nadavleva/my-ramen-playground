#!/bin/bash

# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# fresh-demo-minikube.sh - Complete RamenDR demo workflow using minikube clusters
# This script automates the entire process from cluster setup to demo completion

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${PURPLE}🚀 $1${NC}"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
HUB_PROFILE="ramen-hub"
DR1_PROFILE="ramen-dr1"
DR2_PROFILE="ramen-dr2"

# Wait function with timeout
wait_for_condition() {
    local description="$1"
    local check_command="$2"
    local timeout="${3:-300}"
    local interval="${4:-10}"
    
    log_info "$description..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if eval "$check_command"; then
            log_success "$description completed"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        log_info "⏳ Waiting... (${elapsed}s/${timeout}s)"
    done
    
    log_error "❌ Timeout waiting for: $description"
    return 1
}

# Check minikube profile exists
check_profile_exists() {
    local profile="$1"
    minikube profile list 2>/dev/null | grep -q "^$profile"
}

# Check kubeconfig for minikube
check_kubeconfig_for_minikube() {
    if [ -z "$KUBECONFIG" ] || [[ "$KUBECONFIG" == "/etc/rancher/k3s/k3s.yaml" ]]; then
        log_info "KUBECONFIG not set or pointing to k3s, setting to default: ~/.kube/config"
        export KUBECONFIG=~/.kube/config
    fi
    
    # Create .kube directory if it doesn't exist
    mkdir -p ~/.kube
    
    # For fresh demo, we don't require existing contexts since we'll create them
    log_success "KUBECONFIG set to: $KUBECONFIG"
}

# Cleanup function for minikube
cleanup_minikube() {
    log_info "Stopping any running minikube port-forwards..."
    pkill -f "kubectl.*port-forward.*minio" 2>/dev/null || true
    
    log_info "Cleaning up existing minikube profiles..."
    for profile in "$HUB_PROFILE" "$DR1_PROFILE" "$DR2_PROFILE"; do
        if check_profile_exists "$profile"; then
            log_info "Stopping and deleting profile: $profile"
            minikube stop --profile="$profile" 2>/dev/null || true
            minikube delete --profile="$profile" 2>/dev/null || true
        fi
    done
    
    log_success "Minikube cleanup completed"
}

# Parse command line arguments
START_FROM_PHASE=""
SKIP_CONFIRMATION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --from-phase)
            START_FROM_PHASE="$2"
            shift 2
            ;;
        --skip-confirmation|--auto|-y)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --help|-h)
            echo "RamenDR Fresh Demo - Complete Workflow (minikube)"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --from-phase PHASE    Start from specific phase (1-6)"
            echo "  --skip-confirmation   Skip confirmation prompts"
            echo "  --auto, -y           Same as --skip-confirmation"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Environment variables:"
            echo "  AUTO_CONFIRM=1       Skip confirmation prompts"
            echo "  START_FROM_PHASE=N   Start from specific phase"
            echo ""
            echo "Phases:"
            echo "  1. Clean up existing environment"
            echo "  2. Setup minikube clusters" 
            echo "  3. Install RamenDR operators"
            echo "  4. Deploy S3 storage and DR policies"
            echo "  5. Setup cross-cluster S3 access"
            echo "  6. Run complete demo"
            echo ""
            echo "Examples:"
            echo "  $0 --from-phase 3 --auto    # Start from phase 3, skip prompts"
            echo "  AUTO_CONFIRM=1 $0           # Run all with no prompts"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check environment variables
if [ -n "${AUTO_CONFIRM:-}" ] && [ "$AUTO_CONFIRM" = "1" ]; then
    SKIP_CONFIRMATION="true"
fi

if [ -n "${START_FROM_PHASE:-}" ]; then
    START_FROM_PHASE="$START_FROM_PHASE"
fi

echo "=============================================="
echo "🎬 RamenDR Fresh Demo - Complete Workflow (minikube)"
echo "=============================================="
echo ""

if [ -n "$START_FROM_PHASE" ]; then
    log_info "🚀 Starting from phase $START_FROM_PHASE"
else
    echo "This script will:"
    echo "   1. 🧹 Clean up existing environment"  
    echo "   2. 🏗️  Setup minikube clusters"
    echo "   3. 📦 Install RamenDR operators"
    echo "   4. 🌐 Deploy S3 storage and DR policies"
    echo "   5. 🔗 Setup cross-cluster S3 access"
    echo "   6. 🎯 Run complete demo"
    echo "   7. 🔄 Optional: Run failover demo"
fi
echo ""

# Confirmation (skip if automated)
if [ "$SKIP_CONFIRMATION" != "true" ]; then
    read -p "Proceed with fresh demo setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Demo cancelled by user"
        exit 0
    fi
else
    log_info "🤖 Running in automated mode"
fi

echo ""

# Step 1: Environment cleanup
if [ -z "$START_FROM_PHASE" ] || [ "$START_FROM_PHASE" -le 1 ]; then
    log_step "Step 1/6: Environment cleanup"
    check_kubeconfig_for_minikube

    # Run cleanup script but adapt for minikube
    log_info "Running minikube cleanup..."
    cleanup_minikube

    log_success "Cleanup completed!"
else
    log_info "⏭️ Skipping cleanup (starting from phase $START_FROM_PHASE)"
fi

# Step 2: Setup minikube clusters
if [ -z "$START_FROM_PHASE" ] || [ "$START_FROM_PHASE" -le 2 ]; then
    log_step "Step 2/6: Setting up minikube clusters"

    log_info "🔧 Running minikube cluster setup..."
    if ! "$SCRIPT_DIR/setup-minikube.sh"; then
        log_error "Minikube cluster setup failed!"
        exit 1
    fi

    log_success "Minikube clusters ready!"
else
    log_info "⏭️ Skipping cluster setup (starting from phase $START_FROM_PHASE)"
fi

# Validate cluster setup
log_step "Validating cluster setup..."
for profile in "$HUB_PROFILE" "$DR1_PROFILE"; do
    if ! check_profile_exists "$profile"; then
        log_error "Required profile $profile not found!"
        exit 1
    fi
    log_info "✅ $profile"
done

# Check for optional DR2
if check_profile_exists "$DR2_PROFILE"; then
    log_info "✅ $DR2_PROFILE"
fi

log_success "All required clusters are running"

# Update kubeconfig contexts
log_info "Updating kubeconfig contexts..."
minikube update-context --profile="$HUB_PROFILE"
minikube update-context --profile="$DR1_PROFILE" 
if check_profile_exists "$DR2_PROFILE"; then
    minikube update-context --profile="$DR2_PROFILE"
fi

# Step 3: Install RamenDR operators  
if [ -z "$START_FROM_PHASE" ] || [ "$START_FROM_PHASE" -le 3 ]; then
    log_step "Step 3/6: Installing RamenDR operators"

    # Install missing OCM CRDs first to prevent operator crashes
    log_info "Installing required OCM CRDs..."
    kubectl config use-context "$HUB_PROFILE" >/dev/null 2>&1

    log_info "📦 Installing OCM dependency CRDs..."
    kubectl apply -f "$SCRIPT_DIR/../hack/test/0000_00_clusters.open-cluster-management.io_managedclusters.crd.yaml" || log_warning "ManagedCluster CRD may already exist"
    kubectl apply -f "$SCRIPT_DIR/../hack/test/0000_00_work.open-cluster-management.io_manifestworks.crd.yaml" || log_warning "ManifestWork CRD may already exist"
    kubectl apply -f "$SCRIPT_DIR/../hack/test/0000_02_clusters.open-cluster-management.io_placements.crd.yaml" || log_warning "Placement CRD may already exist"
    kubectl apply -f "$SCRIPT_DIR/../hack/test/0000_01_addon.open-cluster-management.io_managedclusteraddons.crd.yaml" || log_warning "ManagedClusterAddons CRD may already exist"
    kubectl apply -f "$SCRIPT_DIR/../hack/test/0000_03_clusters.open-cluster-management.io_placementdecisions.crd.yaml" || log_warning "PlacementDecision CRD may already exist"
    kubectl apply -f "$SCRIPT_DIR/../hack/test/view.open-cluster-management.io_managedclusterviews.yaml" || log_warning "ManagedClusterView CRD may already exist"

    # Install PlacementRule CRD (optional but prevents warnings)
    if [ -f "$SCRIPT_DIR/../hack/test/apps.open-cluster-management.io_placementrules_crd.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/../hack/test/apps.open-cluster-management.io_placementrules_crd.yaml" || log_warning "PlacementRule CRD may already exist"
    fi
    log_success "OCM dependency CRDs installed"

    # Install operators using automated quick-install
    log_info "🏗️ Installing RamenDR operators..."
    if ! "$SCRIPT_DIR/quick-install-minikube.sh" 3; then
        log_error "RamenDR operator installation failed!"
        exit 1
    fi

    # Install missing resource classes
    log_info "📦 Installing missing resource classes..."
    if [ -f "$SCRIPT_DIR/install-missing-resource-classes.sh" ]; then
        "$SCRIPT_DIR/install-missing-resource-classes.sh" || {
            log_error "Resource classes installation failed!"  
            exit 1
        }
    else
        log_warning "install-missing-resource-classes.sh not found, skipping"
    fi

    log_success "RamenDR operators installed!"
else
    log_info "⏭️ Skipping operator installation (starting from phase $START_FROM_PHASE)"
fi

# Step 4: Wait for operators to be ready
log_step "Step 4/6: Waiting for operators to be ready"

# Wait for hub operator
wait_for_condition "Hub operator to be ready" \
    "kubectl get pods -n ramen-system --context=$HUB_PROFILE | grep ramen-hub-operator | grep -q Running" \
    300 10

# Wait for DR1 operator
wait_for_condition "DR1 operator to be ready" \
    "kubectl get pods -n ramen-system --context=$DR1_PROFILE | grep ramen-dr-cluster-operator | grep -q Running" \
    300 10

# Wait for DR2 operator if it exists
if check_profile_exists "$DR2_PROFILE"; then
    wait_for_condition "DR2 operator to be ready" \
        "kubectl get pods -n ramen-system --context=$DR2_PROFILE | grep ramen-dr-cluster-operator | grep -q Running" \
        300 10
fi

log_success "All operators are ready!"

# Step 5: Deploy S3 storage and DR policies  
log_step "Step 5/6: Deploying S3 storage and DR policies"

log_info "🗄️ Deploying S3 storage (MinIO)..."
if ! "$SCRIPT_DIR/../examples/deploy-ramendr-s3.sh"; then
    log_error "S3 deployment failed!"
    exit 1
fi

log_success "S3 storage deployed!"

# Step 6: Setup cross-cluster S3 access
log_step "Step 6/6: Setting up cross-cluster S3 access"

log_info "🔗 Setting up cross-cluster S3 access..."
if ! "$SCRIPT_DIR/setup-cross-cluster-s3.sh"; then
    log_error "Cross-cluster S3 setup failed!"
    exit 1
fi

log_success "Cross-cluster S3 access configured!"

# Final verification
echo ""
echo "=============================================="
echo "🎉 RamenDR Fresh Demo Setup Complete!"
echo "=============================================="
echo ""

log_success "🎯 Demo environment is ready!"
echo ""
log_info "📊 Cluster Status:"
kubectl config use-context "$HUB_PROFILE" >/dev/null 2>&1
echo "   🏢 Hub ($HUB_PROFILE):"
kubectl get pods -n ramen-system 2>/dev/null | grep -E "(NAME|ramen-hub)" | sed 's/^/      /'

kubectl config use-context "$DR1_PROFILE" >/dev/null 2>&1
echo "   🌊 DR1 ($DR1_PROFILE):"
kubectl get pods -n ramen-system 2>/dev/null | grep -E "(NAME|ramen-dr-cluster)" | sed 's/^/      /'

if check_profile_exists "$DR2_PROFILE"; then
    kubectl config use-context "$DR2_PROFILE" >/dev/null 2>&1
    echo "   🌊 DR2 ($DR2_PROFILE):"
    kubectl get pods -n ramen-system 2>/dev/null | grep -E "(NAME|ramen-dr-cluster)" | sed 's/^/      /'
fi

echo ""
log_info "🔧 Available kubectl contexts:"
kubectl config get-contexts | grep -E "(NAME|ramen-)" | sed 's/^/   /'

echo ""
log_info "🎯 Next Steps:"
echo "   1. 🧪 Test basic demo: ./examples/ramendr-demo.sh"
echo "   2. 🔄 Run failover demo: ./examples/demo-failover.sh"
echo "   3. 📊 Access MinIO console: kubectl port-forward -n minio-system service/minio 9001:9001 --context=$HUB_PROFILE"
echo "   4. 📚 Read docs: ./examples/DEMO_FLOW_GUIDE.md"

echo ""
log_info "🧹 Cleanup when finished:"
echo "   • Full cleanup: ./scripts/cleanup-all.sh"
echo "   • Minikube only: minikube delete --profile=$HUB_PROFILE --profile=$DR1_PROFILE --profile=$DR2_PROFILE"

# Optional failover demo
if [ "$SKIP_CONFIRMATION" != "true" ]; then
    echo ""
    read -p "🔄 Run failover demonstration now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -f "$SCRIPT_DIR/../examples/demo-failover.sh" ]; then
            log_info "🚀 Starting failover demo..."
            "$SCRIPT_DIR/../examples/demo-failover.sh"
        else
            log_warning "Failover demo script not found at: $SCRIPT_DIR/../examples/demo-failover.sh"
        fi
    fi
else
    log_info "🤖 Skipping failover demo prompt in automated mode"
fi

echo ""
log_success "Happy disaster recovery testing with minikube! 🚀"
