#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Load utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

set -euo pipefail

main() {
    log_step "Setting up DR Policy and Configuration..."
    
    # Check prerequisites
    check_required_tools kubectl
    
    # Verify OCM is installed
    if ! kubectl --context=ramen-hub get crd managedclusters.cluster.open-cluster-management.io >/dev/null 2>&1; then
        log_error "OCM CRDs not found. Please run setup-ocm-resources.sh first"
        exit 1
    fi
    
    # Wait for ManagedClusters to be ready
    log_info "Waiting for ManagedClusters to be available..."
    ensure_resource "ramen-hub" "managedcluster" "ramen-dr1" "" 120
    ensure_resource "ramen-hub" "managedcluster" "ramen-dr2" "" 120
    
    # Check ManagedCluster status
    log_info "Verifying ManagedCluster status..."
    for cluster in ramen-dr1 ramen-dr2; do
        local status=$(kubectl --context=ramen-hub get managedcluster "$cluster" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}' 2>/dev/null || echo "Unknown")
        if [ "$status" = "True" ]; then
            log_success "ManagedCluster $cluster is available"
        else
            log_warning "ManagedCluster $cluster status: $status (continuing anyway)"
        fi
    done
    
    # Create DRPolicy
    log_info "Creating DRPolicy..."
    kubectl --context=ramen-hub apply -f "${SCRIPT_DIR}/../yaml/dr-policy/drpolicy.yaml"
    
    # Create DRClusters
    log_info "Creating DRClusters..."
    kubectl --context=ramen-hub apply -f "${SCRIPT_DIR}/../yaml/dr-policy/drclusters.yaml"
    
    # Verify DRPolicy
    ensure_resource "ramen-hub" "drpolicy" "dr-policy" "" 60
    ensure_resource "ramen-hub" "drcluster" "ramen-dr1" "" 60
    ensure_resource "ramen-hub" "drcluster" "ramen-dr2" "" 60
    
    log_success "DR Policy and Configuration setup completed!"
    
    # Show status
    log_info "DR Configuration Status:"
    echo "DRPolicy:"
    kubectl --context=ramen-hub get drpolicy -o wide 2>/dev/null || echo "  No DRPolicy found"
    echo ""
    echo "DRClusters:"
    kubectl --context=ramen-hub get drcluster -o wide 2>/dev/null || echo "  No DRClusters found"
    echo ""
    echo "ManagedClusters:"
    kubectl --context=ramen-hub get managedcluster -o wide 2>/dev/null || echo "  No ManagedClusters found"
}

# Run main function
main "$@"
