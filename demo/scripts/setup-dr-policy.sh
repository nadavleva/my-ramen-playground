#!/bin/bash

set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

main() {
    log_step "Setting up DR Policy and Configuration..."
    
    # Check required tools
    check_required_tools "kubectl"
    
    # Verify contexts exist
    if ! context_exists "ramen-hub"; then
        log_error "Context 'ramen-hub' not found. Please run minikube setup first."
        exit 1
    fi
    
    # Check if ManagedClusters exist and wait for them to be available
    log_info "Waiting for ManagedClusters to be available..."
    ensure_resource "ramen-hub" "managedcluster" "ramen-dr1" "" 30
    ensure_resource "ramen-hub" "managedcluster" "ramen-dr2" "" 30
    
    # Check ManagedCluster status (warn but continue if Unknown)
    log_info "Verifying ManagedCluster status..."
    local dr1_status=$(kubectl --context=ramen-hub get managedcluster ramen-dr1 -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}' 2>/dev/null || echo "Unknown")
    local dr2_status=$(kubectl --context=ramen-hub get managedcluster ramen-dr2 -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}' 2>/dev/null || echo "Unknown")
    
    if [ "$dr1_status" != "True" ]; then
        log_warning "ManagedCluster ramen-dr1 status: $dr1_status (continuing anyway)"
    fi
    if [ "$dr2_status" != "True" ]; then
        log_warning "ManagedCluster ramen-dr2 status: $dr2_status (continuing anyway)"
    fi
    
    # Apply DRPolicy from external file
    log_info "Creating DRPolicy..."
    local dr_policy_dir="$SCRIPT_DIR/../yaml/dr-policy"
    apply_yaml_file_safe "ramen-hub" "$dr_policy_dir/drpolicy.yaml" "DRPolicy"
    
    # Apply DRClusters from external file  
    log_info "Creating DRClusters..."
    apply_yaml_file_safe "ramen-hub" "$dr_policy_dir/drclusters.yaml" "DRClusters"
    
    # Create namespace for test applications
    ensure_namespace "ramen-hub" "nginx-test" 60
    
    # Add required labels to ManagedClusters for PlacementRule matching
    log_info "Adding name labels to ManagedClusters for PlacementRule matching..."
    label_managedcluster "ramen-hub" "ramen-dr1" "name" "ramen-dr1"
    label_managedcluster "ramen-hub" "ramen-dr2" "name" "ramen-dr2"
    
    # # Apply PlacementRules from external files
    # log_info "Creating PlacementRules for DR cluster selection..."
    # apply_yaml_with_namespace "ramen-hub" "$dr_policy_dir/placement-rule-primary.yaml" "nginx-test" "Primary PlacementRule"
    # apply_yaml_with_namespace "ramen-hub" "$dr_policy_dir/placement-rule-secondary.yaml" "nginx-test" "Secondary PlacementRule"
    # apply_yaml_with_namespace "ramen-hub" "$dr_policy_dir/placement-rule-any.yaml" "nginx-test" "Generic DR PlacementRule"

    # ...existing code...

    log_info "Creating Placements for DR cluster selection..."

    log_info "Applying Primary Placement from file: $dr_policy_dir/dr-primary-placement.yaml (namespace: nginx-test)"
    kubectl --context=ramen-hub apply -f "$dr_policy_dir/dr-primary-placement.yaml" || log_warning "Primary Placement may already exist or failed to apply"

    log_info "Applying Secondary Placement from file: $dr_policy_dir/dr-secondary-placement.yaml (namespace: nginx-test)"
    kubectl --context=ramen-hub apply -f "$dr_policy_dir/dr-secondary-placement.yaml" || log_warning "Secondary Placement may already exist or failed to apply"

    # Verify all resources using utils
    log_info "Verifying created resources..."
    ensure_resource "ramen-hub" "drpolicy" "ramen-dr-policy" "" 60
    ensure_resource "ramen-hub" "drcluster" "ramen-dr1" "" 60
    ensure_resource "ramen-hub" "drcluster" "ramen-dr2" "" 60
    # Update verification to use nginx-test namespace
    ensure_resource "ramen-hub" "placement" "dr-primary-placement" "nginx-test" 60
    ensure_resource "ramen-hub" "placement" "dr-secondary-placement" "nginx-test" 60
    
    log_success "DR Policy and Configuration setup completed!"
    
    # Show comprehensive status using utils
    log_info "DR Configuration Status:"
    echo ""
    echo "DRPolicy:"
    kubectl --context=ramen-hub get drpolicy -o wide 2>/dev/null || echo "  No DRPolicy found"
    echo ""
    echo "DRClusters:"
    kubectl --context=ramen-hub get drcluster -o wide 2>/dev/null || echo "  No DRClusters found"
    echo ""
    echo "ManagedClusters:"
    kubectl --context=ramen-hub get managedcluster -o wide 2>/dev/null || echo "  No ManagedClusters found"
    echo ""
    echo "Placements:"
    kubectl --context=ramen-hub get placement -n nginx-test -o wide 2>/dev/null || echo "  No Placements found"
    echo ""
    echo "PlacementDecisions:"
    kubectl --context=ramen-hub get placementdecision -n nginx-test -o wide 2>/dev/null || echo "  No PlacementDecisions found"
}

# Allow script to be called directly or sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi