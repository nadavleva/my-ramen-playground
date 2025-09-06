#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# fix-kubectl-path.sh - Fix kubectl contexts when multiple kubectl installations exist

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${PURPLE}🔄 $1${NC}"; }

echo "=========================================="
log_info "🔧 Fixing kubectl PATH and kubeconfig issues"
echo "=========================================="
echo ""

log_step "Step 1: Detecting kubectl installations"
echo "Current kubectl: $(which kubectl 2>/dev/null || echo 'not found')"
echo "kubectl version: $(kubectl version --client 2>/dev/null | head -1 || echo 'failed')"
echo ""

# Check for common kubectl locations
common_locations=(
    "/usr/local/bin/kubectl"
    "/usr/bin/kubectl" 
    "/snap/bin/kubectl"
    "/home/nlevanon/aws-gpfs-playground/4.19.1/kubectl"
)

log_info "Looking for kubectl installations:"
for location in "${common_locations[@]}"; do
    if [ -x "$location" ]; then
        version=$($location version --client 2>/dev/null | head -1 || echo "unknown version")
        log_success "Found: $location ($version)"
    else
        echo "   Not found: $location"
    fi
done
echo ""

log_step "Step 2: Environment Analysis"
echo "KUBECONFIG: ${KUBECONFIG:-'(not set)'}"
echo "HOME: $HOME"
echo "Default kubeconfig: ~/.kube/config"

if [ -f ~/.kube/config ]; then
    log_success "Default kubeconfig exists ($(du -h ~/.kube/config | cut -f1))"
else
    log_error "Default kubeconfig missing"
fi
echo ""

log_step "Step 3: Export kubeconfig for all kind clusters"
# Make sure we're in the right directory
if [ ! -f "scripts/setup.sh" ]; then
    cd /home/nlevanon/workspace/RamenDR/ramen 2>/dev/null || {
        log_error "Cannot find RamenDR project directory"
        exit 1
    }
fi

# Export kubeconfig to the default location
for cluster in $(kind get clusters 2>/dev/null); do
    log_info "Exporting kubeconfig for: $cluster"
    kind export kubeconfig --name "$cluster" --kubeconfig ~/.kube/config
done
echo ""

log_step "Step 4: Testing with different kubectl binaries"
for location in "${common_locations[@]}"; do
    if [ -x "$location" ]; then
        log_info "Testing $location:"
        
        # Test without KUBECONFIG set
        contexts=$($location config get-contexts -o name 2>/dev/null | grep "kind-" | wc -l || echo "0")
        echo "   Default config: $contexts kind contexts"
        
        # Test with explicit KUBECONFIG
        KUBECONFIG=~/.kube/config contexts=$($location config get-contexts -o name 2>/dev/null | grep "kind-" | wc -l || echo "0")
        echo "   With KUBECONFIG: $contexts kind contexts"
        echo ""
    fi
done

log_step "Step 5: Solutions"
echo ""

log_info "🎯 SOLUTION 1: Use explicit KUBECONFIG environment variable"
echo "   Run in your other terminal:"
echo "   export KUBECONFIG=~/.kube/config"
echo "   kubectl config get-contexts"
echo ""

log_info "🎯 SOLUTION 2: Use full path to standard kubectl"
if [ -x "/usr/local/bin/kubectl" ]; then
    echo "   /usr/local/bin/kubectl config get-contexts"
    echo "   /usr/local/bin/kubectl get nodes"
elif [ -x "/usr/bin/kubectl" ]; then
    echo "   /usr/bin/kubectl config get-contexts"  
    echo "   /usr/bin/kubectl get nodes"
fi
echo ""

log_info "🎯 SOLUTION 3: Add alias in your terminal"
echo "   alias kubectl-kind='/usr/local/bin/kubectl'"
echo "   kubectl-kind config get-contexts"
echo ""

log_info "🎯 SOLUTION 4: Temporary PATH modification"
echo "   export PATH=/usr/local/bin:\$PATH"
echo "   kubectl config get-contexts"
echo ""

log_step "Step 6: Verification Commands"
echo ""
echo "Run these in your other terminal to verify:"
echo "1. export KUBECONFIG=~/.kube/config"
echo "2. kubectl config get-contexts | grep kind"
echo "3. kubectl get nodes --context=kind-ramen-hub"
echo ""

log_success "✅ Kubeconfig exported successfully!"
log_info "Choose one of the solutions above for your other terminal."
echo ""
