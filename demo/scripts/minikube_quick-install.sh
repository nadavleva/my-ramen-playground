#!/bin/bash
# quick-install-minikube.sh - Automated RamenDR operator installation for minikube
# Based on quick-install.sh but adapted for minikube contexts

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Source common logging functions
source "$SCRIPT_DIR/utils.sh"

# Check KUBECONFIG and kubectl for minikube
check_kubeconfig_for_minikube() {
    if [ -z "${KUBECONFIG:-}" ]; then
        export KUBECONFIG=~/.kube/config
        log_info "KUBECONFIG set to default: ~/.kube/config"
    fi
    
    # Create .kube directory if it doesn't exist
    mkdir -p ~/.kube
    
    # Check for minikube contexts
    local minikube_contexts=$(kubectl config get-contexts -o name 2>/dev/null | grep "^ramen-" | wc -l)
    if [ "$minikube_contexts" -eq 0 ]; then
        log_error "No minikube contexts found"
        log_info "Run: ./scripts/setup-minikube.sh first"
        exit 1
    fi
    
    log_success "Found $minikube_contexts minikube contexts"
}

# Check prerequisites
check_kubeconfig_for_minikube
check_kubectl

# # Install storage dependencies (same as original)
# install_storage_dependencies() {
#     log_info "Installing storage replication dependencies..."
    
#     # Install VolumeReplication CRDs (including missing VolumeGroup CRDs)
#     log_info "Installing VolumeReplication CRDs..."
#     kubectl apply -f https://raw.githubusercontent.com/csi-addons/volume-replication-operator/main/config/crd/bases/replication.storage.openshift.io_volumereplications.yaml || log_warning "VolumeReplication CRD may already exist"
#     kubectl apply -f https://raw.githubusercontent.com/csi-addons/volume-replication-operator/main/config/crd/bases/replication.storage.openshift.io_volumereplicationclasses.yaml || log_warning "VolumeReplicationClass CRD may already exist"
    
#     # Install missing VolumeGroup CRDs that operators expect
#     log_info "Installing VolumeGroup CRDs..."
#     kubectl apply -f https://raw.githubusercontent.com/csi-addons/volume-replication-operator/main/config/crd/bases/replication.storage.openshift.io_volumegroupreplications.yaml || log_warning "VolumeGroupReplication CRD may already exist"
#     kubectl apply -f https://raw.githubusercontent.com/csi-addons/volume-replication-operator/main/config/crd/bases/replication.storage.openshift.io_volumegroupreplicationclasses.yaml || log_warning "VolumeGroupReplicationClass CRD may already exist"
    
#     # Install External Snapshotter (required by VolSync)
#     log_info "Installing External Snapshotter..."
    
#     # Install Snapshotter CRDs (using direct YAML files for reliability)
#     log_info "Installing Snapshotter CRDs..."
#     kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml || log_warning "VolumeSnapshotClass CRD may already exist"
#     kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml || log_warning "VolumeSnapshot CRD may already exist"
#     kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml || log_warning "VolumeSnapshotContent CRD may already exist"
    
#     # Install Snapshot Controller (using direct YAML files for reliability)
#     log_info "Installing Snapshot Controller..."
#     kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml || log_warning "Snapshot Controller RBAC may already exist"
#     kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml || log_warning "Snapshot Controller may already exist"
    
#     # Install VolSync using Helm
#     log_info "Installing VolSync for storage replication..."
#     helm repo add backube https://backube.github.io/helm-charts/ || log_warning "VolSync repo may already exist"
#     helm repo update
    
#     # Create volsync-system namespace if it doesn't exist
#     kubectl create namespace volsync-system --dry-run=client -o yaml | kubectl apply -f -
    
#     # Install VolSync with timeout handling for development environments
#     log_info "Installing VolSync (may timeout in minikube environments)..."
#     if helm upgrade --install volsync backube/volsync --namespace volsync-system --wait --timeout=5m; then
#         log_success "VolSync installed successfully"
#     else
#         log_warning "VolSync installation may have timed out (common in development)"
#         log_info "VolSync may still be installing in the background"
#     fi
# }

# Function to check if a CRD exists
crd_exists() {
    local crd_name="$1"
    kubectl get crd "$crd_name" >/dev/null 2>&1
    return $?
}

# Function to install a CRD only if it doesn't exist
install_crd_if_missing() {
    local crd_name="$1"
    local display_name="$2"
    local yaml_content="$3"
    
    if crd_exists "$crd_name"; then
        log_info "✅ $display_name CRD already exists, skipping"
        return 0
    fi
    
    log_info "Installing $display_name CRD..."
    if echo "$yaml_content" | kubectl apply -f -; then
        log_success "✅ $display_name CRD installed successfully"
        return 0
    else
        log_error "❌ Failed to install $display_name CRD"
        return 1
    fi
}

install_storage_dependencies() {
    log_info "Installing storage dependencies..."
    
    # Use dedicated storage dependencies script
    if [ -f "$SCRIPT_DIR/install-storage-dependencies.sh" ]; then
        "$SCRIPT_DIR/install-storage-dependencies.sh" || log_warning "Storage dependencies had issues, continuing..."
    else
        log_warning "install-storage-dependencies.sh not found, using fallback..."
        # Fallback to missing resource classes
        "$SCRIPT_DIR/install-missing-resource-classes.sh" || log_warning "Resource classes installation had issues"
    fi
  
    log_success "Storage dependencies installation completed"
}

install_missing_resource_classes() {
  log_info "Installing missing resource classes..."
  "$SCRIPT_DIR/install-missing-resource-classes.sh"

  log_success "Missing resource classes installation completed"
}

# Install missing resource classes for minikube
# install_missing_resource_classes() {
#     log_info "Installing missing resource classes for minikube..."
    
#     # Create VolumeSnapshotClass for minikube clusters (uses csi-hostpath driver)
#     log_info "Creating VolumeSnapshotClass for minikube clusters..."
#     kubectl apply -f - <<EOF || log_warning "VolumeSnapshotClass may already exist"
# apiVersion: snapshot.storage.k8s.io/v1
# kind: VolumeSnapshotClass
# metadata:
#   name: demo-snapclass
#   labels:
#     app.kubernetes.io/name: ramen-demo
#     velero.io/csi-volumesnapshot-class: "true"
# driver: hostpath.csi.k8s.io
# deletionPolicy: Delete
# EOF
    
#     # Create VolumeReplicationClass (required for VRG selectors)
#     log_info "Creating VolumeReplicationClass for VolSync replication..."
#     kubectl apply -f - <<EOF || log_warning "VolumeReplicationClass may already exist"
# apiVersion: replication.storage.openshift.io/v1alpha1
# kind: VolumeReplicationClass
# metadata:
#   name: demo-replication-class
#   labels:
#     app.kubernetes.io/name: ramen-demo
#     ramendr.openshift.io/replicationID: ramen-volsync
# spec:
#   provisioner: hostpath.csi.k8s.io
#   parameters:
#     copyMethod: Snapshot
# EOF
    
#     # Create stub CRDs for optional RamenDR resources (to prevent operator crashes)
#     log_info "Creating stub CRDs for optional RamenDR resources..."
    
#     # NetworkFenceClass
#     kubectl apply -f - <<EOF || log_warning "NetworkFenceClass CRD may already exist"
# apiVersion: apiextensions.k8s.io/v1
# kind: CustomResourceDefinition
# metadata:
#   name: networkfenceclasses.csiaddons.openshift.io
# spec:
#   group: csiaddons.openshift.io
#   names:
#     kind: NetworkFenceClass
#     listKind: NetworkFenceClassList
#     plural: networkfenceclasses
#     singular: networkfenceclass
#   scope: Cluster
#   versions:
#   - name: v1alpha1
#     served: true
#     storage: true
#     schema:
#       openAPIV3Schema:
#         type: object
#         x-kubernetes-preserve-unknown-fields: true
# EOF
    
