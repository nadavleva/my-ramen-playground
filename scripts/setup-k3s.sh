#!/bin/bash
# RamenDR k3s Multi-Cluster Setup Script
# Creates 3 k3s clusters for hub + 2 DR clusters

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Configuration
K3S_DIR="$HOME/ramen-k3s"
HUB_PORT=6443
DR1_PORT=6444
DR2_PORT=6445

cleanup_existing() {
    log_info "Cleaning up existing k3s clusters..."
    
    # Stop existing k3s services
    sudo systemctl stop k3s || true
    sudo systemctl stop k3s-hub || true
    sudo systemctl stop k3s-dr1 || true
    sudo systemctl stop k3s-dr2 || true
    
    # Remove k3s installations
    if command -v k3s-uninstall.sh >/dev/null 2>&1; then
        log_info "Uninstalling existing k3s..."
        sudo k3s-uninstall.sh || true
    fi
    
    # Clean up data directories
    sudo rm -rf /var/lib/rancher/k3s* 2>/dev/null || true
    sudo rm -rf /opt/k3s-* 2>/dev/null || true
    
    # Clean up kubeconfig directory
    rm -rf "$K3S_DIR" 2>/dev/null || true
    
    log_success "Cleanup completed"
}

install_k3s() {
    log_info "Installing k3s..."
    
    if command -v k3s >/dev/null 2>&1; then
        log_info "k3s already installed, checking version..."
        k3s --version
    else
        log_info "Downloading and installing k3s..."
        curl -sfL https://get.k3s.io | sh -
        log_success "k3s installed successfully"
    fi
    
    # Verify installation
    if ! command -v k3s >/dev/null 2>&1; then
        log_error "k3s installation failed"
        exit 1
    fi
    
    log_success "k3s available: $(k3s --version | head -n1)"
}

create_cluster() {
    local cluster_name="$1"
    local port="$2"
    local data_dir="/opt/k3s-${cluster_name}"
    local kubeconfig="${K3S_DIR}/${cluster_name}/kubeconfig"
    
    log_info "Creating k3s cluster: ${cluster_name} on port ${port}..."
    
    # Create directories
    mkdir -p "${K3S_DIR}/${cluster_name}"
    sudo mkdir -p "$data_dir"
    
    # Start k3s server
    sudo k3s server \
        --data-dir="$data_dir" \
        --cluster-init \
        --write-kubeconfig="$kubeconfig" \
        --write-kubeconfig-mode=644 \
        --https-listen-port="$port" \
        --node-name="${cluster_name}" \
        --cluster-domain="cluster.${cluster_name}" \
        --service-node-port-range="30000-32767" &
    
    local k3s_pid=$!
    log_info "k3s ${cluster_name} started with PID: $k3s_pid"
    
    # Wait for cluster to be ready
    log_info "Waiting for ${cluster_name} cluster to be ready..."
    local timeout=60
    local count=0
    
    while [ $count -lt $timeout ]; do
        if kubectl --kubeconfig="$kubeconfig" get nodes >/dev/null 2>&1; then
            log_success "${cluster_name} cluster is ready!"
            break
        fi
        
        count=$((count + 1))
        sleep 2
        echo -n "."
    done
    
    if [ $count -eq $timeout ]; then
        log_error "${cluster_name} cluster failed to start within ${timeout} seconds"
        return 1
    fi
    
    # Verify cluster
    log_info "Verifying ${cluster_name} cluster..."
    kubectl --kubeconfig="$kubeconfig" get nodes
    kubectl --kubeconfig="$kubeconfig" get pods -A
    
    log_success "${cluster_name} cluster created successfully"
    echo "  📁 Kubeconfig: $kubeconfig"
    echo "  🌐 API Server: https://127.0.0.1:${port}"
}

setup_kubeconfig() {
    log_info "Setting up unified kubeconfig..."
    
    local unified_config="${K3S_DIR}/kubeconfig"
    
    # Merge all kubeconfigs
    KUBECONFIG="${K3S_DIR}/hub/kubeconfig:${K3S_DIR}/dr1/kubeconfig:${K3S_DIR}/dr2/kubeconfig" \
        kubectl config view --flatten > "$unified_config"
    
    # Rename contexts to match our naming convention
    kubectl --kubeconfig="$unified_config" config rename-context default k3s-ramen-hub || true
    kubectl --kubeconfig="$unified_config" config rename-context default k3s-ramen-dr1 || true 
    kubectl --kubeconfig="$unified_config" config rename-context default k3s-ramen-dr2 || true
    
    # Set proper cluster names and contexts
    kubectl --kubeconfig="$unified_config" config set-cluster k3s-ramen-hub --server=https://127.0.0.1:${HUB_PORT}
    kubectl --kubeconfig="$unified_config" config set-cluster k3s-ramen-dr1 --server=https://127.0.0.1:${DR1_PORT}
    kubectl --kubeconfig="$unified_config" config set-cluster k3s-ramen-dr2 --server=https://127.0.0.1:${DR2_PORT}
    
    # Set as default kubeconfig
    export KUBECONFIG="$unified_config"
    
    log_success "Unified kubeconfig created: $unified_config"
    log_info "Available contexts:"
    kubectl config get-contexts
}

verify_setup() {
    log_info "Verifying complete k3s setup..."
    
    local unified_config="${K3S_DIR}/kubeconfig"
    export KUBECONFIG="$unified_config"
    
    for context in k3s-ramen-hub k3s-ramen-dr1 k3s-ramen-dr2; do
        log_info "Testing context: $context"
        if kubectl --context="$context" get nodes >/dev/null 2>&1; then
            log_success "$context is accessible"
            kubectl --context="$context" cluster-info | head -n1
        else
            log_error "$context is not accessible"
            return 1
        fi
    done
    
    log_success "All k3s clusters are ready!"
    echo ""
    echo "🎯 Next steps:"
    echo "  export KUBECONFIG=${unified_config}"
    echo "  ./scripts/setup.sh install  # Test with k3s instead of kind"
}

main() {
    echo "🚀 Setting up k3s clusters for RamenDR..."
    echo ""
    
    cleanup_existing
    install_k3s
    
    log_info "Creating 3 k3s clusters sequentially..."
    
    create_cluster "hub" "$HUB_PORT"
    sleep 5  # Brief pause between clusters
    
    create_cluster "dr1" "$DR1_PORT"  
    sleep 5
    
    create_cluster "dr2" "$DR2_PORT"
    
    setup_kubeconfig
    verify_setup
    
    log_success "k3s multi-cluster setup completed successfully!"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should not be run as root"
   exit 1
fi

# Check for sudo access
if ! sudo -n true 2>/dev/null; then
    log_info "This script requires sudo access for k3s installation"
    sudo -v
fi

main "$@"
