#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Load utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

set -euo pipefail

main() {
    log_step "Setting up Test Application with DRPlacementControl..."
    
    # Check prerequisites
    check_required_tools kubectl
    
    # Verify prerequisites
    if ! kubectl --context=ramen-hub get drpolicy dr-policy >/dev/null 2>&1; then
        log_error "DRPolicy not found. Please run setup-dr-policy.sh first"
        exit 1
    fi
    
    # Create application namespace on hub (for DRPC)
    ensure_namespace "ramen-hub" "test-app" 60
    
    # Create PlacementRule for initial placement
    log_info "Creating PlacementRule for application placement..."
    create_resource "ramen-hub" "test-app" "$(cat <<EOF
apiVersion: apps.open-cluster-management.io/v1
kind: PlacementRule
metadata:
  name: nginx-placement
  namespace: test-app
spec:
  clusterConditions:
  - status: "True"
    type: ManagedClusterConditionAvailable
  clusterSelector:
    matchLabels:
      name: ramen-dr1
EOF
)" "PlacementRule"
    
    # Create DRPlacementControl
    log_info "Creating DRPlacementControl for nginx application..."
    kubectl --context=ramen-hub apply -f "${SCRIPT_DIR}/../yaml/test-application/nginx-drpc.yaml"
    
    # Wait for DRPC to be created
    ensure_resource "ramen-hub" "drplacementcontrol" "nginx-drpc" "test-app" 60
    
    # Deploy application manifests to be managed by DRPC
    log_info "Applying application manifests..."
    kubectl --context=ramen-hub apply -f "${SCRIPT_DIR}/../yaml/test-application/nginx-with-pvc-fixed.yaml"
    
    # Wait a bit for placement to take effect
    log_info "Waiting for placement decisions..."
    sleep 10
    
    # Check placement status
    log_info "Checking placement status..."
    local placed_cluster=$(kubectl --context=ramen-hub get placementdecision -n test-app -o jsonpath='{.items[0].status.decisions[0].clusterName}' 2>/dev/null || echo "none")
    if [ "$placed_cluster" != "none" ]; then
        log_success "Application placed on cluster: $placed_cluster"
    else
        log_warning "Application placement status unclear"
    fi
    
    # Check DRPC status
    log_info "Checking DRPlacementControl status..."
    local drpc_phase=$(kubectl --context=ramen-hub get drplacementcontrol nginx-drpc -n test-app -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    log_info "DRPC Phase: $drpc_phase"
    
    log_success "Test application with DRPlacementControl setup completed!"
    
    # Show status summary
    log_info "Application Status Summary:"
    echo "DRPlacementControl:"
    kubectl --context=ramen-hub get drplacementcontrol -n test-app -o wide 2>/dev/null || echo "  No DRPC found"
    echo ""
    echo "PlacementRule:"
    kubectl --context=ramen-hub get placementrule -n test-app -o wide 2>/dev/null || echo "  No PlacementRule found"
    echo ""
    echo "PlacementDecision:"
    kubectl --context=ramen-hub get placementdecision -n test-app -o wide 2>/dev/null || echo "  No PlacementDecision found"
    echo ""
    
    # Check application on target cluster
    if [ "$placed_cluster" != "none" ] && [ -n "$placed_cluster" ]; then
        echo "Application on $placed_cluster:"
        kubectl --context="$placed_cluster" get pods -n test-app 2>/dev/null || echo "  No pods found in test-app namespace"
    fi
}

# Run main function
main "$@"
