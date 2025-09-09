#!/bin/bash

# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# fresh-demo.sh - One-command fresh RamenDR demo setup
# Runs complete cleanup and demo in sequence

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

# KUBECONFIG check for kind demo (but not required for fresh setup)
check_kubeconfig_for_kind() {
    if [ -z "$KUBECONFIG" ] || [[ "$KUBECONFIG" == "/etc/rancher/k3s/k3s.yaml" ]]; then
        log_info "KUBECONFIG not set or pointing to k3s, setting to default: ~/.kube/config"
        export KUBECONFIG=~/.kube/config
    fi
    
    # Create .kube directory if it doesn't exist
    mkdir -p ~/.kube
    
    # For fresh demo, we don't require existing contexts since we'll create them
    log_success "KUBECONFIG set to: $KUBECONFIG"
}

# Set KUBECONFIG before starting
check_kubeconfig_for_kind

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================="
echo "🎬 RamenDR Fresh Demo - Complete Workflow"
echo "=============================================="
echo ""
echo "This script will:"
echo "   1. 🧹 Clean up existing environment"
echo "   2. 🏗️  Setup kind clusters"
echo "   3. 📦 Install RamenDR operators"
echo "   4. 🌐 Deploy S3 storage and DR policies"
echo "   5. 🔗 Setup cross-cluster S3 access"
echo "   6. 🎯 Run complete demo"
echo ""

# Confirmation
read -p "Proceed with fresh demo setup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Demo cancelled by user"
    exit 0
fi

echo ""

# Step 1: Cleanup
log_step "Step 1/6: Environment cleanup"
if [ -f "$SCRIPT_DIR/cleanup-all.sh" ]; then
    "$SCRIPT_DIR/cleanup-all.sh"
else
    log_error "cleanup-all.sh not found!"
    exit 1
fi

echo ""
log_success "Cleanup completed!"

# Wait a moment
sleep 2

# Step 2: Setup clusters
log_step "Step 2/6: Setting up kind clusters"
if [ -f "$SCRIPT_DIR/setup.sh" ]; then
    "$SCRIPT_DIR/setup.sh" kind
else
    log_error "setup.sh not found!"
    exit 1
fi

echo ""
log_success "Kind clusters ready!"

# Validate kind clusters
log_step "Validating cluster setup..."
log_info "Checking kind clusters:"
if kind get clusters 2>/dev/null | grep -q "ramen-"; then
    kind get clusters | grep "ramen-" | sed 's/^/   ✅ /'
    log_success "All required clusters are running"
else
    log_error "Kind clusters validation failed"
    exit 1
fi

# Export kubeconfig contexts for all clusters
log_info "Exporting kubeconfig contexts..."
kind export kubeconfig --name ramen-hub
kind export kubeconfig --name ramen-dr1  
kind export kubeconfig --name ramen-dr2
log_success "Kubeconfig contexts exported"

# Step 3: Install required dependencies and operators
log_step "Step 3/6: Installing dependencies and RamenDR operators"

# Install missing OCM CRDs first to prevent operator crashes
log_info "Installing required OCM CRDs..."
kubectl config use-context kind-ramen-hub >/dev/null 2>&1

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

# Now install RamenDR operators
log_info "Installing RamenDR operators..."
if [ -f "$SCRIPT_DIR/quick-install.sh" ]; then
    # Use option 3 (All clusters) for automated installation
    echo "3" | "$SCRIPT_DIR/quick-install.sh"
else
    log_error "quick-install.sh not found!"
    exit 1
fi

echo ""
log_success "RamenDR operators installed!"

# Install missing resource classes for VRGs
log_info "Installing missing storage resource classes..."
if [ -f "$SCRIPT_DIR/install-missing-resource-classes.sh" ]; then
    "$SCRIPT_DIR/install-missing-resource-classes.sh"
else
    log_warning "install-missing-resource-classes.sh not found, skipping..."
fi
log_success "Storage resource classes installed"

# Validate operator installation
log_step "Validating operator installation..."
log_info "Checking RamenDR CRDs:"
if kubectl get crd volumereplicationgroups.ramendr.openshift.io >/dev/null 2>&1; then
    log_info "   ✅ VolumeReplicationGroup CRD installed"
else
    log_warning "   ⚠️  VolumeReplicationGroup CRD not found"
fi

log_info "Checking operator pods:"
for context in kind-ramen-hub kind-ramen-dr1 kind-ramen-dr2; do
    kubectl config use-context $context >/dev/null 2>&1
    if kubectl get pods -n ramen-system >/dev/null 2>&1; then
        pod_count=$(kubectl get pods -n ramen-system --no-headers 2>/dev/null | wc -l)
        log_info "   ✅ $context: $pod_count operator pods"
    else
        log_warning "   ⚠️  $context: no ramen-system namespace"
    fi
done
log_success "Operator validation completed"

