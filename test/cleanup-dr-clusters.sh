#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Cleanup script to delete all DR clusters and related resources
# This removes: hub, dr1, dr2 clusters and their minikube profiles

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}ℹ️  [$(date '+%H:%M:%S')] $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  [$(date '+%H:%M:%S')] $1${NC}"; }
log_success() { echo -e "${GREEN}✅ [$(date '+%H:%M:%S')] $1${NC}"; }

echo -e "${YELLOW}🧹 DR Clusters Cleanup${NC}"
echo "===================="
echo ""

# Configuration
HUB_PROFILE="hub"
DR1_PROFILE="dr1" 
DR2_PROFILE="dr2"

log_warning "This will delete the following minikube clusters:"
echo "  • $HUB_PROFILE"
echo "  • $DR1_PROFILE"
echo "  • $DR2_PROFILE"
echo ""

# Confirmation prompt
read -p "Are you sure you want to proceed? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
log_info "Starting cleanup process..."

# Delete clusters
log_warning "Deleting hub cluster..."
minikube delete --profile="$HUB_PROFILE" 2>/dev/null || log_warning "Hub cluster not found or already deleted"

log_warning "Deleting dr1 cluster..."
minikube delete --profile="$DR1_PROFILE" 2>/dev/null || log_warning "DR1 cluster not found or already deleted"

log_warning "Deleting dr2 cluster..."
minikube delete --profile="$DR2_PROFILE" 2>/dev/null || log_warning "DR2 cluster not found or already deleted"

# Wait for cleanup to complete
sleep 3

# Remove any remaining contexts
log_info "Cleaning up kubectl contexts..."
kubectl config delete-context "$HUB_PROFILE" 2>/dev/null || true
kubectl config delete-context "$DR1_PROFILE" 2>/dev/null || true
kubectl config delete-context "$DR2_PROFILE" 2>/dev/null || true

# Check final status
echo ""
log_info "Remaining minikube profiles:"
minikube profile list 2>/dev/null || echo "No minikube profiles found"

echo ""
log_success "🎉 Cleanup completed!"
echo "All DR clusters and their resources have been removed."
echo ""
echo "To recreate the clusters, run:"
echo "  ./setup-dr-clusters-with-ceph.sh"