#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log_info "🚀 Deploying test application with DRPC..."
log_info "   This creates an nginx app with PVC, protected by DRPC."

# Prerequisites check - verify DRPolicy exists
log_info "📋 Checking prerequisites..."
if ! ensure_resource "ramen-hub" "drpolicy" "ramen-dr-policy" "ramen-system"; then
    log_error "DRPolicy not found. Run setup-dr-policy.sh first."
    exit 1
fi
log_success "Prerequisites met."

# Step 1: Ensure namespace exists using ensure_namespace
log_info "📁 Step 1: Creating namespace nginx-test..."
if ! ensure_namespace "ramen-hub" "nginx-test"; then
    log_error "Failed to ensure namespace nginx-test."
    exit 1
fi

# Step 2: Create DRPC-managed placement (two-phase approach)
log_info "📍 Step 2: Creating DRPC-managed placement..."
DRPC_PLACEMENT_YAML="$SCRIPT_DIR/../yaml/test-application/nginx-drpc-placement.yaml"
if ! apply_yaml_file_safe "ramen-hub" "$DRPC_PLACEMENT_YAML" "DRPC placement"; then
    log_error "Failed to apply DRPC placement YAML."
    exit 1
fi

# Wait for OCM to create placement decisions
log_info "⏳ Waiting for OCM to create placement decisions..."
sleep 15

# Check if placement decision is created
for i in {1..6}; do  # Wait up to 1 minute (reduced from 2 minutes)
    if kubectl --context=ramen-hub get placementdecision -n nginx-test -l cluster.open-cluster-management.io/placement=nginx-drpc-placement --no-headers | grep -q .; then
        log_success "✅ Placement decision created by OCM"
        break
    fi
    log_info "   Waiting for placement decision... (attempt $i/6)"
    sleep 10
done

# Verify placement decision exists and shows correct cluster
SELECTED_CLUSTER=$(kubectl --context=ramen-hub get placementdecision -n nginx-test -l cluster.open-cluster-management.io/placement=nginx-drpc-placement -o jsonpath='{.items[0].status.decisions[0].clusterName}' 2>/dev/null || echo "")
if [ -n "$SELECTED_CLUSTER" ]; then
    log_success "✅ Placement decision created, selected cluster: $SELECTED_CLUSTER"
else
    log_warning "⚠️ No placement decision created, DRPC may not work correctly"
fi

# Step 3: Clean up any conflicting placements and DRPC
log_info "🗑️  Step 3: Cleaning up existing resources..."

# Clean up existing DRPC first (with finalizer handling)
if kubectl --context=ramen-hub get drpc nginx-test-drpc -n nginx-test >/dev/null 2>&1; then
    log_info "Removing existing DRPC with finalizer handling..."
    if ! safe_delete_with_finalizers "ramen-hub" "drpc" "nginx-test-drpc" "nginx-test"; then
        log_warning "DRPC deletion failed, but proceeding with creation."
    fi
fi

# Clean up any conflicting placements that might have finalizers
log_info "Cleaning up conflicting placement resources..."
if kubectl --context=ramen-hub get placement dr-primary-placement -n nginx-test >/dev/null 2>&1; then
    log_info "Removing conflicting dr-primary-placement with finalizer handling..."
    if ! safe_delete_with_finalizers "ramen-hub" "placement" "dr-primary-placement" "nginx-test"; then
        log_warning "Failed to clean up dr-primary-placement, but proceeding."
    fi
fi

# Also clean up any orphaned placement decisions
log_info "Cleaning up orphaned placement decisions..."
kubectl --context=ramen-hub delete placementdecision -n nginx-test -l cluster.open-cluster-management.io/placement=dr-primary-placement --ignore-not-found=true >/dev/null 2>&1 || true

# Step 4: Deploy the app YAML first (nginx with PVC)
log_info "🐳 Step 4: Deploying nginx app with PVC..."
APP_YAML="$SCRIPT_DIR/../yaml/test-application/nginx-with-pvc.yaml"
if ! apply_yaml_file_safe "ramen-hub" "$APP_YAML" "nginx app"; then
    log_error "Failed to apply nginx app YAML."
    exit 1
fi

# Step 5: Deploy DRPC to manage the app
log_info "🐳 Step 5: Deploying nginx DRPC..."
DRPC_YAML="$SCRIPT_DIR/../yaml/test-application/nginx-drpc.yaml"
if ! apply_yaml_file_safe "ramen-hub" "$DRPC_YAML" "nginx DRPC"; then
    log_error "Failed to apply DRPC YAML."
    exit 1
fi

# Step 6: Wait for app to be placed on primary cluster (ramen-dr1)
log_info "⏳ Step 6: Waiting for app to be placed on primary cluster (ramen-dr1)..."
for i in {1..10}; do  # Reduced from 30 to 10 attempts (5 minutes to 1.5 minutes)
    if kubectl --context=ramen-dr1 get pods -n nginx-test -l app=nginx --no-headers | grep -q Running; then
        log_success "App successfully placed on ramen-dr1!"
        break
    fi
    log_info "   Waiting for pods on ramen-dr1... (attempt $i/10)"
    sleep 10
done

# If still no pods, log a warning but continue
if ! kubectl --context=ramen-dr1 get pods -n nginx-test -l app=nginx --no-headers | grep -q Running; then
    log_warning "App placement timed out. Check DRPC status and Placement configuration."
fi

# Step 7: Verify using ensure_resource and get_object_yaml
log_info "🔍 Step 7: Verifying deployment..."
if ! ensure_resource "ramen-hub" "drpc" "nginx-test-drpc" "nginx-test"; then
    log_error "DRPC not found after deployment."
    exit 1
fi

# Get DRPC YAML for additional info using get_object_yaml
DRPC_YAML_OUTPUT=$(get_object_yaml "ramen-hub" "drpc" "nginx-test-drpc" "nginx-test")
if [ -n "$DRPC_YAML_OUTPUT" ]; then
    log_info "DRPC details: $(echo "$DRPC_YAML_OUTPUT" | grep -E "(phase|actionNeeded)" || echo "No phase info")"
fi

# Check pods on primary cluster (ramen-dr1)
log_info "   Checking pods on ramen-dr1..."
kubectl --context=ramen-dr1 get pods -n nginx-test -l app=nginx
log_success "Test app ready for failover demo!"

log_info "🎯 Next: Run minikube_demo-failover.sh to test DR."