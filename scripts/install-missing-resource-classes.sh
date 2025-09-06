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

# Function to create VolumeSnapshotClass that matches VRG selector
create_volume_snapshot_class() {
    log_info "📸 Creating VolumeSnapshotClass for kind clusters..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: demo-snapclass
  labels:
    velero.io/csi-volumesnapshot-class: "true"
    app.kubernetes.io/name: ramen-demo
driver: hostpath.csi.k8s.io
deletionPolicy: Delete
parameters:
  # Parameters for hostpath CSI driver in kind
  csi.storage.k8s.io/snapshotter-secret-name: ""
  csi.storage.k8s.io/snapshotter-secret-namespace: ""
EOF
    
    log_success "VolumeSnapshotClass created with velero.io/csi-volumesnapshot-class=true label"
}

# Function to create VolumeReplicationClass that matches VRG selector  
create_volume_replication_class() {
    log_info "🔄 Creating VolumeReplicationClass for VolSync replication..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplicationClass
metadata:
  name: demo-replication-class
  labels:
    ramendr.openshift.io/replicationID: ramen-volsync
    app.kubernetes.io/name: ramen-demo
spec:
  provisioner: hostpath.csi.k8s.io
  parameters:
    replication.storage.openshift.io/replication-secret-name: ""
    replication.storage.openshift.io/replication-secret-namespace: ""
    # VolSync-specific parameters for kind clusters
    copyMethod: Snapshot
    capacity: 1Gi
EOF
    
    log_success "VolumeReplicationClass created with ramendr.openshift.io/replicationID=ramen-volsync label"
}

# Function to create additional stub CRDs if needed
create_stub_crds() {
    log_info "🏗️ Creating minimal stub CRDs to prevent operator startup failures..."
    
    # NetworkFenceClass (prevents startup errors)
    cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: networkfenceclasses.csiaddons.openshift.io
spec:
  group: csiaddons.openshift.io
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
          status:
            type: object
  scope: Cluster
  names:
    plural: networkfenceclasses
    singular: networkfenceclass
    kind: NetworkFenceClass
EOF

    # VolumeGroupReplicationClass (prevents startup errors)
    cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: volumegroupreplicationclasses.replication.storage.openshift.io
spec:
  group: replication.storage.openshift.io
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
          status:
            type: object
  scope: Cluster
  names:
    plural: volumegroupreplicationclasses
    singular: volumegroupreplicationclass
    kind: VolumeGroupReplicationClass
EOF

    # VolumeGroupReplication (prevents startup errors)
    cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: volumegroupreplications.replication.storage.openshift.io
spec:
  group: replication.storage.openshift.io
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
          status:
            type: object
  scope: Namespaced
  names:
    plural: volumegroupreplications
    singular: volumegroupreplication
    kind: VolumeGroupReplication
EOF

    # VolumeGroupSnapshotClass (prevents startup errors)
    cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: volumegroupsnapshotclasses.groupsnapshot.storage.openshift.io
spec:
  group: groupsnapshot.storage.openshift.io
  scope: Cluster
  names:
    plural: volumegroupsnapshotclasses
    singular: volumegroupsnapshotclass
    kind: VolumeGroupSnapshotClass
  versions:
  - name: v1beta1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            x-kubernetes-preserve-unknown-fields: true
          status:
            type: object
            x-kubernetes-preserve-unknown-fields: true
        x-kubernetes-preserve-unknown-fields: true
EOF

    log_success "Stub CRDs created to prevent operator startup failures"
}

# Function to verify resource creation
verify_resources() {
    log_info "✅ Verifying created resources..."
    
    echo "VolumeSnapshotClass:"
    kubectl get volumesnapshotclass demo-snapclass -o wide || log_warning "VolumeSnapshotClass not found"
    
    echo ""
    echo "VolumeReplicationClass:"  
    kubectl get volumereplicationclass demo-replication-class -o wide || log_warning "VolumeReplicationClass not found"
    
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
    current_context=$(kubectl config current-context)
    log_info "Current kubectl context: $current_context"
    
    # Create resource classes
    create_volume_snapshot_class
    create_volume_replication_class
    create_stub_crds
    
    # Verify creation
    verify_resources
    
    log_success "✅ Missing resource classes installation completed!"
    echo ""
    echo "📝 Next steps:"
    echo "   1. These resource classes will be available on the current cluster: $current_context"
    echo "   2. VRGs can now match their selectors successfully"
    echo "   3. Run this script on all clusters (hub, dr1, dr2) if needed"
    echo ""
}

# Check if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
