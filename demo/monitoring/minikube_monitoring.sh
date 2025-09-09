#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Enhanced RamenDR Demo Monitoring Script for minikube
# Comprehensive real-time monitoring for all RamenDR components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Enhanced monitoring function
comprehensive_monitoring() {
    clear
    echo  "KUBECONFIG: $KUBECONFIG"
    echo  "CURRENT_CONTEXT: $(kubectl config current-context)"

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}                    🔍 ENHANCED RAMENDR MINIKUBE MONITORING                    ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Timestamp
    echo -e "${CYAN}📅 $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    # MINIKUBE INFRASTRUCTURE
    echo -e "${BLUE}=== MINIKUBE INFRASTRUCTURE ===${NC}"
    minikube profile list 2>/dev/null | tail -n +2 || echo "minikube not available"
    echo ""
    
    # KUBERNETES CONTEXTS  
    echo -e "${BLUE}=== KUBERNETES CONTEXTS ===${NC}"
    # Update contexts first to ensure they're available
    for profile in ramen-hub ramen-dr1 ramen-dr2; do
        env KUBECONFIG="" minikube update-context --profile=$profile >/dev/null 2>&1 || true
    done
    
    # Show available ramen contexts
    local contexts=$(kubectl config get-contexts -o name | grep "^ramen-" 2>/dev/null || true)
    if [ -n "$contexts" ]; then
        kubectl config get-contexts | head -n 1  # Header
        kubectl config get-contexts | grep ramen
    else
        echo "No ramen contexts found"
    fi
    echo ""

    # RAMENDR OPERATORS
    echo -e "${YELLOW}=== RAMENDR OPERATORS ===${NC}"
    echo "Hub Operator (ramen-hub):"
    kubectl --context=ramen-hub get pods -n ramen-system -l app=ramen-hub 2>/dev/null || echo "  Hub cluster not accessible"
    echo "DR Cluster Operator (ramen-dr1):" 
    kubectl --context=ramen-dr1 get pods -n ramen-system -l app=ramen-dr-cluster 2>/dev/null || echo "  DR1 cluster not accessible"
    echo "DR Cluster Operator (ramen-dr2):" 
    kubectl --context=ramen-dr2 get pods -n ramen-system -l app=ramen-dr-cluster 2>/dev/null || echo "  DR1 cluster not accessible"
    echo ""

    # ORCHESTRATION LAYER (Hub)
    echo -e "${PURPLE}=== ORCHESTRATION LAYER (HUB) ===${NC}"
    echo "📋 DRPolicy:"
    kubectl --context=ramen-hub get drpolicy -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No DRPolicies found"
    echo "🎯 DRPlacementControl (DRPC):"
    kubectl --context=ramen-hub get drplacementcontrol -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No DRPCs found"
    echo ""
    echo "�� DRClusters:"
    kubectl --context=ramen-hub get drcluster -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No DRClusters found"
    echo ""

    # PROTECTION LAYER (DR)
    echo -e "${CYAN}=== PROTECTION LAYER (DR CLUSTERS) ===${NC}"
    echo "📦 VolumeReplicationGroups (VRG):"
    kubectl --context=ramen-dr1 get vrg -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No VRGs found on ramen-dr1"
    echo "🔄 VolSync Resources:"
    kubectl --context=ramen-dr1 get replicationsource,replicationdestination -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No VolSync resources found"
    echo "💾 Volume Replication:" 
    kubectl --context=ramen-dr1 get volumereplication -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No VolumeReplications found"
    echo ""

    # STORAGE CLASSES & SNAPSHOTS
    echo -e "${GREEN}=== STORAGE INFRASTRUCTURE ===${NC}"
    echo "📂 VolumeReplicationClass:"
    kubectl --context=ramen-dr1 get volumereplicationclass -o wide 2>/dev/null | grep -v "No resources" || echo "  No VolumeReplicationClasses found"
    echo "📸 VolumeSnapshotClass:"
    kubectl --context=ramen-dr1 get volumesnapshotclass -o wide 2>/dev/null | grep -v "No resources" || echo "  No VolumeSnapshotClasses found"
    echo ""

    # APPLICATION STATUS
    echo -e "${YELLOW}=== PROTECTED APPLICATIONS ===${NC}"
    echo "🚀 Pods & PVCs (nginx-demo):"
    kubectl --context=ramen-dr1 get pods,pvc -n nginx-demo -o wide 2>/dev/null | grep -v "No resources" || echo "  No resources in nginx-demo namespace"
    echo ""

    # S3 BACKUP STATUS
    echo -e "${PURPLE}=== S3 BACKUP INFRASTRUCTURE ===${NC}"
    echo "🪣 S3 MinIO Status:"
    kubectl --context=ramen-hub get pods,svc -n minio-system 2>/dev/null | grep -v "No resources" || echo "  MinIO not found in cluster"
    echo ""
    echo "📦 S3 Bucket Contents:"
    # Try both mc aliases (check multiple possible locations)
    if command -v mc >/dev/null 2>&1; then
        mc ls minio-local/ramen-metadata/ --recursive 2>/dev/null | head -5 || \
        mc ls minio-host/ramen-metadata/ --recursive 2>/dev/null | head -5 || \
        echo "  No backup data found"
    elif [ -f "./mc" ]; then
        ./mc ls minio-local/ramen-metadata/ --recursive 2>/dev/null | head -5 || \
        ./mc ls minio-host/ramen-metadata/ --recursive 2>/dev/null | head -5 || \
        echo "  No backup data found"
    else
        echo "  MinIO client (mc) not found"
    fi
    echo ""

    # HELPFUL COMMANDS
    echo -e "${CYAN}=== QUICK ACCESS COMMANDS ===${NC}"
    echo "🌐 MinIO Console: http://192.168.50.14:9001 (minioadmin/minioadmin)"
    echo "🔍 Check VRG conditions: kubectl --context=ramen-dr1 describe vrg -n nginx-demo"
    echo "📋 Check DRPC status: kubectl --context=ramen-hub describe drpc -n nginx-demo"
    echo "📊 Monitor logs: kubectl --context=ramen-dr1 logs -n ramen-system deployment/ramen-dr-cluster-operator -f"
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Starting enhanced RamenDR monitoring..."
    echo "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        comprehensive_monitoring
        sleep 15
    done
fi