#     # VolumeGroupSnapshotClass (missing CRD that operators expect)
#     kubectl apply -f - <<EOF || log_warning "VolumeGroupSnapshotClass CRD may already exist"
# apiVersion: apiextensions.k8s.io/v1
# kind: CustomResourceDefinition
# metadata:
#   name: volumegroupsnapshotclasses.groupsnapshot.storage.openshift.io
# spec:
#   group: groupsnapshot.storage.openshift.io
#   names:
#     kind: VolumeGroupSnapshotClass
#     listKind: VolumeGroupSnapshotClassList
#     plural: volumegroupsnapshotclasses
#     singular: volumegroupsnapshotclass
#   scope: Cluster
#   versions:
#   - name: v1beta1
#     served: true
#     storage: true
#     schema:
#       openAPIV3Schema:
#         type: object
#         x-kubernetes-preserve-unknown-fields: true
# EOF
    
#     # Other stub CRDs following the same pattern...
#     # (Include the other CRDs from install-missing-resource-classes.sh)
    
#     log_info "Verifying created resources..."
#     log_success "All required CRDs and resource classes installed successfully"
# }

# Install missing OCM CRDs required for hub operator
install_ocm_crds() {
    log_info "Installing missing OCM CRDs for hub operator..."
    
    # Check if OCM is already set up (cluster-manager exists)
    if kubectl --context=ramen-hub get crd managedclusters.cluster.open-cluster-management.io >/dev/null 2>&1 && \
       kubectl --context=ramen-hub get crd placements.cluster.open-cluster-management.io >/dev/null 2>&1 && \
       kubectl --context=ramen-hub get crd manifestworks.work.open-cluster-management.io >/dev/null 2>&1; then
        log_success "OCM CRDs already exist"
        return 0
    fi
    
    # OCM not set up yet - suggest running setup-ocm-resources.sh first
    log_warning "OCM not detected. setup-ocm-resources.sh should have been run first (step 2)"
    log_info "Installing minimal CRDs for hub operator startup..."
    
    # Install minimal OCM CRDs required for hub operator to start
    log_info "Installing ManagedCluster CRD..."
    kubectl apply -f https://raw.githubusercontent.com/open-cluster-management-io/api/main/cluster/v1/0000_00_clusters.open-cluster-management.io_managedclusters.crd.yaml || log_warning "ManagedCluster CRD may already exist"
    
    log_info "Installing Placement CRD..."
    kubectl apply -f https://raw.githubusercontent.com/open-cluster-management-io/api/main/cluster/v1beta1/0000_02_clusters.open-cluster-management.io_placements.crd.yaml || log_warning "Placement CRD may already exist"
    
    log_info "Installing ManifestWork CRD..."
    kubectl apply -f https://raw.githubusercontent.com/open-cluster-management-io/api/main/work/v1/0000_00_work.open-cluster-management.io_manifestworks.crd.yaml || log_warning "ManifestWork CRD may already exist"
    
    log_success "Minimal OCM CRDs installed"
    log_info "Note: Full OCM setup recommended via setup-ocm-resources.sh"
}

# Update the install_hub_operator function to continue on snapshot controller failure:
install_hub_operator() {
    log_step "Installing Ramen Hub Operator..."

    # Use utility functions
    ensure_namespace "ramen-hub" "ramen-system" 90 || exit 1
    ensure_namespace "ramen-hub" "open-cluster-management" 60 || exit 1
    
    # Install dependencies - don't fail on storage dependency issues
    log_info "Installing storage dependencies..."
    install_storage_dependencies || log_warning "Storage dependencies had issues, continuing..."
    
    log_info "Installing RamenDR Hub CRDs..."
    make install-hub
    
    # Install OCM CRDs
    # install_ocm_crds
    
    # Build and deploy
    build_and_load_image "ramen-hub" || exit 1
    
    # Deploy hub operator
    log_info "Deploying hub operator to ramen-hub cluster..."
    switch_context "ramen-hub" || exit 1
    make deploy-hub
    
    # Wait for deployment using utility with more lenient timeout
    if wait_for_deployment "ramen-hub" "ramen-hub-operator" "ramen-system" 180; then
        log_success "Ramen Hub Operator installed successfully"
    else
        log_warning "Hub operator deployment may need more time, checking status..."
        kubectl get pods -n ramen-system || true
        log_info "Continuing with cluster operator installation..."
    fi
}


