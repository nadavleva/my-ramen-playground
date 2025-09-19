#!/bin/bash

set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

log_info "🔧 Installing Snapshot CRDs and Controller for RamenDR"
echo "============================================="

YAML_DIR="$SCRIPT_DIR/../yaml/external-snapshotter/v6.3.0"

# Function to install CRD using utils with local/remote fallback
install_crd_with_utils() {
    local name=$1
    local local_file=$2
    local remote_url=$3
    
    log_info "📦 Installing $name..."
    
    # Try local file first
    if [ -f "$local_file" ]; then
        log_info "Using local file: $local_file"
        if apply_url_safe "$(kubectl config current-context)" "file://$local_file" "$name CRD from local file"; then
            log_success "✅ $name installed from local file"
            return 0
        else
            log_warning "Local file failed, trying remote URL..."
        fi
    else
        log_warning "Local file not found: $local_file"
        log_info "Downloading from: $remote_url"
    fi
    
    # Fallback to remote URL using utils
    if apply_url_safe "$(kubectl config current-context)" "$remote_url" "$name CRD from remote" 3; then
        # Save for future use
        mkdir -p "$(dirname "$local_file")"
        curl -fsSL "$remote_url" > "$local_file"
        log_info "💾 Saved to: $local_file"
    else
        log_error "Failed to install $name"
        return 1
    fi
}

# Check if CRD exists using utils pattern
crd_exists() {
    local crd_name=$1
    local context=$(kubectl config current-context)
    kubectl --context="$context" get crd "$crd_name" >/dev/null 2>&1
}

# Install VolumeSnapshot CRDs using utils
log_info "🔍 Installing VolumeSnapshot CRDs..."

# Check and install each CRD
if crd_exists "volumesnapshotclasses.snapshot.storage.k8s.io"; then
    log_info "✅ VolumeSnapshotClass CRD already exists"
else
    install_crd_with_utils "VolumeSnapshotClass" \
        "$YAML_DIR/volumesnapshotclasses.yaml" \
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml"
fi

if crd_exists "volumesnapshots.snapshot.storage.k8s.io"; then
    log_info "✅ VolumeSnapshot CRD already exists"
else
    install_crd_with_utils "VolumeSnapshot" \
        "$YAML_DIR/volumesnapshots.yaml" \
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml"
fi

if crd_exists "volumesnapshotcontents.snapshot.storage.k8s.io"; then
    log_info "✅ VolumeSnapshotContent CRD already exists"
else
    install_crd_with_utils "VolumeSnapshotContent" \
        "$YAML_DIR/volumesnapshotcontents.yaml" \
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml"
fi

# Install Snapshot Controller using utils
install_snapshot_controller() {
    log_info "🎛️ Installing Snapshot Controller..."
    
    local context=$(kubectl config current-context)
    
    # The controller deploys to kube-system, so ensure that namespace exists
    ensure_namespace "$context" "kube-system"
    
    # Check if snapshot controller deployment already exists in kube-system
    if kubectl --context="$context" get deployment snapshot-controller -n kube-system >/dev/null 2>&1; then
        local ready_replicas=$(kubectl --context="$context" get deployment snapshot-controller -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired_replicas=$(kubectl --context="$context" get deployment snapshot-controller -n kube-system -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [ "$ready_replicas" = "$desired_replicas" ] && [ "$ready_replicas" != "0" ]; then
            log_success "✅ Snapshot Controller already exists and is ready ($ready_replicas/$desired_replicas replicas)"
            return 0
        else
            log_info "Snapshot Controller exists but not ready ($ready_replicas/$desired_replicas replicas), applying manifests..."
        fi
    fi
    
    log_info "Installing Snapshot Controller RBAC and Deployment..."
    
    # Install RBAC using utils
    local rbac_url="https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml"
    apply_url_safe "$context" "$rbac_url" "Snapshot Controller RBAC"
    
    # Install Deployment using utils
    local controller_url="https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml"
    apply_url_safe "$context" "$controller_url" "Snapshot Controller Deployment"
    
    # Wait for the deployment in kube-system namespace
    log_info "Waiting for snapshot controller deployment in kube-system..."
    wait_for_deployment "$context" "snapshot-controller" "kube-system" 180
    
    log_success "✅ Snapshot Controller installed successfully in kube-system"
}

# Install Snapshot Controller
install_snapshot_controller

# Create mock VolumeSnapshotClass using utils
log_info "🎭 Creating mock VolumeSnapshotClass for demo..."

mock_snapclass_yaml="apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: mock-snapclass
  labels:
    velero.io/csi-volumesnapshot-class: \"true\"
driver: mock.csi.driver
deletionPolicy: Delete
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass  
metadata:
  name: standard-snapclass
  labels:
    velero.io/csi-volumesnapshot-class: \"true\"
driver: standard.csi.driver
deletionPolicy: Delete"

create_resource "$(kubectl config current-context)" "cluster-scoped" "$mock_snapclass_yaml" "Mock VolumeSnapshotClasses"

# Check results using utils
log_info "🔍 Verifying installation..."
echo "Snapshot CRDs:"
kubectl get crd | grep -E "snapshot|volumesnapshot" || log_warning "No snapshot CRDs found"

echo -e "\nSnapshot Classes:"
kubectl get volumesnapshotclass 2>/dev/null || log_warning "No VolumeSnapshotClasses found"

echo -e "\nSnapshot Controller:"
if kubectl get deployment snapshot-controller -n kube-system >/dev/null 2>&1; then
    kubectl get deployment snapshot-controller -n kube-system
    kubectl get pods -n kube-system | grep snapshot-controller
    log_success "✅ Snapshot Controller is running in kube-system"
else
    log_warning "No snapshot controller found in kube-system"
fi
log_success "✅ Snapshot CRDs and Controller installation completed!"
log_warning "⚠️  Note: These provide snapshot infrastructure for RamenDR"
log_info "💡 This enables proper snapshot functionality for VolSync and RamenDR"