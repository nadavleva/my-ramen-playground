#!/bin/bash
# quick-install.sh - Automated RamenDR operator installation
# Based on README.md Quick Install section

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Check if kubectl is available and connected
check_kubectl() {
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "kubectl is not connected to a cluster"
        log_info "Please configure kubectl to connect to your Kubernetes cluster"
        exit 1
    fi
    
    local cluster_info=$(kubectl cluster-info | head -n1)
    log_success "Connected to: $cluster_info"
}

# Install Ramen Hub Operator
install_storage_dependencies() {
    log_info "Installing storage replication dependencies..."
    
    # Install VolumeReplication CRD
    log_info "Installing VolumeReplication CRD..."
    kubectl apply -f https://raw.githubusercontent.com/csi-addons/volume-replication-operator/main/config/crd/bases/replication.storage.openshift.io_volumereplications.yaml || log_warning "VolumeReplication CRD may already exist"
    kubectl apply -f https://raw.githubusercontent.com/csi-addons/volume-replication-operator/main/config/crd/bases/replication.storage.openshift.io_volumereplicationclasses.yaml || log_warning "VolumeReplicationClass CRD may already exist"
    
    # Install External Snapshotter (required by VolSync)
    log_info "Installing External Snapshotter..."
    kubectl apply -k "https://github.com/kubernetes-csi/external-snapshotter/config/crd?ref=v6.2.1" || log_warning "Snapshotter CRDs may already exist"
    kubectl apply -k "https://github.com/kubernetes-csi/external-snapshotter/deploy/kubernetes/snapshot-controller?ref=v6.2.1" || log_warning "Snapshot Controller may already exist"
    
    # Install VolSync using Helm
    log_info "Installing VolSync for storage replication..."
    helm repo add backube https://backube.github.io/helm-charts/ || log_warning "VolSync repo may already exist"
    helm repo update
    
    # Create volsync-system namespace if it doesn't exist
    kubectl create namespace volsync-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Install VolSync with timeout handling for development environments
    log_info "Installing VolSync (may timeout in kind/development environments)..."
    if helm upgrade --install volsync backube/volsync --namespace volsync-system --wait --timeout=5m; then
        log_success "VolSync installed successfully"
    else
        log_warning "VolSync installation timed out - this is common in kind/development environments"
        log_info "VolSync CRDs should still be available for basic testing"
        # Check if CRDs were installed even if deployment failed
        if kubectl get crd replicationsources.volsync.backube >/dev/null 2>&1; then
            log_info "✅ VolSync CRDs detected - basic functionality available"
        fi
    fi
    
    log_success "Storage dependencies installed successfully"
}

install_hub_operator() {
    log_info "Installing Ramen Hub Operator..."
    
    if kubectl get deployment -n ramen-system ramen-hub-operator >/dev/null 2>&1; then
        log_warning "Ramen Hub Operator already exists"
        read -p "Reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping hub operator installation"
            return
        fi
    fi
    
    # Install CRDs first
    log_info "Installing RamenDR CRDs..."
    make install
    
    # Build and load operator image
    log_info "Building RamenDR operator image..."
    make docker-build
    
    # Transfer image from podman to docker if needed
    if podman images | grep -q "ramen-operator"; then
        log_info "Transferring image from podman to docker..."
        podman save quay.io/ramendr/ramen-operator:latest | docker load
    fi
    
    # Load image into kind cluster
    log_info "Loading operator image into kind cluster..."
    kind load docker-image quay.io/ramendr/ramen-operator:latest --name ramen-hub
    
    # Switch to hub cluster context and deploy hub operator
    log_info "Deploying hub operator to ramen-hub cluster..."
    kubectl config use-context kind-ramen-hub
    make deploy-hub
    
    # Wait for deployment to be ready
    log_info "Waiting for hub operator to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/ramen-hub-operator -n ramen-system
    
    log_success "Ramen Hub Operator installed successfully"
}

