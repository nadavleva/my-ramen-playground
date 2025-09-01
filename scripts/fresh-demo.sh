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
echo "   4. 🎯 Run complete demo"
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
log_step "Step 1/4: Environment cleanup"
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
log_step "Step 2/4: Setting up kind clusters"
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

# Step 3: Install operators
log_step "Step 3/4: Installing RamenDR operators"
if [ -f "$SCRIPT_DIR/quick-install.sh" ]; then
    "$SCRIPT_DIR/quick-install.sh"
else
    log_error "quick-install.sh not found!"
    exit 1
fi

echo ""
log_success "RamenDR operators installed!"

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

# Step 4: Run demo
log_step "Step 4/4: Running RamenDR demo"
if [ -f "$SCRIPT_DIR/../examples/ramendr-demo.sh" ]; then
    cd "$SCRIPT_DIR/../examples"
    ./ramendr-demo.sh
else
    log_error "ramendr-demo.sh not found!"
    exit 1
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
log_info "Next steps:"
echo "   • Access MinIO console: http://localhost:9001"
echo "   • Check status: ./examples/monitoring/check-ramendr-status.sh"
echo "   • Clean up when done: ./scripts/cleanup-all.sh"
echo ""
log_success "Happy RamenDR exploration! 🚀"
