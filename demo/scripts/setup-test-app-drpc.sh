#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log_info "🚀 Deploying test application with DRPC..."
log_info "   This creates an nginx app with PVC, protected by DRPC."

# Prerequisites check using ensure_resource
log_info "📋 Checking prerequisites..."
if ! ensure_resource "ramen-hub" "placement" "dr-primary-placement" "nginx-test"; then
    log_error "Placement not found. Run setup-dr-policy.sh first."
    exit 1
fi
log_success "Prerequisites met."

# Step 1: Ensure namespace exists using ensure_namespace
log_info "📁 Step 1: Creating namespace nginx-test..."
if ! ensure_namespace "ramen-hub" "nginx-test"; then
    log_error "Failed to ensure namespace nginx-test."
    exit 1
fi

# Step 2: Handle existing DRPC using safe_delete
log_info "🗑️  Step 2: Checking for existing DRPC..."
if ! safe_delete "ramen-hub" "drpc" "nginx-test-drpc" "nginx-test"; then
    log_warning "DRPC deletion failed, but proceeding with creation."
fi

# Step 3: Deploy the app YAML first (nginx with PVC)
log_info "🐳 Step 3a: Deploying nginx app with PVC..."
APP_YAML="$SCRIPT_DIR/../yaml/test-application/nginx-with-pvc.yaml"
if ! apply_yaml_file_safe "ramen-hub" "$APP_YAML" "nginx app"; then
    log_error "Failed to apply nginx app YAML."
    exit 1
fi

# Step 4: Deploy DRPC to manage the app
log_info "🐳 Step 4: Deploying nginx DRPC..."
DRPC_YAML="$SCRIPT_DIR/../yaml/test-application/nginx-drpc.yaml"
if ! apply_yaml_file_safe "ramen-hub" "$DRPC_YAML" "nginx DRPC"; then
    log_error "Failed to apply DRPC YAML."
    exit 1
fi

# Step 5: Wait for app to be placed on primary cluster (ramen-dr1)
log_info "⏳ Step 5: Waiting for app to be placed on primary cluster (ramen-dr1)..."
for i in {1..30}; do
    if kubectl --context=ramen-dr1 get pods -n nginx-test -l app=nginx --no-headers | grep -q Running; then
        log_success "App successfully placed on ramen-dr1!"
        break
    fi
    log_info "   Waiting for pods on ramen-dr1... (attempt $i/30)"
    sleep 10
done

# If still no pods, log a warning but continue
if ! kubectl --context=ramen-dr1 get pods -n nginx-test -l app=nginx --no-headers | grep -q Running; then
    log_warning "App placement timed out. Check DRPC status and Placement configuration."
fi

# Step 6: Verify using ensure_resource and get_object_yaml
log_info "🔍 Step 6: Verifying deployment..."
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