# Step 4: Deploy S3 and DR policies
log_step "Step 4/6: Deploying S3 storage and DR policies"
if [ -f "$SCRIPT_DIR/../examples/deploy-ramendr-s3.sh" ]; then
    cd "$SCRIPT_DIR/../examples"
    ./deploy-ramendr-s3.sh
    cd "$SCRIPT_DIR"
else
    log_error "deploy-ramendr-s3.sh not found!"
    exit 1
fi

echo ""
log_success "S3 storage and DR policies deployed!"

# Step 5: Setup cross-cluster S3 access
log_step "Step 5/6: Setting up cross-cluster S3 access"
if [ -f "$SCRIPT_DIR/setup-cross-cluster-s3.sh" ]; then
    "$SCRIPT_DIR/setup-cross-cluster-s3.sh"
else
    log_error "setup-cross-cluster-s3.sh not found!"
    exit 1
fi

echo ""
log_success "Cross-cluster S3 access configured!"

# Step 6: Run demo
log_step "Step 6/6: Running RamenDR demo"
if [ -f "$SCRIPT_DIR/../examples/ramendr-demo.sh" ]; then
    cd "$SCRIPT_DIR/../examples"
    ./ramendr-demo.sh
else
    log_error "ramendr-demo.sh not found!"
    exit 1
fi

echo ""
log_success "RamenDR demo completed!"

# Optional: Offer to run failover demonstration
echo ""
log_info "🔄 Optional: Disaster Recovery Failover Demonstration"
log_info "   A separate failover demo is available to show primary/secondary switching"
echo ""
read -p "Run disaster recovery failover demonstration? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Running failover demonstration..."
    if [ -f "$SCRIPT_DIR/../examples/demo-failover.sh" ]; then
        cd "$SCRIPT_DIR/../examples"
        ./demo-failover.sh
        cd "$SCRIPT_DIR"
    else
        log_error "demo-failover.sh not found!"
    fi
else
    log_info "Skipping failover demonstration"
    log_info "   You can run it later with: ./examples/demo-failover.sh"
fi

echo ""
echo "=============================================="
echo "🎉 Fresh RamenDR Demo Complete!"
echo "=============================================="
echo ""

# Final comprehensive validation
log_step "Final Environment Validation"
log_info "🔍 Complete environment status:"

# Check clusters
log_info "📊 Clusters:"
kind get clusters | grep "ramen-" | sed 's/^/   ✅ /'

# Check operators across all clusters  
log_info "🤖 Operators:"
for context in kind-ramen-hub kind-ramen-dr1 kind-ramen-dr2; do
    kubectl config use-context $context >/dev/null 2>&1
    if kubectl get pods -n ramen-system --no-headers 2>/dev/null | grep -q Running; then
        running_pods=$(kubectl get pods -n ramen-system --no-headers 2>/dev/null | grep Running | wc -l)
        log_info "   ✅ $context: $running_pods pods running"
    else
        log_info "   ⚠️  $context: no running pods"
    fi
done

# Check MinIO
kubectl config use-context kind-ramen-hub >/dev/null 2>&1
if kubectl get pods -n minio-system -l app=minio 2>/dev/null | grep -q Running; then
    log_info "💾 Storage:"
    log_info "   ✅ MinIO S3 storage running"
else
    log_info "💾 Storage:"
    log_info "   ⚠️  MinIO not running"
fi

# Check demo app
if kubectl get pods -n nginx-test 2>/dev/null | grep -q Running; then
    log_info "🚀 Demo Application:"
    log_info "   ✅ nginx-test application running"
    if kubectl get vrg -n nginx-test 2>/dev/null | grep -q nginx-test-vrg; then
        log_info "   ✅ VolumeReplicationGroup active"
    fi
else
    log_info "🚀 Demo Application:"
    log_info "   ⚠️  nginx-test not found"
fi

echo ""
log_success "Environment is now running with:"
echo "   • 3 kind clusters (hub + 2 DR clusters)"
echo "   • RamenDR operators installed"
echo "   • MinIO S3 storage configured"
echo "   • Demo application with VRG protection"
echo ""
log_info "🎯 Core RamenDR Capabilities Available:"
echo "   • VolumeReplicationGroup protection"
echo "   • S3 metadata backup and storage"
echo "   • Cross-cluster replication setup"
echo "   • Primary/Secondary state management"
echo ""
log_info "Next steps:"
echo "   • Run failover demo: ./examples/demo-failover.sh"
echo "   • Access MinIO console: http://localhost:9001"
echo "   • Check S3 metadata: ./examples/s3-config/check-minio-backups.sh"
echo "   • Check status: ./examples/monitoring/check-ramendr-status.sh"
echo "   • Clean up when done: ./scripts/cleanup-all.sh"
echo ""
log_success "🎉 RamenDR environment setup completed successfully! 🚀"
