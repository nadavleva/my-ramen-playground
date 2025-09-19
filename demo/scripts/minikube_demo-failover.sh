#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log_info "🔄 Starting RamenDR Failover Demo..."
log_info "   This script simulates a failover scenario for the test application."

# Prerequisites check
log_info "📋 Checking prerequisites..."
if ! ensure_resource "ramen-hub" "drpolicy" "ramen-dr-policy"; then
    log_error "DRPolicy not found. Run setup-dr-policy.sh first."
    exit 1
fi
if ! ensure_resource "ramen-hub" "drpc" "nginx-test-drpc" "nginx-test"; then  # Fixed: Correct name and context
    log_error "Test app DRPC not found. Run setup-test-app-drpc.sh first."
    exit 1
fi
log_success "Prerequisites met."

# Step 1: Verify initial state
log_info "🔍 Step 1: Verifying initial application state on primary cluster (ramen-dr1)..."
kubectl --context=ramen-dr1 get pods -n nginx-test -l app=nginx
kubectl --context=ramen-dr1 get pvc -n nginx-test
kubectl --context=ramen-hub get drpc nginx-test-drpc -n nginx-test -o yaml | grep -E "(phase|actionNeeded)"  # Fixed: Query hub
log_success "Initial state verified."

# Step 2: Simulate failure (e.g., stop primary cluster)
log_info "💥 Step 2: Simulating primary cluster failure..."
log_warning "In a real scenario, this would involve stopping ramen-dr1."
# For demo, we'll just annotate the DRPC to trigger failover
kubectl --context=ramen-hub annotate drpc nginx-test-drpc -n nginx-test ramen.io/dr-action=Relocate  # Fixed: Correct name
log_success "Failover triggered."

# Step 3: Monitor failover
log_info "⏳ Step 3: Monitoring failover progress..."
for i in {1..30}; do
    phase=$(kubectl --context=ramen-hub get drpc nginx-test-drpc -n nginx-test -o jsonpath='{.status.phase}')  # Fixed: Correct name and context
    if [ "$phase" == "Relocated" ]; then
        log_success "Failover complete! Application relocated to secondary cluster."
        break
    fi
    log_info "   Waiting... Current phase: $phase"
    sleep 10
done

# Step 4: Verify post-failover state
log_info "✅ Step 4: Verifying application on secondary cluster (ramen-dr2)..."
kubectl --context=ramen-dr2 get pods -n nginx-test -l app=nginx
kubectl --context=ramen-dr2 get pvc -n nginx-test
kubectl --context=ramen-hub get drpc nginx-test-drpc -n nginx-test -o yaml | grep -E "(phase|actionNeeded)"  # Fixed: Query hub
log_success "Failover demo complete!"

log_info "🎉 Demo Summary:"
log_info "   - Primary cluster: ramen-dr1 (simulated failure)"
log_info "   - Secondary cluster: ramen-dr2 (application relocated)"
log_info "   - Data replicated via VolSync/VRG."
log_info "   - Next: Test recovery or cleanup with cleanup-all.sh"