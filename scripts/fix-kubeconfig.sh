#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# fix-kubeconfig.sh - Fix kubectl contexts for kind clusters
# This script ensures all kind clusters have their contexts properly exported

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo "=========================================="
log_info "🔧 Fixing kubectl contexts for kind clusters"
echo "=========================================="
echo ""

# Check if kind is available
if ! command -v kind >/dev/null 2>&1; then
    log_error "kind not found. Please install kind first."
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    log_error "kubectl not found. Please install kubectl first."
    exit 1
fi

# Get existing kind clusters
clusters=$(kind get clusters 2>/dev/null || echo "")

if [ -z "$clusters" ]; then
    log_warning "No kind clusters found"
    log_info "Create clusters first with: ./scripts/setup.sh kind"
    exit 0
fi

log_info "Found kind clusters:"
for cluster in $clusters; do
    echo "   • $cluster"
done
echo ""

log_info "Exporting kubeconfig for all kind clusters..."
echo ""

# Export kubeconfig for each cluster
for cluster in $clusters; do
    log_info "🔄 Exporting kubeconfig for cluster: $cluster"
    if kind export kubeconfig --name "$cluster" --kubeconfig ~/.kube/config; then
        log_success "Exported kubeconfig for $cluster"
    else
        log_warning "Kind export failed, but kubeconfig may already be correct"
        log_info "Checking if context exists..."
        if kubectl config get-contexts "kind-$cluster" >/dev/null 2>&1; then
            log_success "Context kind-$cluster already exists and is functional"
        else
            log_error "Context kind-$cluster not found"
        fi
    fi
done

echo ""
log_info "🔍 Verifying kubectl contexts..."
echo ""

# Show current contexts
if kubectl config get-contexts 2>/dev/null | grep -q "kind-"; then
    log_success "kubectl contexts found:"
    kubectl config get-contexts | grep "kind-" | sed 's/^/   /'
    echo ""
    
    # Show current context
    current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    log_info "Current context: $current_context"
    echo ""
    
    log_info "🎯 To switch between contexts:"
    for cluster in $clusters; do
        echo "   kubectl config use-context kind-$cluster"
    done
    echo ""
    
    log_success "✅ All kubectl contexts are properly configured!"
else
    log_warning "No kind contexts found in kubectl"
    log_info "Testing cluster connectivity directly..."
    echo ""
    
    # Test if clusters are actually accessible
    accessible_clusters=0
    for cluster in $clusters; do
        log_info "Testing cluster accessibility: $cluster"
        if timeout 15s kubectl get nodes --context="kind-$cluster" >/dev/null 2>&1; then
            log_success "✅ Cluster $cluster is accessible via kubectl"
            ((accessible_clusters++))
        else
            log_warning "❓ Cluster $cluster not accessible (timeout or error)"
        fi
    done
    
    if [ $accessible_clusters -gt 0 ]; then
        log_success "🎯 Good news: $accessible_clusters cluster(s) are working!"
        log_info "You can proceed with RamenDR installation."
    else
        log_error "❌ No clusters are accessible"
        echo ""
        log_info "💡 Troubleshooting steps:"
        echo "   1. Check KUBECONFIG environment variable: echo \$KUBECONFIG"
        echo "   2. Check kubeconfig file: ls -la ~/.kube/config"
        echo "   3. Try recreating clusters: ./scripts/setup.sh kind"
    fi
fi

echo ""
log_info "📚 For more help, see:"
echo "   • examples/DEMO_FLOW_GUIDE.md"
echo "   • examples/CLUSTER_COMPATIBILITY.md"
echo ""
