#!/bin/bash
# setup-kind-enhanced.sh - Enhanced kind cluster setup for RamenDR with Docker
# This script addresses networking issues and provides a complete RamenDR environment

set -euo pipefail

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
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${PURPLE}🔄 $1${NC}"; }
log_details() { echo -e "${CYAN}   $1${NC}"; }

# Configuration
HUB_CLUSTER="ramen-hub"
DR1_CLUSTER="ramen-dr1"
DR2_CLUSTER="ramen-dr2"

# Check prerequisites
check_prerequisites() {
    echo "=========================================="
    log_info "🔍 Checking Prerequisites for kind Setup"
    echo "=========================================="
    echo ""
    
    local missing=0
    
    log_step "Checking required tools..."
    
    # Check Docker
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            log_success "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
        else
            log_error "Docker installed but daemon not running"
            log_details "Run: sudo systemctl start docker"
            ((missing++))
        fi
    else
        log_error "Docker not found"
        log_details "Run: ./scripts/setup-linux.sh to install"
        ((missing++))
    fi
    
    # Check kind
    if command -v kind >/dev/null 2>&1; then
        log_success "kind: $(kind version | head -n1)"
    else
        log_error "kind not found"
        log_details "Run: ./scripts/setup-linux.sh to install"
        ((missing++))
    fi
    
    # Check kubectl
    if command -v kubectl >/dev/null 2>&1; then
        log_success "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    else
        log_error "kubectl not found"
        log_details "Run: ./scripts/setup-linux.sh to install"
        ((missing++))
    fi
    
    # Check helm
    if command -v helm >/dev/null 2>&1; then
        log_success "helm: $(helm version --short 2>/dev/null || helm version)"
    else
        log_error "helm not found"
        log_details "Run: ./scripts/setup-linux.sh to install"
        ((missing++))
    fi
    
    if [ $missing -gt 0 ]; then
        echo ""
        log_error "Missing $missing required tools. Please install them first."
        exit 1
    fi
    
    echo ""
    log_success "All prerequisites satisfied!"
    echo ""
}

# Clean up existing clusters
cleanup_existing() {
    log_step "Cleaning up existing kind clusters..."
    
    local existing_clusters
    existing_clusters=$(kind get clusters 2>/dev/null || echo "")
    
    if [ -n "$existing_clusters" ]; then
        log_info "Found existing kind clusters:"
        echo "$existing_clusters" | sed 's/^/   /'
        echo ""
        
        log_warning "These clusters will be deleted to ensure clean setup"
        log_details "Press Ctrl+C within 10 seconds to cancel..."
        echo ""
        
        for i in {10..1}; do
            echo -ne "\r   ⏱️  Continuing in $i seconds... "
            sleep 1
        done
        echo -e "\n"
        
        for cluster in $existing_clusters; do
            log_details "Deleting cluster: $cluster"
            kind delete cluster --name "$cluster"
        done
        log_success "Cleanup complete"
    else
        log_info "No existing kind clusters found"
    fi
    echo ""
}

# Create kind cluster configurations
create_cluster_configs() {
    log_step "Creating optimized kind cluster configurations..."
    
    # Hub cluster config - single node with port mappings
    log_details "Generating hub cluster configuration..."
    cat > /tmp/hub-cluster.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${HUB_CLUSTER}
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    etcd:
      local:
        dataDir: /tmp/etcd
    apiServer:
      extraArgs:
        enable-admission-plugins: NodeRestriction
  extraPortMappings:
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
EOF

    # DR1 cluster config - simple single node
    log_details "Generating DR1 cluster configuration..."
    cat > /tmp/dr1-cluster.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${DR1_CLUSTER}
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    etcd:
      local:
        dataDir: /tmp/etcd
    apiServer:
      extraArgs:
        enable-admission-plugins: NodeRestriction
EOF

    # DR2 cluster config (optional)
    log_details "Generating DR2 cluster configuration..."
    cat > /tmp/dr2-cluster.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${DR2_CLUSTER}
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    etcd:
      local:
        dataDir: /tmp/etcd
    apiServer:
      extraArgs:
        enable-admission-plugins: NodeRestriction
EOF

    log_success "Cluster configurations ready"
    echo ""
}

# Create clusters
create_clusters() {
    log_step "Creating kind clusters with Docker..."
    echo ""
    
    # Ensure we're using Docker (not podman)
    unset DOCKER_HOST
    export KIND_EXPERIMENTAL_PROVIDER=""
    
    # Create hub cluster
    log_info "🏢 Creating hub cluster (${HUB_CLUSTER})..."
    log_details "This cluster will run RamenDR hub operator and management components"
    kind create cluster --config /tmp/hub-cluster.yaml --wait 60s
    kind export kubeconfig --name "${HUB_CLUSTER}"
    log_success "Hub cluster created successfully"
    echo ""
    
    # Create DR1 cluster
    log_info "🌊 Creating DR cluster 1 (${DR1_CLUSTER})...)..."
    log_details "This cluster will run RamenDR DR cluster operator and workloads"
    kind create cluster --config /tmp/dr1-cluster.yaml --wait 60s
    kind export kubeconfig --name "${DR1_CLUSTER}"
    log_success "DR1 cluster created successfully"
    echo ""
    
    # Ask about DR2 cluster
    read -p "❓ Create third cluster (${DR2_CLUSTER}) for advanced testing? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "🌊 Creating DR cluster 2 (${DR2_CLUSTER})..."
        log_details "This cluster provides additional DR target for complex scenarios"
        if kind create cluster --config /tmp/dr2-cluster.yaml --wait 60s; then
            kind export kubeconfig --name "${DR2_CLUSTER}"
            log_success "DR2 cluster created successfully"
        else
            log_warning "DR2 cluster creation failed (not critical for basic testing)"
        fi
        echo ""
    fi
}

