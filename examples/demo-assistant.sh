#!/bin/bash

# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# demo-assistant.sh - Interactive RamenDR Demo Assistant
# Guides presenters through the complete RamenDR demonstration flow

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_step() { echo -e "${PURPLE}🎬 $1${NC}"; }
log_talk() { echo -e "${CYAN}🗣️  $1${NC}"; }

# Function to wait for presenter
wait_for_presenter() {
    local message=${1:-"Press ENTER to continue..."}
    echo ""
    read -p "🎯 $message" -r
    echo ""
}

# Function to run command with explanation
run_demo_command() {
    local cmd="$1"
    local explanation="$2"
    
    echo ""
    log_info "Command: $cmd"
    if [ -n "$explanation" ]; then
        log_talk "$explanation"
    fi
    wait_for_presenter "Press ENTER to run command..."
    
    echo -e "${GREEN}$ $cmd${NC}"
    eval "$cmd"
    echo ""
}

# Function to show talking points
show_talking_points() {
    local title="$1"
    shift
    local points=("$@")
    
    echo ""
    echo "═══════════════════════════════════════════"
    log_talk "TALKING POINTS: $title"
    echo "═══════════════════════════════════════════"
    for point in "${points[@]}"; do
        echo -e "${CYAN}  • $point${NC}"
    done
    echo "═══════════════════════════════════════════"
    wait_for_presenter
}

echo ""
echo "🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬"
echo "🎬                                        🎬"
echo "🎬      RamenDR Interactive Demo          🎬"
echo "🎬         Presentation Assistant         🎬"
echo "🎬                                        🎬"
echo "🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬🎬"
echo ""
log_info "This assistant will guide you through a complete RamenDR demonstration"
log_info "Duration: 15-20 minutes | Audience: Developers, DevOps, Platform teams"
echo ""

# Confirm readiness
read -p "🎯 Ready to start the demo? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Demo preparation cancelled"
    exit 0
fi

# Phase 1: Introduction
show_talking_points "INTRODUCTION & PROBLEM STATEMENT" \
    "Today I'll show RamenDR - Kubernetes-native disaster recovery" \
    "Protects applications and data across multiple clusters" \
    "Automatically backs up metadata to S3 and coordinates DR workflows" \
    "We'll see complete automation from cluster creation to DR testing"

log_step "Phase 1: Show Architecture Overview"
run_demo_command "head -40 examples/RAMENDR_ARCHITECTURE_GUIDE.md" \
    "This shows the two-tier operator architecture with hub and DR cluster operators"

# Phase 2: Environment Setup
show_talking_points "AUTOMATED ENVIRONMENT SETUP" \
    "Starting with completely clean environment" \
    "One command creates 3 kind clusters, installs operators, configures S3" \
    "Zero manual configuration required" \
    "Each step includes built-in validation"

log_step "Phase 2: Launch Complete Automated Setup"

# Check if environment is already set up
if kind get clusters 2>/dev/null | grep -q ramen-; then
    log_warning "RamenDR clusters already exist. Clean first?"
    read -p "Run cleanup? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_demo_command "./scripts/cleanup-all.sh" \
            "This safely removes all RamenDR resources with verification"
    fi
fi

run_demo_command "./scripts/fresh-demo.sh" \
    "Watch the automation: cluster creation → operator installation → S3 setup → demo application"

# Phase 3: Environment Validation
show_talking_points "ENVIRONMENT VALIDATION" \
    "Let's verify our complete RamenDR environment is ready" \
    "Check clusters, operators, storage, and CRDs" \
    "Multi-cluster setup with different roles"

log_step "Phase 3: Verify Complete Environment"

run_demo_command "kind get clusters" \
    "Three clusters: hub (orchestration) + dr1/dr2 (execution sites)"

run_demo_command "for context in kind-ramen-hub kind-ramen-dr1 kind-ramen-dr2; do echo \"=== \$context ===\"; kubectl config use-context \$context; kubectl get pods -n ramen-system 2>/dev/null || echo 'No ramen-system namespace'; echo; done" \
    "RamenDR operators running on each cluster with different roles"

run_demo_command "kubectl config use-context kind-ramen-hub && kubectl get pods -n minio-system" \
    "MinIO S3-compatible storage for metadata backup"

run_demo_command "kubectl get crd | grep ramen" \
    "Custom Resource Definitions that extend Kubernetes for DR"

# Phase 4: Application Protection
show_talking_points "APPLICATION PROTECTION DEMO" \
    "Deploy test application and show RamenDR protection" \
    "VolumeReplicationGroup (VRG) is core RamenDR resource" \
    "Automatically discovers and protects PVCs" \
    "Backs up Kubernetes metadata to S3"

log_step "Phase 4: Show Application Protection in Action"

run_demo_command "kubectl get all,pvc -n nginx-test 2>/dev/null || echo 'Application will be created during demo'" \
    "Our demo application with persistent volume claims"

