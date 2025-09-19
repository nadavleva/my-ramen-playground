#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors  
# SPDX-License-Identifier: Apache-2.0

# Install Missing Resource Classes for RamenDR Demo
# This script creates the VolumeSnapshotClass and VolumeReplicationClass
# resources that VRGs need to match their selectors

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log_info "🔧 Installing missing resource classes for RamenDR demo"
echo "================================================================"
echo ""

# Function to apply YAML file safely
# Function to apply YAML file safely with built-in existence check
apply_yaml_file() {
    local yaml_file="$1"
    local description="$2"
    
    if [ -f "$yaml_file" ]; then
        log_info "Applying $description from file: $yaml_file"
        if kubectl apply -f "$yaml_file"; then
            log_success "$description applied successfully"
            return 0
        else
            log_warning "$description may already exist or failed to apply"
            return 1
        fi
    else
        log_warning "$description file not found: $yaml_file"
        return 1
    fi
}

# Function to try multiple file locations
apply_yaml_file_multi() {
    local description="$1"
    shift  # Remove first argument, rest are file paths
    local files=("$@")
    
    for yaml_file in "${files[@]}"; do
        if apply_yaml_file "$yaml_file" "$description"; then
            return 0
        fi
    done
    
    log_error "No valid file found for $description in any of the specified locations"
    return 1
}

# Function to create VolumeSnapshotClass
create_volume_snapshot_class() {
    log_info "📸 Creating VolumeSnapshotClass for minikube clusters..."
    
    local yaml_file="$SCRIPT_DIR/../yaml/resource-classes/volume-snapshot-class.yaml"
    apply_yaml_file "$yaml_file" "VolumeSnapshotClass"
}

# Function to create VolumeReplicationClass
create_volume_replication_class() {
    log_info "🔄 Creating VolumeReplicationClass for VolSync replication..."
    
    local yaml_file="$SCRIPT_DIR/../yaml/resource-classes/volume-replication-class.yaml"
    apply_yaml_file "$yaml_file" "VolumeReplicationClass"
}

# Function to create External Snapshotter CRDs
install_snapshot_crds() {
    log_info "📦 Installing External Snapshotter CRDs first..."
    
    local snapshotter_dir="$SCRIPT_DIR/../yaml/external-snapshotter/v6.3.0"
    
    # Install VolumeSnapshotClass CRD
    apply_yaml_file "$snapshotter_dir/volumesnapshotclasses.yaml" "VolumeSnapshotClass CRD"
    
    # Install VolumeSnapshot CRD  
    apply_yaml_file "$snapshotter_dir/volumesnapshots.yaml" "VolumeSnapshot CRD"
    
    # Install VolumeSnapshotContent CRD
    apply_yaml_file "$snapshotter_dir/volumesnapshotcontents.yaml" "VolumeSnapshotContent CRD"
    
    log_success "External Snapshotter CRDs installed"
}


# Function to create VolumeReplication CRDs
create_volume_replication_crds() {
    log_info "🏗️ Installing VolumeReplication CRDs..."
    
    local resource_classes_dir="$SCRIPT_DIR/../yaml/resource-classes"
    
    # VolumeReplication CRD
    apply_yaml_file "$resource_classes_dir/volume-replication-crd.yaml" "VolumeReplication CRD"
    
    # VolumeReplicationClass CRD - now install it explicitly
    apply_yaml_file "$resource_classes_dir/volume-replication-class-crd.yaml" "VolumeReplicationClass CRD"
    
    log_success "VolumeReplication CRDs installed"
}


# Function to create stub CRDs using existing files
create_stub_crds() {
     log_info "🏗️ Creating stub CRDs to prevent operator startup failures..."
    
    local crd_dir="$SCRIPT_DIR/../yaml/crds"
    local resource_classes_dir="$SCRIPT_DIR/../yaml/resource-classes"
    
    # NetworkFenceClass CRD - try both locations (prefer crds directory)
    apply_yaml_file_multi "NetworkFenceClass CRD" \
        "$crd_dir/networkfenceclass-crd.yaml" \
        "$resource_classes_dir/network-fence-class-crd.yaml"
    
    # VolumeGroupSnapshotClass CRD - try both locations (prefer crds directory)
    apply_yaml_file_multi "VolumeGroupSnapshotClass CRD" \
        "$crd_dir/volume-group-snapshot-class-crd.yaml" \
        "$resource_classes_dir/volume-group-snapshot-class-crd.yaml"
    
    # VolumeGroupReplicationClass CRD
    apply_yaml_file "$resource_classes_dir/volume-group-replication-class-crd.yaml" "VolumeGroupReplicationClass CRD"
    
    # VolumeGroupReplication CRD
    apply_yaml_file "$resource_classes_dir/volume-group-replication-crd.yaml" "VolumeGroupReplication CRD"
    
    log_success "Stub CRDs installation completed"
}

# Function to verify resource creation
verify_resources() {
    log_info "✅ Verifying created resources..."
    
    echo "VolumeSnapshotClass:"
    if kubectl get volumesnapshotclass demo-snapclass >/dev/null 2>&1; then
        kubectl get volumesnapshotclass demo-snapclass -o wide 2>/dev/null || log_warning "Could not get details"
    else
        log_warning "VolumeSnapshotClass 'demo-snapclass' not found"
    fi
    
    echo ""
    echo "VolumeReplicationClass:"
    if kubectl get volumereplicationclass demo-replication-class >/dev/null 2>&1; then
        kubectl get volumereplicationclass demo-replication-class -o wide 2>/dev/null || log_warning "Could not get details"
    else
        log_warning "VolumeReplicationClass 'demo-replication-class' not found"
    fi
    
    echo ""
    echo "CRDs installed:"
    kubectl get crd | grep -E "(volumereplication|networkfence|volumegroup)" 2>/dev/null || echo "No relevant CRDs found"
    
    echo ""
    echo "Labels verification:"
    echo "VolumeSnapshotClass labels:"
    kubectl get volumesnapshotclass demo-snapclass -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "  (not found)"
    echo ""
    echo "VolumeReplicationClass labels:"
    kubectl get volumereplicationclass demo-replication-class -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "  (not found)"
    echo ""
}

# Main execution
main() {
    log_info "Installing missing resource classes that VRGs need..."
    
    # Check current context
    local current_context=$(kubectl config current-context)
    log_info "Current kubectl context: $current_context"

    # Install External Snapshotter CRDs FIRST
    install_snapshot_crds
    
    # Create CRDs needed for resource classes after snapshot CRDs
    create_volume_replication_crds
    create_stub_crds
    
    # Create resource classes
    create_volume_snapshot_class
    create_volume_replication_class
    
    # Verify creation
    verify_resources
    
    log_success "✅ Missing resource classes installation completed!"
    echo ""
    echo "📝 Summary:"
    echo "   • Current cluster: $current_context"
    echo "   • VRGs can now match their selectors successfully"
    echo "   • Run this script on all clusters if needed"
    echo ""
}

# Check if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi