#!/bin/bash

# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# cleanup-all.sh - Comprehensive cleanup script for RamenDR demo environment
# Removes all demo resources, clusters, and port-forwards for a fresh start

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

echo "=============================================="
echo "🧹 RamenDR Complete Environment Cleanup"
echo "=============================================="
echo ""
log_warning "This will remove ALL RamenDR demo resources:"
echo "   • All kind clusters (ramen-hub, ramen-dr1, ramen-dr2)"
echo "   • Demo applications and VRGs"
echo "   • Port-forwards (MinIO console, etc.)"
echo "   • Docker images (optional)"
echo ""
log_warning "⚠️  S3 bucket data cleanup notice:"
echo "   • RamenDR metadata in MinIO buckets will be cleaned if possible"
echo "   • Manual bucket cleanup may be required for complete cleanup"
echo ""

# Confirmation
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cleanup cancelled by user"
    exit 0
fi

echo ""
log_step "Starting comprehensive cleanup..."

# 1. Stop any active port-forwards
log_info "Stopping port-forwards..."
pkill -f "kubectl.*port-forward.*minio" 2>/dev/null && log_success "MinIO port-forwards stopped" || log_info "No MinIO port-forwards running"
pkill -f "kubectl.*port-forward" 2>/dev/null && log_success "All port-forwards stopped" || log_info "No port-forwards running"

# 2. Clean up demo resources
log_info "Cleaning up demo resources..."
cd "$(dirname "$0")/../examples" 2>/dev/null || cd examples 2>/dev/null || true

if [ -f "ramendr-demo.sh" ]; then
    log_info "Running demo cleanup..."
    ./ramendr-demo.sh cleanup 2>/dev/null || log_warning "Demo cleanup failed or no resources to clean"
else
    log_warning "ramendr-demo.sh not found, skipping demo cleanup"
fi

# 3. Remove kind clusters
log_info "Removing kind clusters..."
cd "$(dirname "$0")" 2>/dev/null || true

if command -v kind >/dev/null 2>&1; then
    existing_clusters=$(kind get clusters 2>/dev/null || echo "")
    
    if [ -n "$existing_clusters" ]; then
        log_info "Found existing kind clusters:"
        echo "$existing_clusters" | sed 's/^/   /'
        echo ""
        
        for cluster in $existing_clusters; do
            log_info "Deleting cluster: $cluster"
            kind delete cluster --name "$cluster" 2>/dev/null || log_warning "Failed to delete $cluster"
        done
        
        # Clean up kubectl contexts left behind by kind
        log_info "Cleaning up kubectl contexts..."
        for cluster in $existing_clusters; do
            context_name="kind-$cluster"
            if kubectl config get-contexts "$context_name" >/dev/null 2>&1; then
                kubectl config delete-context "$context_name" >/dev/null 2>&1 && log_info "Removed context: $context_name"
            fi
        done
        
        log_success "Kind clusters and contexts removed"
    else
        log_info "No kind clusters found"
    fi
else
    log_warning "kind not available, skipping cluster cleanup"
fi


log_step "Cleaning minikube clusters..."
log_step "Cleaning minikube clusters..."

# Use sudo for pkill if needed
log_info "Stopping minikube-related processes..."
if ! pkill -f minikube 2>/dev/null; then
    log_warning "Trying with sudo..."
    sudo pkill -f minikube 2>/dev/null || true
fi
sleep 2

# Get actual running profiles
PROFILES=$(minikube profile list -o json | jq -r '.valid[] | select(.Name | startswith("ramen-")) | .Name')

for profile in $PROFILES; do
    log_info "Cleaning profile: $profile"
    
    # Stop profile first
    minikube stop -p "$profile" || true
    sleep 2
    
    # Direct deletion without loops
    log_info "Deleting profile: $profile"
    minikube delete --purge -p "$profile" || {
        log_warning "Standard delete failed, trying force delete..."
        minikube delete --purge --force -p "$profile"
    }
done

# Verify using JSON output
remaining=$(minikube profile list -o json | jq -r '.valid[] | select(.Name | startswith("ramen-")) | .Name')
if [ -n "$remaining" ]; then
    log_error "Failed to delete profiles:"
    echo "$remaining" | sed 's/^/    /'
    log_warning "Try manually: minikube delete --profile <profile-name>"
else
    log_success "All Minikube profiles deleted"
fi

# Clean up related Docker resources
log_info "Cleaning up related Docker resources..."
docker ps -a | grep "minikube-ramen" | awk '{print $1}' | xargs -r docker rm -f
docker network ls | grep "minikube-ramen" | awk '{print $1}' | xargs -r docker network rm

