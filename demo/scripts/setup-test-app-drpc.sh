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
    
    # Verify DR infrastructure exists
    if ! kubectl --context=ramen-hub get drpolicy ramen-dr-policy >/dev/null 2>&1; then
        log_error "DRPolicy not found. Please run setup-dr-policy.sh first"
        exit 1
    fi
    
    if ! kubectl --context=ramen-hub get placementrule dr-primary-placement -n test-app >/dev/null 2>&1; then
        log_error "PlacementRules not found. Please run setup-dr-policy.sh first"
        exit 1
    fi
    
    # Create DRPlacementControl (APPLICATION SPECIFIC)
    log_info "Creating DRPlacementControl for nginx application..."
    create_resource "ramen-hub" "test-app" "$(cat <<EOF
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRPlacementControl
metadata:
  name: nginx-drpc
  namespace: test-app
  labels:
    app.kubernetes.io/name: nginx
    app.kubernetes.io/component: drpc
spec:
  drPolicyRef:
    name: ramen-dr-policy
  placementRef:
    name: dr-primary-placement  # Use pre-created PlacementRule
    kind: PlacementRule
  pvcSelector:
    matchLabels:
      app: nginx
  kubeObjectProtection:
    captureInterval: 5m
EOF
)" "DRPlacementControl"
    
    # Deploy application manifests
    log_info "Applying nginx application manifests..."
    kubectl --context=ramen-hub apply -f "${SCRIPT_DIR}/../yaml/test-application/nginx-with-pvc-fixed.yaml"
    
    # Wait for DRPC to be created
    ensure_resource "ramen-hub" "drplacementcontrol" "nginx-drpc" "test-app" 60
    
    # Check DRPC status
    log_info "Checking DRPlacementControl status..."
    local drpc_phase=$(kubectl --context=ramen-hub get drplacementcontrol nginx-drpc -n test-app -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    log_info "DRPC Phase: $drpc_phase"
    
    log_success "Test application with DRPlacementControl setup completed!"
    
    # Show status summary
    log_info "Application Status Summary:"
    kubectl --context=ramen-hub get drplacementcontrol -n test-app -o wide 2>/dev/null || echo "  No DRPC found"
}

# Run main function
main "$@"