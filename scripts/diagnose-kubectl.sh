#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# diagnose-kubectl.sh - Comprehensive kubectl and kubeconfig diagnostics
# This script helps debug kubectl context issues across different terminal sessions

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
log_info "🔍 Comprehensive kubectl Diagnostics"
echo "=========================================="
echo ""

log_step "Step 1: Environment Check"
echo "Current shell: $0"
echo "Working directory: $(pwd)"
echo "User: $USER"
echo "Home: $HOME"
echo ""

log_step "Step 2: Environment Variables"
echo "KUBECONFIG: ${KUBECONFIG:-'(not set)'}"
echo "PATH contains kubectl: $(echo $PATH | grep -o '[^:]*kubectl[^:]*' || echo 'not found in PATH')"
echo ""

log_step "Step 3: Tool Availability"
if command -v kubectl >/dev/null 2>&1; then
    log_success "kubectl found: $(which kubectl)"
    kubectl version --client 2>/dev/null || log_warning "kubectl version failed"
else
    log_error "kubectl not found in PATH"
fi

if command -v kind >/dev/null 2>&1; then
    log_success "kind found: $(which kind)"
    kind version 2>/dev/null || log_warning "kind version failed"
else
    log_error "kind not found in PATH"
fi
echo ""

log_step "Step 4: Kubeconfig File Analysis"
kubeconfig_file="${KUBECONFIG:-$HOME/.kube/config}"
echo "Expected kubeconfig location: $kubeconfig_file"

if [ -f "$kubeconfig_file" ]; then
    log_success "Kubeconfig file exists"
    echo "File permissions: $(ls -la "$kubeconfig_file")"
    echo "File size: $(du -h "$kubeconfig_file" | cut -f1)"
    
    # Check if file is readable
    if [ -r "$kubeconfig_file" ]; then
        log_success "Kubeconfig file is readable"
    else
        log_error "Kubeconfig file is not readable"
    fi
else
    log_error "Kubeconfig file not found"
fi
echo ""

log_step "Step 5: Kubectl Configuration Test"
if kubectl config view --minify >/dev/null 2>&1; then
    log_success "kubectl config view works"
    echo "Current context: $(kubectl config current-context 2>/dev/null || echo 'none')"
else
    log_error "kubectl config view failed"
fi
echo ""

log_step "Step 6: Context Detection"
if kubectl config get-contexts >/dev/null 2>&1; then
    log_success "kubectl config get-contexts works"
    
    # Count contexts
    total_contexts=$(kubectl config get-contexts -o name 2>/dev/null | wc -l || echo "0")
    kind_contexts=$(kubectl config get-contexts -o name 2>/dev/null | grep "kind-" | wc -l || echo "0")
    
    echo "Total contexts: $total_contexts"
    echo "Kind contexts: $kind_contexts"
    
    if [ "$kind_contexts" -gt 0 ]; then
        log_success "Kind contexts found:"
        kubectl config get-contexts | grep "kind-" | sed 's/^/   /' || echo "   (failed to list)"
    else
        log_warning "No kind contexts found"
    fi
else
    log_error "kubectl config get-contexts failed"
fi
echo ""

log_step "Step 7: Kind Cluster Status"
if kind get clusters >/dev/null 2>&1; then
    clusters=$(kind get clusters 2>/dev/null)
    if [ -n "$clusters" ]; then
        log_success "Kind clusters found:"
        for cluster in $clusters; do
            echo "   • $cluster"
        done
        
        # Test Docker containers
        echo ""
        log_info "Docker containers for kind clusters:"
        docker ps -a --filter "name=.*-control-plane" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "   Failed to query docker containers"
    else
        log_warning "No kind clusters found"
    fi
else
    log_error "kind get clusters failed"
fi
echo ""

log_step "Step 8: Cluster Connectivity Test"
if [ -n "${clusters:-}" ]; then
    for cluster in $clusters; do
        log_info "Testing connectivity to kind-$cluster..."
        
        # Test with different timeout approaches
        if timeout 10s kubectl cluster-info --context="kind-$cluster" >/dev/null 2>&1; then
            log_success "✅ kind-$cluster: API server responding"
        elif kubectl get --raw /healthz --context="kind-$cluster" >/dev/null 2>&1; then
            log_warning "⚠️  kind-$cluster: API server responding (via /healthz)"
        else
            log_error "❌ kind-$cluster: API server not responding"
        fi
    done
else
    log_warning "No clusters to test"
fi
echo ""

log_step "Step 9: Recommendations"
echo ""

# Determine recommendations based on findings
if [ "$kind_contexts" -eq 0 ] && [ -n "${clusters:-}" ]; then
    log_warning "ISSUE: Kind clusters exist but no kubectl contexts found"
    echo "🔧 SOLUTION:"
    echo "   1. Run: ./scripts/fix-kubeconfig.sh"
    echo "   2. Or manually: kind export kubeconfig --name <cluster-name>"
    echo ""
elif [ "$kind_contexts" -gt 0 ] && [ -n "${clusters:-}" ]; then
    log_success "Contexts exist - testing accessibility..."
    echo "🎯 Next steps:"
    echo "   1. Try: kubectl get nodes --context=kind-ramen-hub"
    echo "   2. If that fails, clusters may be starting up"
    echo "   3. Check docker containers: docker ps | grep kind"
    echo ""
else
    log_warning "No kind clusters or contexts found"
    echo "🚀 SOLUTION:"
    echo "   1. Create clusters: ./scripts/setup.sh kind"
    echo "   2. Or use full automation: ./scripts/fresh-demo.sh"
    echo ""
fi

log_info "📋 Quick Commands to Test:"
echo "   kubectl config get-contexts"
echo "   kubectl config current-context"
echo "   kubectl get nodes"
echo "   kind get clusters"
echo ""

log_info "📚 For more help:"
echo "   • ./scripts/fix-kubeconfig.sh - Fix context issues"
echo "   • ./scripts/setup.sh kind - Recreate clusters"
echo "   • examples/DEMO_FLOW_GUIDE.md - Complete guide"
echo ""
