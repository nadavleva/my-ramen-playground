#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# kubeconfig-check.sh - Reusable KUBECONFIG validation function
# Source this file in scripts that need kubectl access to kind clusters

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions for kubeconfig checks
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Main function to check and fix KUBECONFIG
check_and_fix_kubeconfig() {
    local script_name="${1:-$(basename "$0")}"
    
    # Check if KUBECONFIG is set
    if [ -z "$KUBECONFIG" ]; then
        log_warning "KUBECONFIG not set, setting to default location"
        export KUBECONFIG=~/.kube/config
    fi
    
    # Check if kubeconfig file exists
    if [ ! -f "$KUBECONFIG" ]; then
        log_error "Kubeconfig file not found: $KUBECONFIG"
        echo ""
        echo "🔧 To fix this:"
        echo "   1. Create kind clusters: ./scripts/setup.sh kind"
        echo "   2. Or run complete setup: ./scripts/fresh-demo.sh"
        return 1
    fi
    
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl not found in PATH"
        echo ""
        echo "🔧 To fix this:"
        echo "   1. Install kubectl"
        echo "   2. Or use system kubectl: /usr/local/bin/kubectl"
        return 1
    fi
    
    # Check for kind contexts
    local kind_contexts=$(kubectl config get-contexts -o name 2>/dev/null | grep "^kind-" | wc -l || echo "0")
    
    if [ "$kind_contexts" -eq 0 ]; then
        log_warning "No kind contexts found"
        echo ""
        log_info "Attempting to fix kubeconfig..."
        
        # Try to export kubeconfig for existing kind clusters
        local kind_clusters=$(kind get clusters 2>/dev/null || echo "")
        if [ -n "$kind_clusters" ]; then
            log_info "Found kind clusters, exporting kubeconfig..."
            for cluster in $kind_clusters; do
                kind export kubeconfig --name "$cluster" --kubeconfig "$KUBECONFIG" 2>/dev/null || true
            done
            
            # Check again
            kind_contexts=$(kubectl config get-contexts -o name 2>/dev/null | grep "^kind-" | wc -l || echo "0")
            if [ "$kind_contexts" -gt 0 ]; then
                log_success "Fixed! Found $kind_contexts kind contexts"
            else
                log_error "Still no kind contexts found"
                echo ""
                echo "🔧 To fix this:"
                echo "   1. Run: ./scripts/fix-kubeconfig.sh"
                echo "   2. Or: export KUBECONFIG=~/.kube/config"
                echo "   3. Check: kubectl config get-contexts"
                return 1
            fi
        else
            log_error "No kind clusters found"
            echo ""
            echo "🔧 To fix this:"
            echo "   1. Create clusters: ./scripts/setup.sh kind"
            echo "   2. Or run: ./scripts/fresh-demo.sh"
            return 1
        fi
    else
        log_success "Found $kind_contexts kind contexts"
    fi
    
    # Test cluster connectivity
    local accessible_clusters=0
    for context in $(kubectl config get-contexts -o name 2>/dev/null | grep "^kind-"); do
        if timeout 5s kubectl get nodes --context="$context" >/dev/null 2>&1; then
            ((accessible_clusters++))
        fi
    done
    
    if [ "$accessible_clusters" -eq 0 ]; then
        log_warning "Kind contexts exist but clusters not accessible"
        log_info "Clusters may be starting up, continuing anyway..."
    else
        log_success "✅ $accessible_clusters clusters accessible"
    fi
    
    # Set a reasonable default context if current context is not kind
    local current_context=$(kubectl config current-context 2>/dev/null || echo "")
    if [[ ! "$current_context" =~ ^kind- ]]; then
        local hub_context=$(kubectl config get-contexts -o name 2>/dev/null | grep "kind-.*hub" | head -1)
        if [ -n "$hub_context" ]; then
            kubectl config use-context "$hub_context" >/dev/null 2>&1
            log_info "Switched to context: $hub_context"
        fi
    fi
    
    return 0
}

# Quick function for scripts that just need basic checking
ensure_kubeconfig() {
    if [ -z "$KUBECONFIG" ]; then
        export KUBECONFIG=~/.kube/config
    fi
}

# Function to check if we're in the right directory
ensure_ramen_directory() {
    if [ ! -f "scripts/setup.sh" ] && [ ! -f "../scripts/setup.sh" ]; then
        if [ -d "/home/nlevanon/workspace/RamenDR/ramen" ]; then
            cd /home/nlevanon/workspace/RamenDR/ramen
        else
            echo "❌ Error: Not in RamenDR project directory"
            echo "   Please run from: /home/nlevanon/workspace/RamenDR/ramen"
            return 1
        fi
    fi
}
