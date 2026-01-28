#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors  
# SPDX-License-Identifier: Apache-2.0

# KUBECONFIG Setup Guide for Regional DR Monitoring
# This script helps fix KUBECONFIG and context issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo -e "${BLUE}🔧 KUBECONFIG Setup Guide for Regional DR${NC}"
echo "=========================================="
echo ""

# 1. Show current KUBECONFIG
log_info "Current KUBECONFIG location:"
echo "  File: ${HOME}/.kube/config"
echo "  Environment: ${KUBECONFIG:-'Not set (using default)'}"
echo ""

# 2. Show available contexts
log_info "Available kubectl contexts:"
kubectl config get-contexts || {
    log_error "Failed to get contexts. kubectl may not be configured."
    exit 1
}
echo ""

# 3. Check minikube profiles
log_info "Available minikube profiles:"
minikube profile list 2>/dev/null || log_warning "minikube not available or no profiles found"
echo ""

# 4. Check cluster status
log_info "Checking cluster accessibility:"

clusters=("hub" "dr1" "dr2")
available_clusters=()

for cluster in "${clusters[@]}"; do
    if kubectl config get-contexts -o name | grep -q "^$cluster$"; then
        if kubectl --context=$cluster get nodes >/dev/null 2>&1; then
            log_success "$cluster - Available and accessible"
            available_clusters+=("$cluster")
        else
            log_warning "$cluster - Context exists but cluster not accessible"
        fi
    else
        log_warning "$cluster - Context not found"
        
        # Try to fix missing context
        if minikube profile list 2>/dev/null | grep -q "^$cluster"; then
            log_info "Attempting to fix $cluster context..."
            minikube update-context --profile=$cluster 2>/dev/null && {
                log_success "$cluster context restored"
                available_clusters+=("$cluster")
            } || log_warning "Failed to restore $cluster context"
        fi
    fi
done

echo ""
log_info "Summary:"
echo "  Available clusters: ${available_clusters[*]:-'None'}"
echo "  Required for monitoring: hub, dr1 (minimum)"
echo "  Optional: dr2"
echo ""

# 5. Test monitoring script
if [ "${#available_clusters[@]}" -ge 2 ]; then
    log_success "Sufficient clusters available for monitoring!"
    log_info "You can now run the monitoring script:"
    echo "  cd test"
    echo "  ./regional-dr-monitoring.sh"
else
    log_error "Insufficient clusters for monitoring"
    echo ""
    log_info "To fix this:"
    echo "  1. Start missing clusters: minikube start --profile=<cluster>"
    echo "  2. Update contexts: minikube update-context --profile=<cluster>"
    echo "  3. Re-run this script to verify"
fi

echo ""
log_info "KUBECONFIG troubleshooting:"
echo "  • Default location: ~/.kube/config"
echo "  • To use specific config: export KUBECONFIG=/path/to/config"
echo "  • To merge configs: export KUBECONFIG=config1:config2:config3"
echo "  • To reset: unset KUBECONFIG (uses ~/.kube/config)"