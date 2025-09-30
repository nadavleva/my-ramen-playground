#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# RamenDR Storage Demo Monitoring Script for minikube
# Comprehensive real-time monitoring for Rook Ceph and storage scenarios

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Storage monitoring function
storage_monitoring() {
    clear
    echo "KUBECONFIG: $KUBECONFIG"
    echo "CURRENT_CONTEXT: $(kubectl config current-context 2>/dev/null || echo 'No context set')"

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}                    🗄️  RAMENDR STORAGE DEMO MONITORING                         ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Timestamp
    echo -e "${CYAN}📅 $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    # MINIKUBE INFRASTRUCTURE
    echo -e "${BLUE}=== MINIKUBE CLUSTERS ===${NC}"
    minikube profile list 2>/dev/null | tail -n +2 || echo "minikube not available"
    echo ""

    # LOOP DEVICES FOR CEPH
    echo -e "${PURPLE}=== BLOCK DEVICES (LOOP DEVICES) ===${NC}"
    echo "📀 ramen-dr1 devices:"
    minikube ssh -p ramen-dr1 -- "losetup -a" 2>/dev/null || echo "  Cannot access ramen-dr1"
    echo "📀 ramen-dr2 devices:"  
    minikube ssh -p ramen-dr2 -- "losetup -a" 2>/dev/null || echo "  Cannot access ramen-dr2"
    echo ""

    # ROOK CEPH CLUSTER STATUS
    echo -e "${YELLOW}=== ROOK CEPH CLUSTER STATUS ===${NC}"
    echo "🏗️  Ceph Cluster (ramen-dr1):"
    kubectl --context=ramen-dr1 -n rook-ceph get cephcluster -o wide 2>/dev/null || echo "  No CephCluster found on ramen-dr1"
    echo "🏗️  Ceph Cluster (ramen-dr2):"
    kubectl --context=ramen-dr2 -n rook-ceph get cephcluster -o wide 2>/dev/null || echo "  No CephCluster found on ramen-dr2"
    echo ""

    # CEPH COMPONENTS
    echo -e "${CYAN}=== CEPH COMPONENTS ===${NC}"
    echo "👥 MON/MGR/OSD Pods (ramen-dr1):"
    kubectl --context=ramen-dr1 -n rook-ceph get pods -l 'app in (rook-ceph-mon,rook-ceph-mgr,rook-ceph-osd)' 2>/dev/null | grep -v "No resources" || echo "  No Ceph component pods found"
    
    echo "🔧 Ceph Tools:"
    kubectl --context=ramen-dr1 -n rook-ceph get pods -l app=rook-ceph-tools 2>/dev/null | grep -v "No resources" || echo "  Ceph toolbox not found"
    echo ""

    # CEPH HEALTH STATUS
    echo -e "${GREEN}=== CEPH HEALTH STATUS ===${NC}"
    echo "🏥 Cluster Health (ramen-dr1):"
    timeout 10 kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph status -f json 2>/dev/null | jq -r '.health.status // "Unknown"' 2>/dev/null || echo "  Cannot connect to Ceph cluster"
    
    echo "💾 Storage Usage:"
    timeout 10 kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph df 2>/dev/null | head -10 || echo "  Storage info unavailable"
    echo ""

    # STORAGE CLASSES
    echo -e "${BLUE}=== STORAGE CLASSES ===${NC}"
    echo "📂 Available Storage Classes (ramen-dr1):"
    kubectl --context=ramen-dr1 get storageclass -o name 2>/dev/null | grep -E "(rook|ceph)" | sed 's|storageclass.storage.k8s.io/|  - |' || echo "  No Rook storage classes found"
    
    echo "📸 Volume Snapshot Classes:"
    kubectl --context=ramen-dr1 get volumesnapshotclass -o name 2>/dev/null | grep -E "(rook|ceph)" | sed 's|volumesnapshotclass.snapshot.storage.k8s.io/|  - |' || echo "  No Rook snapshot classes found"
    echo ""

    # STORAGE DEMO APPLICATIONS
    echo -e "${YELLOW}=== STORAGE DEMO APPLICATIONS ===${NC}"
    
    # Block Storage Demo
    echo "🧱 Block Storage Demo (SAN):"
    kubectl --context=ramen-dr1 -n block-storage-demo get pods,pvc -o wide 2>/dev/null | grep -v "No resources" || echo "  No block storage demo running"
    
    # File Storage Demo  
    echo "📁 File Storage Demo (VSAN):"
    kubectl --context=ramen-dr1 -n file-storage-demo get pods,pvc -o wide 2>/dev/null | grep -v "No resources" || echo "  No file storage demo running"
    
    # Object Storage Demo
    echo "🪣 Object Storage Demo (S3):"
    kubectl --context=ramen-dr1 -n object-storage-demo get pods,obc -o wide 2>/dev/null | grep -v "No resources" || echo "  No object storage demo running"
    echo ""

    # RAMENDR PROTECTION
    echo -e "${PURPLE}=== RAMENDR PROTECTION ===${NC}"
    echo "🛡️  VolumeReplicationGroups:"
    kubectl --context=ramen-dr1 get vrg -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No VRGs found"
    
    echo "🔄 Volume Replication:"
    kubectl --context=ramen-dr1 get volumereplication -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No VolumeReplications found"
    echo ""

    # S3 BACKUP STATUS
    echo -e "${CYAN}=== S3 BACKUP STATUS ===${NC}"
    echo "🗄️  MinIO (Hub cluster):"
    kubectl --context=ramen-hub -n minio-system get pods,svc 2>/dev/null | grep -v "No resources" || echo "  MinIO not accessible"
    
    echo "📦 Ramen Metadata Backups:"
    # Try to show S3 bucket contents if mc is available
    if command -v mc >/dev/null 2>&1; then
        mc ls minio-local/ramen-metadata/ 2>/dev/null | head -3 || echo "  No metadata backups found"
    else
        echo "  MinIO client not available for bucket inspection"
    fi
    echo ""

    # TROUBLESHOOTING COMMANDS
    echo -e "${YELLOW}=== QUICK TROUBLESHOOTING ===${NC}"
    echo "🔍 Debug Commands:"
    echo "  Storage Classes: kubectl --context=ramen-dr1 get storageclass"
    echo "  Ceph Status:     kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph status"
    echo "  Storage Events:  kubectl --context=ramen-dr1 -n rook-ceph get events --sort-by=.metadata.creationTimestamp"
    echo "  OSD Status:      kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd status"
    
    echo ""
    echo -e "${GREEN}📚 Storage Demo Commands:${NC}"
    echo "  Run All Demos:   ./demo/scripts/storage/run-storage-demos.sh all"  
    echo "  Block Demo:      ./demo/scripts/storage/run-storage-demos.sh block"
    echo "  File Demo:       ./demo/scripts/storage/run-storage-demos.sh file"
    echo "  Object Demo:     ./demo/scripts/storage/run-storage-demos.sh object"
    echo "  Test Storage:    ./demo/scripts/storage/run-storage-demos.sh test"
    echo "  Cleanup:         ./demo/scripts/storage/run-storage-demos.sh cleanup"
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Starting RamenDR Storage Demo monitoring..."
    echo "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        storage_monitoring
        sleep 20
    done
fi
