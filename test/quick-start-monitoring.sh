#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Quick start script for Regional DR with enhanced monitoring
# Based on playground monitoring setup from nadavleva/my-ramen-playground

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Check if we're in the test directory
if [ ! -f "envs/regional-dr-monitoring.yaml" ]; then
    log_error "Please run this script from the test directory"
    log_info "cd test && ./quick-start-monitoring.sh"
    exit 1
fi

echo -e "${PURPLE}🚀 RamenDR Regional DR with Enhanced Monitoring${NC}"
echo "=============================================="
echo ""

log_info "This script will:"
echo "  • Set up regional DR environment (hub + dr1 + dr2 clusters)"
echo "  • Deploy Ceph storage with RBD mirroring"
echo "  • Install CSI replication components"
echo "  • Enable metrics-server for monitoring"
echo "  • Set up comprehensive monitoring tools"
echo ""

# Check prerequisites
log_info "Checking prerequisites..."
if ! command -v minikube >/dev/null 2>&1; then
    log_error "minikube not found. Please install minikube first."
    exit 1
fi

if ! python3 -c "import drenv" 2>/dev/null; then
    log_error "drenv module not found. Please install dependencies first:"
    echo "  pip install -e ."
    exit 1
fi

# Check if environment is already running
if minikube profile list 2>/dev/null | grep -q "rdr-monitoring"; then
    log_warning "Regional DR monitoring environment appears to be already running"
    read -p "Do you want to delete and restart? (y/N): " restart
    if [[ $restart =~ ^[Yy]$ ]]; then
        log_info "Deleting existing environment..."
        /home/nlevanon/workspace/ramenfork/ramen/.venv/bin/python -m drenv delete envs/regional-dr-monitoring.yaml || true
    else
        log_info "Skipping environment creation, proceeding to monitoring setup"
        setup_monitoring_only=true
    fi
fi

if [ "$setup_monitoring_only" != "true" ]; then
    # Setup host environment
    log_info "Setting up host environment for drenv..."
    /home/nlevanon/workspace/ramenfork/ramen/.venv/bin/python -m drenv setup envs/regional-dr-monitoring.yaml

    # Start the enhanced regional DR environment
    log_info "Starting Regional DR environment with monitoring..."
    log_warning "This process takes 20-30 minutes. Please be patient..."
    echo ""
    
    /home/nlevanon/workspace/ramenfork/ramen/.venv/bin/python -m drenv start envs/regional-dr-monitoring.yaml
    
    if [ $? -eq 0 ]; then
        log_success "Regional DR environment started successfully!"
    else
        log_error "Failed to start Regional DR environment"
        exit 1
    fi
fi

# Set up monitoring
echo ""
log_info "Setting up monitoring tools..."

# Check if contexts are available
sleep 5  # Wait for contexts to be available
for context in hub dr1 dr2; do
    if ! kubectl config get-contexts -o name | grep -q "^$context$"; then
        log_warning "Context '$context' not found, updating minikube contexts..."
        minikube update-context --profile=rdr-monitoring-$context || true
    fi
done

# Test monitoring script
if ./regional-dr-monitoring.sh 2>&1 | head -5 | grep -q "contexts found"; then
    log_success "Monitoring script is ready!"
else
    log_warning "Monitoring script may need manual context setup"
fi

echo ""
log_success "🎉 Regional DR Environment with Monitoring is Ready!"
echo ""
echo -e "${CYAN}📊 Available Monitoring Options:${NC}"
echo "  • Comprehensive monitoring: ./regional-dr-monitoring.sh"
echo "  • Direct comprehensive view: ./regional-dr-monitoring.sh comprehensive"
echo ""
echo -e "${CYAN}🎯 Cluster Contexts:${NC}"
echo "  • hub    - Management cluster (OCM hub, ArgoCD)"
echo "  • dr1    - Primary DR cluster (Ceph, apps)"
echo "  • dr2    - Secondary DR cluster (Ceph, failover target)"
echo ""
echo -e "${CYAN}🏗️  Key Components:${NC}"
echo "  • Ceph storage with RBD mirroring between dr1 ⟷ dr2"
echo "  • CSI replication APIs (VolumeReplication, VolumeReplicationClass)"
echo "  • RamenDR operators for disaster recovery orchestration"
echo "  • MinIO S3 for metadata backup"
echo "  • Metrics-server for resource monitoring"
echo ""
echo -e "${CYAN}🧪 Next Steps - Testing CSI Replication:${NC}"
echo "  1. Start monitoring: ./regional-dr-monitoring.sh"
echo "  2. Deploy test app: test/basic-test/deploy dr1"
echo "  3. Enable DR: test/basic-test/enable-dr dr1"
echo "  4. Test failover: test/basic-test/failover dr2"
echo "  5. Test relocate: test/basic-test/relocate dr1"
echo ""
echo -e "${PURPLE}📋 Context switching:${NC}"
echo "  kubectl config use-context hub    # Management cluster"
echo "  kubectl config use-context dr1    # Primary cluster"
echo "  kubectl config use-context dr2    # Secondary cluster"
echo ""
log_info "Environment is ready for CSI replication testing!"