# Replace install_cluster_operator function with:
install_cluster_operator() {
    log_step "Installing Ramen Cluster Operator..."
    
    # Get DR contexts using utility
    local dr_contexts=($(get_contexts_matching "ramen-dr"))
    
    if [ ${#dr_contexts[@]} -eq 0 ]; then
        log_error "No DR cluster contexts found (ramen-dr*)"
        exit 1
    fi
    
    log_info "Found DR contexts: ${dr_contexts[*]}"

    # Create namespaces on all DR clusters using utility
    for context in "${dr_contexts[@]}"; do
        log_info "Creating namespaces \"ramen-system\" and \"open-cluster-management\" on $context..."
        ensure_namespace "$context" "ramen-system" 60 || exit 1
        ensure_namespace "$context" "open-cluster-management" 60 || exit 1
    done
    
    # Install on each DR cluster
    for context in "${dr_contexts[@]}"; do
        log_info "Installing on $context..."
        switch_context "$context" || exit 1
        
        # Build and load image
        build_and_load_image "${context}" || log_warning "Image load failed for $context, continuing..."
        
        # Install dependencies - don't fail on issues
        log_info "Installing storage dependencies on $context..."
        install_storage_dependencies || log_warning "Storage dependencies had issues on $context, continuing..."
        
        log_info "Deploying cluster operator to $context..."
        # Deploy
        if make deploy-dr-cluster; then
            log_success "Deployment command completed for $context"
        else
            log_warning "Deployment command had issues for $context, checking status..."
        fi
        
        # Wait for deployment using utility with more lenient approach
        if wait_for_deployment "$context" "ramen-dr-cluster-operator" "ramen-system" 180; then
            log_success "Cluster operator installed on $context"
        else
            log_warning "Cluster operator on $context may need more time"
            kubectl get pods -n ramen-system || true
            kubectl get deployment -n ramen-system || true
        fi
    done
}

# Update verify_installation to use utilities:
verify_installation() {
    log_step "Verifying installation..."
    
    # Check hub operator
    verify_deployment "ramen-hub" "ramen-hub-operator" "ramen-system" "Hub operator"
    
    # Check DR operators
    local dr_contexts=($(get_contexts_matching "ramen-dr"))
    for context in "${dr_contexts[@]}"; do
        verify_deployment "$context" "ramen-dr-cluster-operator" "ramen-system" "DR operator on $context"
    done
}

# Install on all minikube clusters
install_all_clusters() {
    log_info "🌐 Installing RamenDR operators on all minikube clusters..."
    
    # Check that required contexts exist
    local required_contexts=("ramen-hub" "ramen-dr1")
    for context in "${required_contexts[@]}"; do
        if ! kubectl config get-contexts -o name | grep -q "^${context}$"; then
            log_error "Required context '${context}' not found. Please ensure all minikube clusters are created."
            log_info "Run: ./scripts/setup-minikube.sh"
            exit 1
        fi
    done
    
    log_info "✅ All required contexts found: ${required_contexts[*]}"
    
    # Install hub operator first
    log_step "Installing Hub Operator on ramen-hub..."
    kubectl config use-context ramen-hub
    install_hub_operator
    
    # Install DR cluster operators
    log_step "Installing DR Cluster Operators on DR clusters..."
    install_cluster_operator
    
    log_success "🎉 Multi-cluster installation completed!"
    log_info "Hub operator: ramen-hub"
    log_info "DR operators: ${dr_contexts[*]}"
}

# Verify installation
verify_installation() {
    log_step "Verifying installation..."
    
    # Check hub operator
    kubectl config use-context ramen-hub
    if kubectl get deployment ramen-hub-operator -n ramen-system >/dev/null 2>&1; then
        log_success "✅ Hub operator deployed"
    else
        log_error "❌ Hub operator not found"
    fi
    
    # Check DR operators
    local dr_contexts=($(kubectl config get-contexts -o name | grep "^ramen-dr"))
    for context in "${dr_contexts[@]}"; do
        kubectl config use-context "$context"
        if kubectl get deployment ramen-dr-cluster-operator -n ramen-system >/dev/null 2>&1; then
            log_success "✅ DR operator deployed on $context"
        else
            log_error "❌ DR operator not found on $context"
        fi
    done
}



# Create sample DR policy
create_sample_policy() {
    log_step "Creating sample DR policy..."
    
    switch_context "ramen-hub" || return 1
    
    local minikube_yaml_dir="$SCRIPT_DIR/../yaml/minikube"
    
    # Apply DRPolicy using external YAML
    if [ -f "$minikube_yaml_dir/drpolicy.yaml" ]; then
        log_info "Applying DRPolicy from external YAML..."
        apply_yaml_with_timeout_warning "kubectl --context=ramen-hub apply -f $minikube_yaml_dir/drpolicy.yaml" "DRPolicy creation"
    else
        log_error "DRPolicy YAML file not found: $minikube_yaml_dir/drpolicy.yaml"
        return 1
    fi
    
    # Apply DRClusters using external YAML
    if [ -f "$minikube_yaml_dir/drclusters.yaml" ]; then
        log_info "Applying DRClusters from external YAML..."
        apply_yaml_with_timeout_warning "kubectl --context=ramen-hub apply -f $minikube_yaml_dir/drclusters.yaml" "DRClusters creation"
    else
        log_error "DRClusters YAML file not found: $minikube_yaml_dir/drclusters.yaml"
        return 1
    fi
    
    log_success "Sample DR policy setup completed"
}

# Show next steps
show_next_steps() {
    log_success "🎉 RamenDR installation completed!"
    echo ""
    log_info "📋 Next steps:"
    echo "   1. Deploy S3 storage: ./examples/deploy-ramendr-s3.sh"
    echo "   2. Setup cross-cluster access: ./scripts/setup-cross-cluster-s3.sh"
    echo "   3. Run failover demo: ./examples/demo-failover-minikube.sh"
    echo ""
    log_info "🔍 Verify installation:"
    echo "   • Hub operator: kubectl get pods -n ramen-system --context=ramen-hub"
    echo "   • DR operators: kubectl get pods -n ramen-system --context=ramen-dr1"
    echo ""
}

# Main installation function
main() {
    log_info "🚀 Starting automated RamenDR installation for minikube..."
    
    # Check for automated choice via environment variable or command line
    local choice="${AUTO_INSTALL_CHOICE:-${1:-}}"
    
    # If no automated choice provided, ask user
    if [ -z "$choice" ]; then
        echo "Select installation type:"
        echo "  1) Hub only (for hub cluster)"
        echo "  2) Cluster only (for managed cluster)"
        echo "  3) All clusters (automated multi-cluster setup)"
        echo ""
        read -p "Enter choice (1-3): " choice
    else
        log_info "Using automated choice: $choice"
    fi
    
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
            log_error "Invalid choice: $choice"
            exit 1
            ;;
    esac
    
    verify_installation
    create_sample_policy
    show_next_steps
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "RamenDR Quick Install for minikube"
        echo ""
        echo "Usage: $0 [options] [choice]"
        echo ""
        echo "Arguments:"
        echo "  choice    Installation choice (1=hub, 2=cluster, 3=all)"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help"
        echo ""
        echo "Environment variables:"
        echo "  AUTO_INSTALL_CHOICE    Set installation choice (1-3)"
        echo ""
        echo "Examples:"
        echo "  $0 3                   # Install all clusters automatically"
        echo "  AUTO_INSTALL_CHOICE=3 $0   # Install all clusters via env var"
        echo "  echo '3' | $0         # Install all clusters via pipe"
        echo ""
        echo "This script installs RamenDR operators on minikube clusters"
        echo "Prerequisites: minikube clusters created with ./scripts/setup-minikube.sh"
        exit 0
        ;;
    [1-3])
        main "$1"
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