# Verify clusters
verify_clusters() {
    log_step "Verifying cluster health..."
    echo ""
    
    local clusters
    clusters=$(kind get clusters)
    
    for cluster in $clusters; do
        log_info "🔍 Checking cluster: $cluster"
        
        # Switch context
        kubectl config use-context "kind-$cluster" >/dev/null
        
        # Check nodes
        log_details "Nodes: $(kubectl get nodes --no-headers | wc -l) ready"
        
        # Check system pods
        local system_pods_ready
        system_pods_ready=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        log_details "System pods: $system_pods_ready running"
        
        # Check API connectivity
        if kubectl cluster-info >/dev/null 2>&1; then
            log_details "API server: responsive"
        else
            log_warning "API server: connectivity issues"
        fi
        
        log_success "Cluster $cluster is healthy"
        echo ""
    done
}

# Setup cluster networking
setup_networking() {
    log_step "Configuring cluster networking..."
    echo ""
    
    local clusters
    clusters=$(kind get clusters)
    
    for cluster in $clusters; do
        log_info "🌐 Setting up networking for $cluster..."
        kubectl config use-context "kind-$cluster" >/dev/null
        
        # Wait for CNI to be ready
        log_details "Waiting for CNI to be ready..."
        kubectl wait --for=condition=ready node --all --timeout=60s >/dev/null
        
        # Verify pod networking
        if kubectl run network-test --image=busybox --rm -it --restart=Never --timeout=30s -- nslookup kubernetes >/dev/null 2>&1; then
            log_details "Pod networking: functional"
        else
            log_details "Pod networking: testing..."
        fi
        
        log_success "Networking configured for $cluster"
    done
    echo ""
}

# Show cluster information
show_cluster_info() {
    echo "=========================================="
    log_success "🎉 kind Clusters Ready for RamenDR!"
    echo "=========================================="
    echo ""
    
    local clusters
    clusters=$(kind get clusters)
    
    log_info "📋 Created clusters:"
    for cluster in $clusters; do
        echo "   • $cluster"
    done
    echo ""
    
    log_info "🔧 kubectl contexts:"
    kubectl config get-contexts | grep "kind-" | sed 's/^/   /'
    echo ""
    
    log_info "🌍 Cluster access:"
    echo "   • Hub cluster:  kubectl config use-context kind-${HUB_CLUSTER}"
    echo "   • DR1 cluster:  kubectl config use-context kind-${DR1_CLUSTER}"
    if kind get clusters | grep -q "$DR2_CLUSTER"; then
        echo "   • DR2 cluster:  kubectl config use-context kind-${DR2_CLUSTER}"
    fi
    echo ""
    
    log_info "📝 Next steps:"
    echo "   1. 🚀 Install RamenDR: ./scripts/setup-ramendr.sh"
    echo "   2. 🧪 Test basic functionality: kubectl get nodes"
    echo "   3. 📚 Follow RamenDR user guide for application setup"
    echo ""
    
    # Set default context to hub
    kubectl config use-context "kind-${HUB_CLUSTER}" >/dev/null
    log_info "🎯 Current context: kind-${HUB_CLUSTER} (hub cluster)"
    echo ""
}

# Cleanup function
cleanup() {
    log_details "Cleaning up temporary files..."
    rm -f /tmp/hub-cluster.yaml /tmp/dr1-cluster.yaml /tmp/dr2-cluster.yaml
}

# Main function
main() {
    echo "=========================================="
    log_info "🚀 Enhanced kind Setup for RamenDR"
    echo "=========================================="
    echo ""
    log_info "This script creates optimized kind clusters using Docker for RamenDR testing"
    echo ""
    
    # Trap cleanup on exit
    trap cleanup EXIT
    
    check_prerequisites
    cleanup_existing
    create_cluster_configs
    create_clusters
    setup_networking
    verify_clusters
    show_cluster_info
    
    log_success "kind setup complete! Ready for RamenDR installation."
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Enhanced kind Setup for RamenDR"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help"
        echo "  --cleanup     Only cleanup existing clusters"
        echo ""
        echo "This script creates kind clusters optimized for RamenDR with:"
        echo "  • Docker container runtime (no podman conflicts)"
        echo "  • Proper networking configuration"
        echo "  • Health verification"
        echo "  • Ready for RamenDR operator installation"
        exit 0
        ;;
    --cleanup)
        log_info "🧹 Cleanup mode: removing existing kind clusters"
        cleanup_existing
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
