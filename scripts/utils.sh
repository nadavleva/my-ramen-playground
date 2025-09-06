#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Common utilities and logging functions for RamenDR scripts

# Color definitions
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
log_step() { echo -e "${BLUE}🔧 $1${NC}"; }

# KUBECONFIG check for kind demo
check_kubeconfig_for_kind() {
    if [ -z "$KUBECONFIG" ]; then
        log_info "KUBECONFIG not set, setting to default: ~/.kube/config"
        export KUBECONFIG=~/.kube/config
    fi
    
    # Check for kind contexts
    if ! kubectl config get-contexts 2>/dev/null | grep -q "kind-"; then
        log_error "No kind contexts found"
        echo ""
        echo "🔧 To fix this:"
        echo "   export KUBECONFIG=~/.kube/config"
        echo "   kubectl config get-contexts"
        echo ""
        echo "Or run: ./scripts/fix-kubeconfig.sh"
        exit 1
    fi
    log_success "Kind contexts available"
}

# Check kubectl availability
check_kubectl() {
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "kubectl is not connected to a cluster"
        log_info "Please configure kubectl to connect to your Kubernetes cluster"
        exit 1
    fi
    
    local cluster_info=$(kubectl cluster-info | head -n1)
    log_success "Connected to: $cluster_info"
}
