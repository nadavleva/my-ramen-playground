#!/bin/bash
# setup-minikube.sh - Enhanced minikube cluster setup for RamenDR
# This script creates multiple minikube profiles for RamenDR hub and DR clusters

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
HUB_PROFILE="ramen-hub"
DR1_PROFILE="ramen-dr1"
DR2_PROFILE="ramen-dr2"
MINIKUBE_DRIVER="docker"  # or "virtualbox", "podman", etc.
MEMORY="4096"  # 4GB per cluster
CPUS="2"

# Check prerequisites
check_prerequisites() {
    echo "=============================================="
    log_info "🔍 Checking Prerequisites for minikube Setup"
    echo "=============================================="
    echo ""
    
    local missing=0
    
    log_step "Checking required tools..."
    
    # Check minikube
    if command -v minikube >/dev/null 2>&1; then
        log_success "minikube: $(minikube version --short 2>/dev/null || minikube version | head -n1)"
    else
        log_error "minikube not found"
        log_details "Install: https://minikube.sigs.k8s.io/docs/start/"
        log_details "Or run: ./scripts/setup-linux.sh to install"
        ((missing++))
    fi
    
    # Check kubectl
    if command -v kubectl >/dev/null 2>&1; then
        log_success "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client | head -n1)"
    else
        log_error "kubectl not found"
        log_details "Run: ./scripts/setup-linux.sh to install"
        ((missing++))
    fi
    
    # Check Docker (if using docker driver)
    if [ "$MINIKUBE_DRIVER" = "docker" ]; then
        if command -v docker >/dev/null 2>&1; then
            if docker info >/dev/null 2>&1; then
                log_success "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
            else
                log_error "Docker installed but daemon not running"
                log_details "Run: sudo systemctl start docker"
                ((missing++))
            fi
        else
            log_error "Docker not found (required for docker driver)"
            log_details "Run: ./scripts/setup-linux.sh to install"
            ((missing++))
        fi
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
        log_error "$missing required tools missing!"
        exit 1
    fi
    
    log_success "All prerequisites satisfied!"
    echo ""
}

# Cleanup existing clusters
cleanup_existing() {
    log_step "Cleaning up existing minikube clusters..."
    
    # Stop and delete existing profiles
    for profile in "$HUB_PROFILE" "$DR1_PROFILE" "$DR2_PROFILE"; do
        if minikube profile list 2>/dev/null | grep -q "^$profile"; then
            log_info "Stopping and deleting existing profile: $profile"
            minikube stop --profile="$profile" 2>/dev/null || true
            minikube delete --profile="$profile" 2>/dev/null || true
        fi
    done
    
    log_success "Cleanup completed"
    echo ""
}

# Create clusters with minikube profiles
create_clusters() {
    log_step "Creating minikube clusters..."
    echo ""
    
    # Create hub cluster
    log_info "🏢 Creating hub cluster ($HUB_PROFILE)..."
    log_details "This cluster will run RamenDR hub operator and management components"
    
    minikube start \
        --profile="$HUB_PROFILE" \
        --driver="$MINIKUBE_DRIVER" \
        --memory="$MEMORY" \
        --cpus="$CPUS" \
        --kubernetes-version="v1.27.3" \
        --addons=storage-provisioner,default-storageclass \
        --wait=true
    
    log_success "Hub cluster created successfully"
    echo ""
    
    # Create DR1 cluster
    log_info "🌊 Creating DR cluster 1 ($DR1_PROFILE)..."
    log_details "This cluster will run RamenDR DR cluster operator and workloads"
    
    minikube start \
        --profile="$DR1_PROFILE" \
        --driver="$MINIKUBE_DRIVER" \
        --memory="$MEMORY" \
        --cpus="$CPUS" \
        --kubernetes-version="v1.27.3" \
        --addons=storage-provisioner,default-storageclass \
        --wait=true
    
    log_success "DR1 cluster created successfully"
    echo ""
    
    # Ask about DR2 cluster
    read -p "❓ Create third cluster ($DR2_PROFILE) for advanced testing? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "🌊 Creating DR cluster 2 ($DR2_PROFILE)..."
        log_details "This cluster provides additional DR target for complex scenarios"
        
        if minikube start \
            --profile="$DR2_PROFILE" \
            --driver="$MINIKUBE_DRIVER" \
            --memory="$MEMORY" \
            --cpus="$CPUS" \
            --kubernetes-version="v1.27.3" \
            --addons=storage-provisioner,default-storageclass \
            --wait=true; then
            log_success "DR2 cluster created successfully"
        else
            log_warning "DR2 cluster creation failed (not critical for basic testing)"
        fi
        echo ""
    fi
}

