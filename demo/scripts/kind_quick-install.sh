#!/bin/bash
# quick-install.sh - Automated RamenDR operator installation
# Based on README.md Quick Install section

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Source common logging functions
source "$SCRIPT_DIR/utils.sh"

# Check KUBECONFIG and kubectl before starting
check_kubeconfig_for_kind
check_kubectl

# Helper function to apply resources with fallback and continue on errors
apply_with_fallback() {
    local description="$1"
    local local_path="$2"
    local fallback_url="$3"
    local continue_on_error="${4:-true}"
    
    log_info "Installing $description..."
    
    # Try local path first
    if [[ -n "$local_path" && -f "$local_path" ]]; then
        log_info "Using local file: $local_path"
        if kubectl apply -f "$local_path" 2>/dev/null; then
            log_success "$description installed successfully (local)"
            return 0
        else
            log_warning "Failed to apply local file: $local_path"
        fi
    elif [[ -n "$local_path" ]]; then
        log_info "Using local kustomization: $local_path"
        if kubectl apply -k "$local_path" 2>/dev/null; then
            log_success "$description installed successfully (local kustomization)"
            return 0
        else
            log_warning "Failed to apply local kustomization: $local_path"
        fi
    fi
    
    # Try fallback URL if provided
    if [[ -n "$fallback_url" ]]; then
        log_info "Trying fallback URL: $fallback_url"
        if kubectl apply -f "$fallback_url" 2>/dev/null; then
            log_success "$description installed successfully (remote)"
            return 0
        else
            log_error "Failed to apply from URL: $fallback_url"
        fi
    fi
    
    # Log final status
    if [[ "$continue_on_error" == "true" ]]; then
        log_warning "$description installation failed - continuing with other components"
        return 1
    else
        log_error "$description installation failed - this may cause issues"
        return 1
    fi
}