# 4. Clean up Docker images (optional)
echo ""
read -p "Remove RamenDR Docker images? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Removing RamenDR Docker images..."
    
    # Remove RamenDR operator images
    docker rmi quay.io/ramendr/ramen-operator:latest 2>/dev/null && log_info "Removed ramen-operator image" || log_info "No ramen-operator image found"
    
    # Remove MinIO images
    docker rmi quay.io/minio/minio:latest 2>/dev/null && log_info "Removed MinIO image" || log_info "No MinIO image found"
    
    # Remove VolSync images
    docker images | grep volsync | awk '{print $1":"$2}' | xargs -r docker rmi 2>/dev/null && log_info "Removed VolSync images" || log_info "No VolSync images found"
    
    log_success "Docker images cleanup completed"
fi

# 5. Clean up temporary files
log_info "Cleaning up temporary files..."
rm -f /tmp/minio-*.log 2>/dev/null && log_info "Removed MinIO logs" || true
rm -f /tmp/k3s-*.log 2>/dev/null && log_info "Removed k3s logs" || true
rm -f gather.*/ -rf 2>/dev/null && log_info "Removed kubectl-gather directories" || true

log_success "Cleanup completed successfully!"

# Validate cleanup
log_step "Validating cleanup completion..."
log_info "🔍 Cleanup verification:"

# Check kind clusters
if kind get clusters 2>/dev/null | grep -q .; then
    remaining_clusters=$(kind get clusters 2>/dev/null | wc -l)
    log_warning "   ⚠️  $remaining_clusters kind clusters still exist"
    kind get clusters | sed 's/^/      /'
else
    log_info "   ✅ No kind clusters remaining"
fi

# Check kubectl contexts
if kubectl config get-contexts 2>/dev/null | grep -q "kind-"; then
    remaining_contexts=$(kubectl config get-contexts 2>/dev/null | grep "kind-" | wc -l)
    log_warning "   ⚠️  $remaining_contexts kind kubectl contexts still exist"
    kubectl config get-contexts | grep "kind-" | sed 's/^/      /'
else
    log_info "   ✅ No kind kubectl contexts remaining"
fi

# Check port-forwards
if ps aux | grep -q "kubectl.*port-forward"; then
    log_warning "   ⚠️  Port-forwards still running:"
    ps aux | grep "kubectl.*port-forward" | grep -v grep | awk '{print "      " $11 " " $12 " " $13}'
else
    log_info "   ✅ No port-forwards running"
fi

# Check Docker images (informational)
ramen_images=$(docker images | grep -E "(ramen|minio)" | wc -l)
if [ "$ramen_images" -gt 0 ]; then
    log_info "   ℹ️  $ramen_images RamenDR/MinIO Docker images remain (optional cleanup)"
else
    log_info "   ✅ No RamenDR/MinIO Docker images found"
fi

# S3 bucket cleanup notification
log_warning "   ⚠️  S3 bucket data may require manual cleanup:"
echo "      • RamenDR metadata in MinIO buckets"
echo "      • To verify: Access MinIO console or use mc client"
echo "      • Manual cleanup: ./examples/s3-config/check-minio-backups.sh"

echo ""
echo "=============================================="
echo "🎯 Environment Ready for Fresh Demo"
echo "=============================================="
echo ""
log_info "🚀 Automated Setup (Recommended):"
echo "   • Complete demo: ./scripts/fresh-demo.sh"
echo "   • Failover demo: ./examples/demo-failover.sh (after fresh-demo.sh)"
echo ""
log_info "🔧 Manual Setup (Step-by-Step):"
echo "   1. Setup clusters: ./scripts/setup.sh kind"
echo "   2. Install operators: ./scripts/quick-install.sh"
echo "   3. Install OCM CRDs: Apply files from hack/test/"
echo "   4. Install resource classes: ./scripts/install-missing-resource-classes.sh"
echo "   5. Deploy S3 storage: ./examples/deploy-ramendr-s3.sh"
echo "   6. Run basic demo: ./examples/ramendr-demo.sh"
echo "   7. Run failover demo: ./examples/demo-failover.sh"
echo ""
log_info "📚 Documentation:"
echo "   • Demo guide: ./examples/DEMO_FLOW_GUIDE.md"
echo "   • Architecture: ./examples/RAMENDR_ARCHITECTURE_GUIDE.md"
echo "   • Quick start: ./examples/AUTOMATED_DEMO_QUICKSTART.md"
echo ""
log_info "🛠️  Troubleshooting:"
echo "   • Fix KUBECONFIG: export KUBECONFIG=~/.kube/config"
echo "   • Export contexts: kind export kubeconfig --name <cluster-name>"
echo "   • Check operators: kubectl get pods -n ramen-system --all-namespaces"
echo "   • Check CRDs: kubectl get crd | grep ramendr"
echo ""
log_success "Ready for a clean RamenDR demo experience!"