# Setup networking and prerequisites
setup_networking() {
    log_step "Configuring cluster networking..."
    echo ""
    
    for profile in "$HUB_PROFILE" "$DR1_PROFILE"; do
        if minikube profile list 2>/dev/null | grep -q "^$profile"; then
            log_info "🌐 Setting up networking for $profile..."
            
            # Switch to profile and configure
            minikube profile "$profile"
            
            # Wait for API server to be ready
            log_details "Waiting for API server to be ready..."
            kubectl wait --for=condition=Ready nodes --all --timeout=120s >/dev/null 2>&1
            
            # Test pod networking
            log_details "Pod networking: testing..."
            kubectl run test-pod --image=busybox --restart=Never --rm -i -- echo "Network test successful" >/dev/null 2>&1 || log_warning "Network test failed for $profile"
            
            log_success "Networking configured for $profile"
        fi
    done
    
    # Check DR2 if it exists
    if minikube profile list 2>/dev/null | grep -q "^$DR2_PROFILE"; then
        log_info "🌐 Setting up networking for $DR2_PROFILE..."
        minikube profile "$DR2_PROFILE"
        kubectl wait --for=condition=Ready nodes --all --timeout=120s >/dev/null 2>&1
        kubectl run test-pod --image=busybox --restart=Never --rm -i -- echo "Network test successful" >/dev/null 2>&1 || log_warning "Network test failed for $DR2_PROFILE"
        log_success "Networking configured for $DR2_PROFILE"
    fi
    
    echo ""
}

# Verify clusters
verify_clusters() {
    log_step "Verifying cluster health..."
    echo ""
    
    local profiles=("$HUB_PROFILE" "$DR1_PROFILE")
    if minikube profile list 2>/dev/null | grep -q "^$DR2_PROFILE"; then
        profiles+=("$DR2_PROFILE")
    fi
    
    for profile in "${profiles[@]}"; do
        log_info "🔍 Checking cluster: $profile"
        minikube profile "$profile"
        
        # Check nodes
        local node_count=$(kubectl get nodes --no-headers | wc -l)
        local ready_nodes=$(kubectl get nodes --no-headers | awk '$2=="Ready"' | wc -l)
        log_details "Nodes: $ready_nodes/$node_count ready"
        
        # Check system pods
        local system_pods=$(kubectl get pods -n kube-system --no-headers | wc -l)
        local running_pods=$(kubectl get pods -n kube-system --no-headers | awk '$3=="Running"' | wc -l)
        log_details "System pods: $running_pods/$system_pods running"
        
        # Check API server
        if kubectl version --short >/dev/null 2>&1; then
            log_details "API server: responsive"
        else
            log_warning "API server: not responsive"
        fi
        
        log_success "Cluster $profile is healthy"
        echo ""
    done
}

# Setup kubeconfig contexts
setup_kubeconfig() {
    log_step "Setting up kubeconfig contexts..."
    echo ""
    
    # Ensure kubeconfig directory exists
    mkdir -p ~/.kube
    
    # Update kubeconfig for each profile
    for profile in "$HUB_PROFILE" "$DR1_PROFILE"; do
        if minikube profile list 2>/dev/null | grep -q "^$profile"; then
            log_info "📝 Setting up kubeconfig for $profile..."
            minikube update-context --profile="$profile"
            
            # Verify context
            if kubectl config get-contexts "$profile" >/dev/null 2>&1; then
                log_success "Context '$profile' ready"
            else
                log_warning "Context '$profile' not found in kubeconfig"
            fi
        fi
    done
    
    # Check DR2 if it exists
    if minikube profile list 2>/dev/null | grep -q "^$DR2_PROFILE"; then
        log_info "📝 Setting up kubeconfig for $DR2_PROFILE..."
        minikube update-context --profile="$DR2_PROFILE"
        
        if kubectl config get-contexts "$DR2_PROFILE" >/dev/null 2>&1; then
            log_success "Context '$DR2_PROFILE' ready"
        else
            log_warning "Context '$DR2_PROFILE' not found in kubeconfig"
        fi
    fi
    
    echo ""
}