# Install storage dependencies (improved version with local files and better error handling)
install_storage_dependencies() {
    log_info "Installing storage replication dependencies..."
    
    # Define local paths relative to script directory  
    local storage_deps_dir="$SCRIPT_DIR/../yaml/storage-dependencies"
    local failed_operations=0
    
    # Install CRDs first using local files with fallback
    log_info "Installing storage-related CRDs..."
    if ! apply_with_fallback "Storage CRDs" "$storage_deps_dir/crds" ""; then
        ((failed_operations++))
    fi
    
    # Install Snapshot Controllers using local files with fallback  
    log_info "Installing Snapshot Controllers..."
    if ! apply_with_fallback "Snapshot Controllers" "$storage_deps_dir/controllers" ""; then
        ((failed_operations++))
    fi
    
    # Fallback: Try individual external URLs if local kustomization failed
    if [[ $failed_operations -gt 0 ]]; then
        log_info "Some local installations failed, trying individual external resources..."
        
        # VolumeReplication CRDs
        apply_with_fallback "VolumeReplication CRD" "" "https://raw.githubusercontent.com/csi-addons/volume-replication-operator/main/config/crd/bases/replication.storage.openshift.io_volumereplications.yaml"
        apply_with_fallback "VolumeReplicationClass CRD" "" "https://raw.githubusercontent.com/csi-addons/volume-replication-operator/main/config/crd/bases/replication.storage.openshift.io_volumereplicationclasses.yaml"
        
        # Snapshot CRDs
        apply_with_fallback "VolumeSnapshotClass CRD" "" "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml"
        apply_with_fallback "VolumeSnapshot CRD" "" "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml"
        apply_with_fallback "VolumeSnapshotContent CRD" "" "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml"
        
        # Snapshot Controller
        apply_with_fallback "Snapshot Controller RBAC" "" "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml"
        apply_with_fallback "Snapshot Controller" "" "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml"
    fi
    
    # Install VolSync using Helm (continue even if it fails)
    log_info "Installing VolSync for storage replication..."
    if helm repo add backube https://backube.github.io/helm-charts/ 2>/dev/null; then
        log_success "VolSync repo added successfully"
    else
        log_warning "VolSync repo may already exist or failed to add"
    fi
    
    if helm repo update 2>/dev/null; then
        log_success "Helm repos updated successfully"
    else
        log_warning "Helm repo update failed - continuing anyway"
    fi
    
    # Create volsync-system namespace if it doesn't exist
    if kubectl create namespace volsync-system --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null; then
        log_success "volsync-system namespace ready"
    else
        log_warning "Failed to create volsync-system namespace - may already exist"
    fi
    
    # Install VolSync with timeout handling for development environments
    log_info "Installing VolSync (may timeout in kind/development environments)..."
    if helm upgrade --install volsync backube/volsync --namespace volsync-system --wait --timeout=5m 2>/dev/null; then
        log_success "VolSync installed successfully"
    else
        log_warning "VolSync installation timed out or failed - this is common in kind/development environments"
        log_info "VolSync CRDs should still be available for basic testing"
        # Check if CRDs were installed even if deployment failed
        if kubectl get crd replicationsources.volsync.backube >/dev/null 2>&1; then
            log_info "✅ VolSync CRDs detected - basic functionality available"
        fi
    fi
    
    # Install demo resource classes using local files with inline fallback
    log_info "Installing demo resource classes for VRG selectors..."
    if ! apply_with_fallback "Demo Resource Classes" "$storage_deps_dir/resource-classes" ""; then
        log_info "Local resource classes failed, creating inline..."
        
        # Create VolumeSnapshotClass (required for VRG selectors)
        log_info "Creating VolumeSnapshotClass for kind clusters..."
        if kubectl apply -f - <<EOF 2>/dev/null
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: demo-snapclass
  labels:
    app.kubernetes.io/name: ramen-demo
    velero.io/csi-volumesnapshot-class: "true"
driver: hostpath.csi.k8s.io
deletionPolicy: Delete
EOF
        then
            log_success "VolumeSnapshotClass created successfully"
        else
            log_warning "VolumeSnapshotClass creation failed - may already exist"
        fi
        
        # Create VolumeReplicationClass (required for VRG selectors)
        log_info "Creating VolumeReplicationClass for VolSync replication..."
        if kubectl apply -f - <<EOF 2>/dev/null
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplicationClass
metadata:
  name: demo-replication-class
  labels:
    app.kubernetes.io/name: ramen-demo
    ramendr.openshift.io/replicationID: ramen-volsync
spec:
  provisioner: hostpath.csi.k8s.io
  parameters:
    copyMethod: Snapshot
EOF
        then
            log_success "VolumeReplicationClass created successfully"
        else
            log_warning "VolumeReplicationClass creation failed - may already exist"
        fi
    fi
    
    # Verify installation
    log_info "Verifying storage dependencies installation..."
    
    # Check demo resource classes
    if kubectl get volumesnapshotclass demo-snapclass >/dev/null 2>&1; then
        log_success "VolumeSnapshotClass 'demo-snapclass' available"
    else
        log_warning "VolumeSnapshotClass 'demo-snapclass' not found"
    fi
    
    if kubectl get volumereplicationclass demo-replication-class >/dev/null 2>&1; then
        log_success "VolumeReplicationClass 'demo-replication-class' available"
    else
        log_warning "VolumeReplicationClass 'demo-replication-class' not found"
    fi
    
    # Check critical CRDs
    local crds_to_check=(
        "volumesnapshots.snapshot.storage.k8s.io"
        "volumesnapshotclasses.snapshot.storage.k8s.io" 
        "volumesnapshotcontents.snapshot.storage.k8s.io"
        "volumereplications.replication.storage.openshift.io"
        "volumereplicationclasses.replication.storage.openshift.io"
        "volumegroupreplications.replication.storage.openshift.io"
        "volumegroupreplicationclasses.replication.storage.openshift.io"
        "volumegroupsnapshotclasses.groupsnapshot.storage.openshift.io"
        "networkfenceclasses.csiaddons.openshift.io"
    )
    
    local missing_crds=0
    for crd in "${crds_to_check[@]}"; do
        if kubectl get crd "$crd" >/dev/null 2>&1; then
            log_success "CRD '$crd' available"
        else
            log_warning "CRD '$crd' not found"
            ((missing_crds++))
        fi
    done
    
    if [[ $missing_crds -eq 0 ]]; then
        log_success "All required CRDs and resource classes installed successfully"
    else
        log_warning "$missing_crds CRDs are missing - some functionality may be limited"
        log_info "This is normal for development environments - operators should still function"
    fi
    
    log_success "Storage dependencies installation completed (errors are non-fatal)"
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
    
    # Wait for namespace to exist first (with timeout)
    local namespace_timeout=60  # 60 seconds timeout
    local elapsed=0
    while ! kubectl get namespace ramen-system >/dev/null 2>&1; do
        if [ $elapsed -ge $namespace_timeout ]; then
            log_error "Timeout waiting for ramen-system namespace to be created"
            return 1
        fi
        log_info "Waiting for ramen-system namespace to be created..."
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
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
        log_info "🔧 DR1: Switching to kind-ramen-dr1 context..."
        kubectl config use-context kind-ramen-dr1
        if ! kubectl get nodes >/dev/null 2>&1; then
            log_error "❌ DR1: Cannot connect to kind-ramen-dr1 cluster!"
            exit 1
        fi
        log_info "✅ DR1: Connected to cluster successfully"
        
        log_info "🔧 DR1: Installing storage dependencies..."
        install_storage_dependencies
        
        log_info "🔧 DR1: Starting deployment to ramen-dr1..."
        if ! make deploy-dr-cluster; then
            log_error "❌ DR1: make deploy-dr-cluster failed!"
            exit 1
        fi
        log_success "✅ DR1: Deployment completed successfully"
    ) &
    DR1_PID=$!
    
    # Start DR2 deployment in background  
    (
        log_info "🔧 DR2: Switching to kind-ramen-dr2 context..."
        kubectl config use-context kind-ramen-dr2
        if ! kubectl get nodes >/dev/null 2>&1; then
            log_error "❌ DR2: Cannot connect to kind-ramen-dr2 cluster!"
            exit 1
        fi
        log_info "✅ DR2: Connected to cluster successfully"
        
        log_info "🔧 DR2: Installing storage dependencies..."
        install_storage_dependencies
        
        log_info "🔧 DR2: Starting deployment to ramen-dr2..."
        if ! make deploy-dr-cluster; then
            log_error "❌ DR2: make deploy-dr-cluster failed!"
            exit 1
        fi
        log_success "✅ DR2: Deployment completed successfully"
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
        
        # Wait for namespace to exist first (with timeout)
        local namespace_timeout=60
        local elapsed=0
        while ! kubectl get namespace ramen-system >/dev/null 2>&1; do
            if [ $elapsed -ge $namespace_timeout ]; then
                log_error "Timeout waiting for ramen-system namespace on ramen-dr1"
                exit 1
            fi
            log_info "Waiting for ramen-system namespace to be created on ramen-dr1..."
            sleep 2
            elapsed=$((elapsed + 2))
        done
        
        kubectl wait --for=condition=available --timeout=300s deployment/ramen-dr-cluster-operator -n ramen-system
        log_info "DR1 operator is ready"
    ) &
    DR1_WAIT_PID=$!
    
    # Check DR2 readiness in background
    (
        kubectl config use-context kind-ramen-dr2
        log_info "Checking ramen-dr2 cluster operator readiness..."
        
        # Wait for namespace to exist first (with timeout)
        local namespace_timeout=60
        local elapsed=0
        while ! kubectl get namespace ramen-system >/dev/null 2>&1; do
            if [ $elapsed -ge $namespace_timeout ]; then
                log_error "Timeout waiting for ramen-system namespace on ramen-dr2"
                exit 1
            fi
            log_info "Waiting for ramen-system namespace to be created on ramen-dr2..."
            sleep 2
            elapsed=$((elapsed + 2))
        done
        
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
    
    # Check hub operator (on hub cluster)
    if kubectl get deployment -n ramen-system ramen-hub-operator --context=kind-ramen-hub >/dev/null 2>&1; then
        local hub_status=$(kubectl get deployment -n ramen-system ramen-hub-operator --context=kind-ramen-hub -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
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
    # Hub-specific CRDs (check on hub cluster)
    local hub_crds=(
        "drpolicies.ramendr.openshift.io"
        "drplacementcontrols.ramendr.openshift.io"
        "drclusters.ramendr.openshift.io"
    )
    
    for crd in "${hub_crds[@]}"; do
        if kubectl get crd "$crd" --context=kind-ramen-hub >/dev/null 2>&1; then
            log_success "CRD: $crd"
        else
            log_error "CRD: $crd (missing)"
        fi
    done
    
    # Cluster-specific CRDs (check on current cluster)
    local cluster_crds=(
        "volumereplicationgroups.ramendr.openshift.io"
    )
    
    for crd in "${cluster_crds[@]}"; do
        if kubectl get crd "$crd" >/dev/null 2>&1; then
            log_success "CRD: $crd"
        else
            log_error "CRD: $crd (missing)"
        fi
    done
    
    # Show pods
    echo ""
    log_info "RamenDR pods:"
    echo "Hub cluster (kind-ramen-hub):"
    kubectl get pods -n ramen-system -l "app.kubernetes.io/part-of=ramen" --context=kind-ramen-hub 2>/dev/null || echo "  No RamenDR pods found"
    echo "Current cluster ($(kubectl config current-context)):"
    kubectl get pods -n ramen-system -l "app.kubernetes.io/part-of=ramen" 2>/dev/null || echo "  No RamenDR pods found"

    log_success "RamenDR installation verification complete"
}

# Create sample DRPolicy
create_sample_policy() {
    read -p "Create a sample DRPolicy? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    log_info "Creating sample DRPolicy..."
    
    cat <<EOF | kubectl apply --context=kind-ramen-hub -f -
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
    kubectl get drpolicy sample-dr-policy --context=kind-ramen-hub -o wide
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

# Install on all clusters (hub + both DR clusters)
install_all_clusters() {
    log_info "🌐 Installing RamenDR operators on all clusters..."
    
    # Check that all kind contexts exist
    local required_contexts=("kind-ramen-hub" "kind-ramen-dr1" "kind-ramen-dr2")
    for context in "${required_contexts[@]}"; do
        if ! kubectl config get-contexts -o name | grep -q "^${context}$"; then
            log_error "Required context '${context}' not found. Please ensure all kind clusters are created."
            log_info "Run: ./scripts/setup.sh kind"
            exit 1
        fi
    done
    
    log_info "✅ All required contexts found: ${required_contexts[*]}"
    
    # Install hub operator first
    log_step "Installing Hub Operator on kind-ramen-hub..."
    kubectl config use-context kind-ramen-hub
    install_hub_operator
    
    # Install DR cluster operators on both DR clusters
    log_step "Installing DR Cluster Operators on both DR clusters..."
    install_cluster_operator
    
    log_success "🎉 Multi-cluster installation completed!"
    log_info "Hub operator: kind-ramen-hub"
    log_info "DR operators: kind-ramen-dr1, kind-ramen-dr2"
}

# Main installation function
main() {
    log_info "🚀 Starting automated RamenDR installation..."
    
    # Determine installation type
    echo "Select installation type:"
    echo "  1) Hub only (for hub cluster)"
    echo "  2) Cluster only (for managed cluster)"
    echo "  3) All clusters (automated multi-cluster setup)"
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
            install_all_clusters
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