run_demo_command "kubectl get vrg -n nginx-test 2>/dev/null || echo 'VRG will be created during demo'" \
    "VolumeReplicationGroup protects the application"

log_info "The fresh-demo.sh already created these resources. Let's examine them:"

run_demo_command "kubectl describe vrg nginx-test-vrg -n nginx-test" \
    "VRG status shows protection state, S3 backup, and replication details"

run_demo_command "kubectl get pvc -n nginx-test --show-labels" \
    "Protected PVCs are labeled for RamenDR management"

# Phase 5: S3 Backup Verification
show_talking_points "S3 BACKUP VERIFICATION" \
    "RamenDR backs up application metadata to S3" \
    "This metadata enables recovery on any cluster" \
    "S3 storage provides cross-region durability"

log_step "Phase 5: Verify S3 Backup Storage"

log_info "Starting MinIO console for browser access..."
log_info "🌐 Open http://localhost:9001 in browser (minioadmin/minioadmin)"
log_info "Navigate to 'ramen-metadata' bucket to see backup files"

run_demo_command "./examples/access-minio-console.sh" \
    "This sets up port-forwarding to MinIO web console"

wait_for_presenter "After showing browser console, press ENTER to continue..."

run_demo_command "./examples/monitoring/check-minio-backups.sh" \
    "Command-line verification of S3 backup contents"

run_demo_command "./examples/monitoring/check-ramendr-status.sh" \
    "Comprehensive RamenDR status across all clusters"

# Phase 6: DR Capabilities
show_talking_points "DR CAPABILITIES DEMONSTRATION" \
    "In real DR scenarios, RamenDR orchestrates failover" \
    "DRPolicy defines replication between clusters" \
    "Any cluster can become primary or secondary" \
    "Integrates with Open Cluster Management"

log_step "Phase 6: Show DR Policy and Multi-Cluster Capabilities"

run_demo_command "kubectl get drpolicy,drcluster -o wide 2>/dev/null || echo 'DR policies were configured during setup'" \
    "DR policies define which clusters participate in disaster recovery"

run_demo_command "kubectl config use-context kind-ramen-dr1 && kubectl get nodes && echo && kubectl get storageclass" \
    "DR cluster ready to receive applications during failover"

run_demo_command "kubectl config use-context kind-ramen-hub && cat examples/test-application/nginx-drpc.yaml" \
    "DRPlacementControl would orchestrate application placement and failover"

# Phase 7: Monitoring & Operations
show_talking_points "MONITORING & OPERATIONS" \
    "RamenDR includes comprehensive monitoring tools" \
    "Rich logging and event tracking" \
    "Production-ready operational automation"

log_step "Phase 7: Show Monitoring and Operational Tools"

run_demo_command "ls -la examples/monitoring/" \
    "Built-in monitoring and verification scripts"

run_demo_command "kubectl get events -n nginx-test --sort-by='.lastTimestamp' | tail -10" \
    "Kubernetes events show RamenDR activities"

run_demo_command "kubectl logs -n ramen-system -l app.kubernetes.io/name=ramen --tail=5" \
    "RamenDR operator logs show protection activities"

# Phase 8: Demo Summary
show_talking_points "DEMO SUMMARY & KEY TAKEAWAYS" \
    "✅ Zero Configuration: One command sets up complete DR environment" \
    "✅ Kubernetes Native: Uses familiar K8s resources and patterns" \
    "✅ Production Ready: Comprehensive validation and monitoring" \
    "✅ Multi-Cloud: Supports any Kubernetes distribution" \
    "✅ Policy Driven: Centralized DR policies and governance"

log_step "Phase 8: Demo Complete!"

echo ""
echo "🎉 RamenDR Demo Successfully Completed! 🎉"
echo ""
log_info "Follow-up Resources:"
echo "   • Architecture Guide: examples/RAMENDR_ARCHITECTURE_GUIDE.md"
echo "   • Quick Start: examples/AUTOMATED_DEMO_QUICKSTART.md"
echo "   • Source Code: internal/controller/ and api/v1alpha1/"
echo ""

# Optional cleanup
read -p "🧹 Clean up demo environment? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_step "Cleanup: Removing Demo Environment"
    run_demo_command "./scripts/cleanup-all.sh" \
        "Safe cleanup with validation - returns to clean state"
    log_success "Demo environment cleaned up successfully!"
else
    log_info "Demo environment preserved for exploration"
    echo ""
    log_info "Available for exploration:"
    echo "   • MinIO console: http://localhost:9001"
    echo "   • Monitoring: ./examples/monitoring/check-ramendr-status.sh"
    echo "   • Cleanup later: ./scripts/cleanup-all.sh"
fi

echo ""
log_success "Thank you for the RamenDR demonstration! 🚀"
echo ""