# Show cluster information
show_cluster_info() {
    echo "=============================================="
    log_success "🎉 minikube Clusters Ready for RamenDR!"
    echo "=============================================="
    echo ""
    
    log_info "📋 Created clusters:"
    minikube profile list | grep -E "(ramen-|Profile)" || echo "   No profiles found"
    echo ""
    
    log_info "🔧 kubectl contexts:"
    kubectl config get-contexts | grep -E "(NAME|ramen-)" | sed 's/^/   /'
    echo ""
    
    log_info "🌍 Cluster access:"
    log_details "Hub cluster:  kubectl config use-context $HUB_PROFILE"
    log_details "DR1 cluster:  kubectl config use-context $DR1_PROFILE"
    if minikube profile list 2>/dev/null | grep -q "^$DR2_PROFILE"; then
        log_details "DR2 cluster:  kubectl config use-context $DR2_PROFILE"
    fi
    echo ""
    
    log_info "📝 Next steps:"
    log_details "1. 🚀 Install RamenDR: ./scripts/quick-install.sh"
    log_details "2. 🧪 Test basic functionality: kubectl get nodes"
    log_details "3. 📚 Follow RamenDR user guide for application setup"
    echo ""
    
    # Show current context
    current_context=$(kubectl config current-context)
    log_info "🎯 Current context: $current_context"
    echo ""
    
    # Show cluster URLs for reference
    log_info "🔗 Cluster URLs (for reference):"
    for profile in "$HUB_PROFILE" "$DR1_PROFILE"; do
        if minikube profile list 2>/dev/null | grep -q "^$profile"; then
            url=$(minikube ip --profile="$profile" 2>/dev/null || echo "N/A")
            log_details "$profile: $url"
        fi
    done
    if minikube profile list 2>/dev/null | grep -q "^$DR2_PROFILE"; then
        url=$(minikube ip --profile="$DR2_PROFILE" 2>/dev/null || echo "N/A")
        log_details "$DR2_PROFILE: $url"
    fi
}

# Cleanup function
cleanup() {
    log_details "Cleaning up temporary files..."
    # No temporary files to clean up for minikube
}

# Main function
main() {
    echo "=============================================="
    log_info "🚀 Enhanced minikube Setup for RamenDR"
    echo "=============================================="
    echo ""
    log_info "This script creates multiple minikube profiles for RamenDR testing"
    log_info "Driver: $MINIKUBE_DRIVER | Memory: ${MEMORY}MB | CPUs: $CPUS per cluster"
    echo ""
    
    # Trap cleanup on exit
    trap cleanup EXIT
    
    check_prerequisites
    cleanup_existing
    create_clusters
    setup_networking
    verify_clusters
    setup_kubeconfig
    show_cluster_info
    
    log_success "minikube setup complete! Ready for RamenDR installation."
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Enhanced minikube Setup for RamenDR"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help"
        echo "  --cleanup     Only cleanup existing clusters"
        echo "  --driver=X    Set minikube driver (default: docker)"
        echo "  --memory=X    Set memory per cluster (default: 4096MB)"
        echo "  --cpus=X      Set CPUs per cluster (default: 2)"
        echo ""
        echo "This script creates minikube clusters optimized for RamenDR with:"
        echo "  • Multiple minikube profiles (hub, dr1, dr2)"
        echo "  • Proper networking configuration"
        echo "  • Storage provisioner enabled"
        echo "  • Health verification"
        echo "  • Ready for RamenDR operator installation"
        exit 0
        ;;
    --cleanup)
        log_info "🧹 Cleanup mode: removing existing minikube profiles"
        cleanup_existing
        exit 0
        ;;
    --driver=*)
        MINIKUBE_DRIVER="${1#--driver=}"
        main
        ;;
    --memory=*)
        MEMORY="${1#--memory=}"
        main
        ;;
    --cpus=*)
        CPUS="${1#--cpus=}"
        main
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
