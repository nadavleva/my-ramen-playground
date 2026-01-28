#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Manual setup for both DR clusters with Ceph
# Based on playground monitoring setup patterns

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
log_step() { echo -e "${PURPLE}🔧 $1${NC}"; }

echo -e "${PURPLE}🚀 Manual DR Clusters Setup with Ceph${NC}"
echo "========================================"
echo ""

log_info "This will create 3 clusters with Ceph storage:"
echo "  • hub  - Management cluster"
echo "  • dr1  - Primary DR cluster with Ceph RBD"
echo "  • dr2  - Secondary DR cluster with Ceph RBD"
echo ""

# Configuration
HUB_PROFILE="hub"
DR1_PROFILE="dr1" 
DR2_PROFILE="dr2"
MINIKUBE_DRIVER="kvm2"
MEMORY="6144"  # 6GB per cluster for Ceph
CPUS="4"       # 4 vCPUs per cluster for Ceph
KUBERNETES_VERSION="v1.29.0"  # Use stable version

log_step "Step 1: Creating hub cluster..."
minikube start \
    --profile="$HUB_PROFILE" \
    --driver="$MINIKUBE_DRIVER" \
    --memory="4096" \
    --cpus="2" \
    --kubernetes-version="$KUBERNETES_VERSION" \
    --addons=storage-provisioner,default-storageclass \
    --wait=true

log_success "Hub cluster created"
minikube update-context --profile="$HUB_PROFILE"

log_step "Step 2: Creating dr1 cluster with extra storage for Ceph..."
minikube start \
    --profile="$DR1_PROFILE" \
    --driver="$MINIKUBE_DRIVER" \
    --memory="$MEMORY" \
    --cpus="$CPUS" \
    --kubernetes-version="$KUBERNETES_VERSION" \
    --addons=storage-provisioner,default-storageclass,volumesnapshots,csi-hostpath-driver \
    --extra-disks=1 \
    --disk-size=20g \
    --wait=true

log_success "DR1 cluster created"
minikube update-context --profile="$DR1_PROFILE"

log_step "Step 3: Creating dr2 cluster with extra storage for Ceph..."
minikube start \
    --profile="$DR2_PROFILE" \
    --driver="$MINIKUBE_DRIVER" \
    --memory="$MEMORY" \
    --cpus="$CPUS" \
    --kubernetes-version="$KUBERNETES_VERSION" \
    --addons=storage-provisioner,default-storageclass,volumesnapshots,csi-hostpath-driver \
    --extra-disks=1 \
    --disk-size=20g \
    --wait=true

log_success "DR2 cluster created"
minikube update-context --profile="$DR2_PROFILE"

log_step "Step 4: Updating all contexts..."
minikube update-context --profile="$HUB_PROFILE"
minikube update-context --profile="$DR1_PROFILE"  
minikube update-context --profile="$DR2_PROFILE"

log_step "Step 5: Verifying cluster connectivity..."
echo ""
echo "Hub cluster:"
kubectl --context=hub get nodes -o wide
echo ""
echo "DR1 cluster:"
kubectl --context=dr1 get nodes -o wide  
echo ""
echo "DR2 cluster:"
kubectl --context=dr2 get nodes -o wide
echo ""

log_step "Step 6: Installing Rook Ceph on DR clusters..."

# Install Rook operator on dr1
log_info "Installing Rook operator on dr1..."
kubectl --context=dr1 apply -f https://raw.githubusercontent.com/rook/rook/v1.12.3/deploy/examples/crds.yaml
kubectl --context=dr1 apply -f https://raw.githubusercontent.com/rook/rook/v1.12.3/deploy/examples/common.yaml
kubectl --context=dr1 apply -f https://raw.githubusercontent.com/rook/rook/v1.12.3/deploy/examples/operator.yaml

# Install Rook operator on dr2
log_info "Installing Rook operator on dr2..."
kubectl --context=dr2 apply -f https://raw.githubusercontent.com/rook/rook/v1.12.3/deploy/examples/crds.yaml
kubectl --context=dr2 apply -f https://raw.githubusercontent.com/rook/rook/v1.12.3/deploy/examples/common.yaml
kubectl --context=dr2 apply -f https://raw.githubusercontent.com/rook/rook/v1.12.3/deploy/examples/operator.yaml