# Install Ramen Cluster Operator
install_cluster_operator() {
    log_info "Installing Ramen Cluster Operator..."
    
    if kubectl get deployment -n ramen-system ramen-dr-cluster-operator >/dev/null 2>&1; then
        log_warning "Ramen Cluster Operator already exists"
        read -p "Reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping cluster operator installation"
            return
        fi
    fi
    
    # Install storage dependencies first (required for DR cluster operators)
    install_storage_dependencies
    
    # Ensure CRDs are installed (may have been done by hub operator)
    log_info "Ensuring RamenDR CRDs are installed..."
    make install
    
    # Build and load operator image if not already done
    if ! docker images | grep -q "quay.io/ramendr/ramen-operator"; then
        log_info "Building RamenDR operator image..."
        make docker-build
        
        # Transfer image from podman to docker if needed
        if podman images | grep -q "ramen-operator"; then
            log_info "Transferring image from podman to docker..."
            podman save quay.io/ramendr/ramen-operator:latest | docker load
        fi
    fi
    
    # Load image into DR clusters
    log_info "Loading operator image into DR clusters..."
    kind load docker-image quay.io/ramendr/ramen-operator:latest --name ramen-dr1
    kind load docker-image quay.io/ramendr/ramen-operator:latest --name ramen-dr2
    
    # Deploy cluster operators to both DR clusters in parallel
    log_info "Deploying cluster operators to both DR clusters in parallel..."
    
    # Start DR1 deployment in background
    (
        kubectl config use-context kind-ramen-dr1
        log_info "Installing storage dependencies on ramen-dr1..."
        install_storage_dependencies
        log_info "Starting deployment to ramen-dr1..."
        make deploy-dr-cluster
        log_info "DR1 deployment completed"
    ) &
    DR1_PID=$!
    
    # Start DR2 deployment in background  
    (
        kubectl config use-context kind-ramen-dr2
        log_info "Installing storage dependencies on ramen-dr2..."
        install_storage_dependencies
        log_info "Starting deployment to ramen-dr2..."
        make deploy-dr-cluster
        log_info "DR2 deployment completed"
    ) &
    DR2_PID=$!
    
    # Wait for both deployments to complete
    log_info "Waiting for both deployments to complete..."
    wait $DR1_PID
    wait $DR2_PID
    log_info "Both DR cluster deployments completed"
    
    # Wait for deployments to be ready on both DR clusters (also in parallel)
    log_info "Waiting for cluster operators to be ready..."
    
    # Check DR1 readiness in background
    (
        kubectl config use-context kind-ramen-dr1
        log_info "Checking ramen-dr1 cluster operator readiness..."
        kubectl wait --for=condition=available --timeout=300s deployment/ramen-dr-cluster-operator -n ramen-system
        log_info "DR1 operator is ready"
    ) &
    DR1_WAIT_PID=$!
    
    # Check DR2 readiness in background
    (
        kubectl config use-context kind-ramen-dr2
        log_info "Checking ramen-dr2 cluster operator readiness..."
        kubectl wait --for=condition=available --timeout=300s deployment/ramen-dr-cluster-operator -n ramen-system
        log_info "DR2 operator is ready"
    ) &
    DR2_WAIT_PID=$!
    
    # Wait for both readiness checks
    wait $DR1_WAIT_PID
    wait $DR2_WAIT_PID
    
    log_success "Ramen Cluster Operator installed successfully"
}

# Verify installation
verify_installation() {
    log_info "Verifying RamenDR installation..."
    
    # Check hub operator
    if kubectl get deployment -n ramen-system ramen-hub-operator >/dev/null 2>&1; then
        local hub_status=$(kubectl get deployment -n ramen-system ramen-hub-operator -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
        if [[ "$hub_status" == "True" ]]; then
            log_success "Hub operator: Running"
        else
            log_warning "Hub operator: Not ready"
        fi
    else
        log_error "Hub operator: Not found"
    fi
    
    # Check cluster operator  
    if kubectl get deployment -n ramen-system ramen-dr-cluster-operator >/dev/null 2>&1; then
        local cluster_status=$(kubectl get deployment -n ramen-system ramen-dr-cluster-operator -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
        if [[ "$cluster_status" == "True" ]]; then
            log_success "Cluster operator: Running"
        else
            log_warning "Cluster operator: Not ready"
        fi
    else
        log_error "Cluster operator: Not found"
    fi
    
    # Check CRDs
    local crds=(
        "drpolicies.ramendr.openshift.io"
        "drplacementcontrols.ramendr.openshift.io"
        "volumereplicationgroups.ramendr.openshift.io"
        "drclusters.ramendr.openshift.io"
    )
    
    for crd in "${crds[@]}"; do
        if kubectl get crd "$crd" >/dev/null 2>&1; then
            log_success "CRD: $crd"
        else
            log_error "CRD: $crd (missing)"
        fi
    done
    
    # Show pods
    echo ""
    log_info "RamenDR pods:"
    kubectl get pods -n ramen-system -l "app.kubernetes.io/part-of=ramen"
}

# Create sample DRPolicy
create_sample_policy() {
    read -p "Create a sample DRPolicy? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    log_info "Creating sample DRPolicy..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRPolicy
metadata:
  name: sample-dr-policy
spec:
  drClusters:
  - cluster1
  - cluster2
  schedulingInterval: 5m
  replicationClassSelector:
    matchLabels:
      ramen.io/replicationClass: "rbd"
  volumeSnapshotClassSelector:
    matchLabels:
      ramen.io/volumeSnapshotClass: "csi-rbdplugin-snapclass"
EOF
    
    log_success "Sample DRPolicy created"
    kubectl get drpolicy sample-dr-policy -o wide
}

# Show next steps
show_next_steps() {
    echo ""
    log_success "🎉 RamenDR installation complete!"
    echo ""
    log_info "📝 Next steps:"
    echo "   1. Configure storage replication (Ceph RBD, VolSync, etc.)"
    echo "   2. Create DRPolicy resources for your clusters"
    echo "   3. Create DRPlacementControl to protect applications"
    echo "   4. Test DR workflows (failover/relocate)"
    echo ""
    log_info "📚 Documentation:"
    echo "   - User Guide: docs/usage.md"
    echo "   - Configuration: docs/configure.md"
    echo "   - Examples: examples/"
    echo ""
    log_info "🔧 Useful commands:"
    echo "   kubectl get drpolicy"
    echo "   kubectl get drplacementcontrol"
    echo "   kubectl get volumereplicationgroup"
    echo "   kubectl logs -n ramen-system -l app.kubernetes.io/name=ramen-hub-operator"
}

# Main installation function
main() {
    log_info "🚀 Starting automated RamenDR installation..."
    
    # Determine installation type
    echo "Select installation type:"
    echo "  1) Hub only (for hub cluster)"
    echo "  2) Cluster only (for managed cluster)"
    echo "  3) Both (for single cluster or testing)"
    echo ""
    read -p "Enter choice (1-3): " choice
    
    case $choice in
        1)
            check_kubectl
            install_hub_operator
            ;;
        2)
            check_kubectl
            install_cluster_operator
            ;;
        3)
            check_kubectl
            install_hub_operator
            install_cluster_operator
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
    
    verify_installation
    create_sample_policy
    show_next_steps
}

# Handle script arguments
case "${1:-}" in
    --hub)
        check_kubectl
        install_hub_operator
        verify_installation
        ;;
    --cluster)
        check_kubectl
        install_cluster_operator
        verify_installation
        ;;
    --both)
        check_kubectl
        install_hub_operator
        install_cluster_operator
        verify_installation
        ;;
    --help|-h)
        echo "Usage: $0 [--hub|--cluster|--both|--help]"
        echo ""
        echo "Options:"
        echo "  --hub     Install hub operator only"
        echo "  --cluster Install cluster operator only"
        echo "  --both    Install both operators"
        echo "  --help    Show this help"
        echo ""
        echo "Interactive mode if no options provided"
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
