#!/bin/bash

# Install Snapshot CRDs for RamenDR Demo
# This reduces operator errors by providing the expected CRDs

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Installing Snapshot CRDs for RamenDR${NC}"
echo "============================================="

# Function to install CRD from GitHub
install_crd() {
    local name=$1
    local url=$2
    
    echo -e "${BLUE}📦 Installing $name...${NC}"
    if curl -fsSL "$url" | kubectl apply -f -; then
        echo -e "${GREEN}✅ $name installed successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  $name may already exist or URL changed${NC}"
    fi
}

# Install VolumeSnapshot CRDs
echo -e "${BLUE}🔍 Installing VolumeSnapshot CRDs...${NC}"

install_crd "VolumeSnapshotClass" \
    "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml"

install_crd "VolumeSnapshot" \
    "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml"

install_crd "VolumeSnapshotContent" \
    "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml"

# Create mock VolumeSnapshotClass for demo purposes
echo -e "${BLUE}🎭 Creating mock VolumeSnapshotClass for demo...${NC}"
cat << EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: mock-snapclass
  labels:
    velero.io/csi-volumesnapshot-class: "true"
driver: mock.csi.driver
deletionPolicy: Delete
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass  
metadata:
  name: standard-snapclass
  labels:
    velero.io/csi-volumesnapshot-class: "true"
driver: standard.csi.driver
deletionPolicy: Delete
EOF

echo -e "${GREEN}✅ Mock VolumeSnapshotClass created${NC}"

# Check results
echo -e "${BLUE}🔍 Checking installed CRDs...${NC}"
echo "Snapshot CRDs:"
kubectl get crd | grep -E "snapshot|volumesnapshot" || echo "No snapshot CRDs found"

echo -e "\nSnapshot Classes:"
kubectl get volumesnapshotclass 2>/dev/null || echo "No VolumeSnapshotClasses found"

echo ""
echo -e "${GREEN}✅ Snapshot CRDs installation completed!${NC}"
echo -e "${YELLOW}⚠️  Note: These are CRDs only - no actual snapshot functionality${NC}"
echo -e "${BLUE}💡 This reduces RamenDR operator errors and enables VolSync configuration${NC}"

echo ""
echo -e "${BLUE}🔄 Restart RamenDR operator to pick up new CRDs:${NC}"
echo "   kubectl rollout restart deployment/ramen-dr-cluster-operator -n ramen-system"