log_info "Waiting for Rook operators to be ready..."
kubectl --context=dr1 wait --for=condition=ready pod -l app=rook-ceph-operator -n rook-ceph --timeout=300s
kubectl --context=dr2 wait --for=condition=ready pod -l app=rook-ceph-operator -n rook-ceph --timeout=300s

log_step "Step 7: Creating Ceph clusters..."

# Create Ceph cluster config for single node (minikube)
cat > ceph-cluster.yaml << 'EOF'
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v17.2.6
    allowUnsupported: false
  dataDirHostPath: /var/lib/rook
  skipUpgradeChecks: false
  continueUpgradeAfterChecksEvenIfNotHealthy: false
  waitTimeoutForHealthyOSDInMinutes: 10
  mon:
    count: 1
    allowMultiplePerNode: false
  mgr:
    count: 1
    allowMultiplePerNode: false
  dashboard:
    enabled: true
    ssl: true
  monitoring:
    enabled: false
  network:
    connections:
      requireMsgr2: false
  crashCollector:
    disable: false
  logCollector:
    enabled: true
    periodicity: daily
  cleanupPolicy:
    confirmation: ""
    sanitizeDisks:
      method: quick
      dataSource: zero
      iteration: 1
  placement:
    all:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: kubernetes.io/os
              operator: In
              values:
              - linux
      tolerations:
      - effect: NoSchedule
        operator: Exists
  resources:
    mgr:
      requests:
        cpu: "125m"
        memory: "549Mi"
    mon:
      requests:
        cpu: "49m"
        memory: "477Mi"
    osd:
      requests:
        cpu: "442m"
        memory: "2781Mi"
  storage:
    useAllNodes: true
    useAllDevices: false
    deviceFilter: "^sd[b-z]"
    config:
      osdsPerDevice: "1"
EOF

log_info "Deploying Ceph cluster on dr1..."
kubectl --context=dr1 apply -f ceph-cluster.yaml

log_info "Deploying Ceph cluster on dr2..."  
kubectl --context=dr2 apply -f ceph-cluster.yaml

log_step "Step 8: Creating RBD storage pools with mirroring..."

cat > ceph-blockpool.yaml << 'EOF'
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: replicapool
  namespace: rook-ceph
spec:
  failureDomain: host
  replicated:
    size: 1
    requireSafeReplicaSize: false
  mirroring:
    enabled: true
    mode: image
EOF

log_info "Creating block pools..."
kubectl --context=dr1 apply -f ceph-blockpool.yaml
kubectl --context=dr2 apply -f ceph-blockpool.yaml

log_step "Step 9: Creating storage classes..."

cat > storage-class.yaml << 'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

kubectl --context=dr1 apply -f storage-class.yaml
kubectl --context=dr2 apply -f storage-class.yaml

log_step "Step 10: Waiting for Ceph clusters to be ready..."
echo "This may take 5-10 minutes..."

kubectl --context=dr1 wait --for=condition=ready cephcluster/rook-ceph -n rook-ceph --timeout=600s || log_warning "DR1 Ceph cluster taking longer than expected"
kubectl --context=dr2 wait --for=condition=ready cephcluster/rook-ceph -n rook-ceph --timeout=600s || log_warning "DR2 Ceph cluster taking longer than expected"

# Cleanup temp files
rm -f ceph-cluster.yaml ceph-blockpool.yaml storage-class.yaml

log_success "🎉 Both DR clusters with Ceph are now ready!"
echo ""
echo -e "${CYAN}📊 Cluster Status:${NC}"
echo "  • hub  - Management cluster: $(kubectl --context=hub get nodes --no-headers | wc -l) node(s)"
echo "  • dr1  - Primary with Ceph:   $(kubectl --context=dr1 get nodes --no-headers | wc -l) node(s)"  
echo "  • dr2  - Secondary with Ceph: $(kubectl --context=dr2 get nodes --no-headers | wc -l) node(s)"
echo ""
echo -e "${CYAN}🎯 Next Steps:${NC}"
echo "  1. Test monitoring: ./regional-dr-monitoring.sh"
echo "  2. Check Ceph health:"
echo "     kubectl --context=dr1 -n rook-ceph get cephcluster"
echo "     kubectl --context=dr2 -n rook-ceph get cephcluster" 
echo "  3. Deploy RamenDR operators (if needed)"
echo "  4. Test CSI replication between dr1 and dr2"
echo ""
echo -e "${PURPLE}📋 Available contexts:${NC}"
kubectl config get-contexts | grep -E "(hub|dr1|dr2)"