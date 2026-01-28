#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Enhanced RamenDR Regional DR Monitoring Script  
# Comprehensive real-time monitoring for multi-cluster CSI replication testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check contexts for regional DR environment
check_contexts() {
    if [ -z "$KUBECONFIG" ]; then
        echo -e "${YELLOW}⚠️  KUBECONFIG not set, setting to default: ~/.kube/config${NC}"
        export KUBECONFIG=~/.kube/config
    fi
    
    local required_contexts=("hub" "dr1" "dr2")
    for ctx in "${required_contexts[@]}"; do
        if ! kubectl config get-contexts -o name | grep -q "^$ctx$"; then
            echo -e "${RED}❌ Required context '$ctx' not found${NC}"
            echo "Available contexts:"
            kubectl config get-contexts -o name
            exit 1
        fi
    done
    echo -e "${GREEN}✅ All required contexts found: hub, dr1, dr2${NC}"
}

# Enhanced monitoring function
comprehensive_monitoring() {
    clear
    echo "KUBECONFIG: $KUBECONFIG"
    echo "CURRENT_CONTEXT: $(kubectl config current-context 2>/dev/null || echo 'No context set')"

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}                  🔍 RAMENDR REGIONAL DR CSI MONITORING                        ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Timestamp
    echo -e "${CYAN}📅 $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    # CLUSTER INFRASTRUCTURE
    echo -e "${BLUE}=== CLUSTER INFRASTRUCTURE ===${NC}"
    echo "🏗️ Contexts:"
    kubectl config get-contexts | head -n 1  # Header
    kubectl config get-contexts | grep -E "(hub|dr1|dr2)" || echo "  No regional DR contexts found"
    echo ""
    
    # RAMENDR OPERATORS
    echo -e "${YELLOW}=== RAMENDR OPERATORS ===${NC}"
    echo "Hub Operator:"
    kubectl --context=hub get pods -n ramen-system 2>/dev/null || echo "  Hub cluster not accessible"
    echo "DR1 Operator:" 
    kubectl --context=dr1 get pods -n ramen-system 2>/dev/null || echo "  DR1 cluster not accessible"
    echo "DR2 Operator:" 
    kubectl --context=dr2 get pods -n ramen-system 2>/dev/null || echo "  DR2 cluster not accessible"
    echo ""

    # ORCHESTRATION LAYER (Hub)
    echo -e "${PURPLE}=== ORCHESTRATION LAYER (HUB) ===${NC}"
    echo "🌐 ManagedClusters:"
    kubectl --context=hub get managedcluster -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No managedclusters found"
    echo "📋 DRPolicy:"
    kubectl --context=hub get drpolicy -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No DRPolicies found"
    echo "🎯 DRPlacement (DRPC):"
    kubectl --context=hub get drplacementcontrol --all-namespaces -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No DRPCs found"
    echo ""
    echo "🎯 PlacementDecision:"
    kubectl --context=hub get placementdecision --all-namespaces -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No PlacementDecisions found"
    echo ""
    echo "🏢 DRClusters:"
    kubectl --context=hub get drcluster -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No DRClusters found"
    echo ""

    # PROTECTION LAYER (DR)
    echo -e "${CYAN}=== PROTECTION LAYER (DR CLUSTERS) ===${NC}"
    echo "📦 VolumeReplicationGroups (DR1):"
    kubectl --context=dr1 get vrg -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No VRGs found on dr1"
    echo "📦 VolumeReplicationGroups (DR2):"
    kubectl --context=dr2 get vrg -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No VRGs found on dr2"
    echo "🔄 VolumeReplication (DR1):" 
    kubectl --context=dr1 get volumereplication --all-namespaces -o wide 2>/dev/null | grep -v "No resources" || echo "  No VolumeReplications found"
    echo ""

    # STORAGE INFRASTRUCTURE
    echo -e "${GREEN}=== CSI & STORAGE INFRASTRUCTURE ===${NC}"
    echo "📂 VolumeReplicationClass (DR1):"
    kubectl --context=dr1 get volumereplicationclass -o wide 2>/dev/null | grep -v "No resources" || echo "  No VolumeReplicationClasses found"
    echo "📸 VolumeSnapshotClass (DR1):"
    kubectl --context=dr1 get volumesnapshotclass -o wide 2>/dev/null | grep -v "No resources" || echo "  No VolumeSnapshotClasses found"
    echo "💾 StorageClass (DR1):"
    kubectl --context=dr1 get storageclass 2>/dev/null || echo "  No StorageClasses found"
    echo "💾 StorageClass (DR2):"
    kubectl --context=dr2 get storageclass 2>/dev/null || echo "  No StorageClasses found"
    echo ""

    # CEPH STORAGE STATUS
    echo -e "${CYAN}=== CEPH STORAGE STATUS ===${NC}"
    echo "🏗️ Ceph Cluster (DR1):"
    kubectl --context=dr1 -n rook-ceph get cephcluster -o wide 2>/dev/null || echo "  No CephCluster found on dr1"
    echo "🏗️ Ceph Cluster (DR2):"
    kubectl --context=dr2 -n rook-ceph get cephcluster -o wide 2>/dev/null || echo "  No CephCluster found on dr2"
    echo "💾 Ceph BlockPool (DR1):"
    kubectl --context=dr1 -n rook-ceph get cephblockpool -o wide 2>/dev/null || echo "  No CephBlockPool found on dr1"
    echo "💾 Ceph BlockPool (DR2):"
    kubectl --context=dr2 -n rook-ceph get cephblockpool -o wide 2>/dev/null || echo "  No CephBlockPool found on dr2"
    echo ""

    # RBD MIRROR STATUS
    echo -e "${YELLOW}=== RBD MIRRORING STATUS ===${NC}"
    echo "🪞 RBD Mirror (DR1):"
    kubectl --context=dr1 -n rook-ceph get deployment rook-ceph-rbd-mirror-a 2>/dev/null || echo "  RBD Mirror not found on dr1"
    echo "🪞 RBD Mirror (DR2):"
    kubectl --context=dr2 -n rook-ceph get deployment rook-ceph-rbd-mirror-a 2>/dev/null || echo "  RBD Mirror not found on dr2"
    echo ""

    # APPLICATION STATUS
    echo -e "${PURPLE}=== PROTECTED APPLICATIONS ===${NC}"
    echo "🚀 Test Applications (DR1):"
    kubectl --context=dr1 get pods,pvc -A | grep -E "(test|demo|sample)" | head -5 || echo "  No test applications found on dr1"
    echo "🚀 Test Applications (DR2):"
    kubectl --context=dr2 get pods,pvc -A | grep -E "(test|demo|sample)" | head -5 || echo "  No test applications found on dr2"
    echo ""

    # S3 BACKUP STATUS
    echo -e "${BLUE}=== S3 BACKUP INFRASTRUCTURE ===${NC}"
    echo "🪣 S3 MinIO Status (Hub):"
    kubectl --context=hub get pods,svc -n minio-system 2>/dev/null | grep -v "No resources" || echo "  MinIO not found in hub cluster"
    echo "🪣 S3 MinIO Status (DR1):"
    kubectl --context=dr1 get pods,svc -n minio-system 2>/dev/null | grep -v "No resources" || echo "  MinIO not found in dr1 cluster"
    echo "🪣 S3 MinIO Status (DR2):"
    kubectl --context=dr2 get pods,svc -n minio-system 2>/dev/null | grep -v "No resources" || echo "  MinIO not found in dr2 cluster"
    echo ""

    # RESOURCE METRICS (if metrics-server available)
    echo -e "${GREEN}=== RESOURCE METRICS ===${NC}"
    echo "📊 Node Resources (DR1):"
    kubectl --context=dr1 top nodes 2>/dev/null || echo "  Metrics not available"
    echo "📊 Node Resources (DR2):"
    kubectl --context=dr2 top nodes 2>/dev/null || echo "  Metrics not available"
    echo ""

    # HELPFUL COMMANDS
    echo -e "${CYAN}=== QUICK ACCESS COMMANDS ===${NC}"
    echo "🔍 Check VRG conditions: kubectl --context=dr1 describe vrg -n <namespace>"
    echo "📋 Check DRPC status: kubectl --context=hub describe drplacementcontrol -n <namespace>"
    echo "📊 Monitor DR operator logs: kubectl --context=dr1 logs -n ramen-system deployment/ramen-dr-cluster-operator -f"
    echo "🪞 Check RBD mirror status: kubectl --context=dr1 -n rook-ceph exec deployment/rook-ceph-tools -- rbd mirror pool status replicapool"
    echo "💾 List Ceph pools: kubectl --context=dr1 -n rook-ceph exec deployment/rook-ceph-tools -- ceph osd pool ls"
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to display monitoring options
show_monitoring_options() {
    echo -e "${BLUE}📊 RamenDR Regional DR Monitoring Options:${NC}"
    echo ""
    echo "1. 🏗️  Cluster & Infrastructure Monitoring"
    echo "2. 📦 Application & DR Resources Monitoring"  
    echo "3. 💾 Storage & VRG Monitoring"
    echo "4. ⚙️  Operators & CRDs Monitoring"
    echo "5. 🪞 Ceph & RBD Mirroring Monitoring"
    echo "6. 🔄 Comprehensive All-in-One Monitoring"
    echo "7. 🌐 MinIO Console Access Setup"
    echo "8. 📋 Show All Commands (for copy-paste)"
    echo "9. ❓ Help & Examples"
    echo ""
}

# Cluster monitoring
cluster_monitoring() {
    echo -e "${GREEN}🏗️  Starting Cluster & Infrastructure Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • Cluster contexts and connectivity"
    echo "  • RamenDR operator pods"
    echo "  • OCM components"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 2 '
        echo "=== REGIONAL DR CLUSTERS ===" && 
        kubectl config get-contexts | head -n 1 && 
        kubectl config get-contexts | grep -E "(hub|dr1|dr2)" && 
        echo "" && 
        echo "=== RAMEN OPERATORS ===" && 
        kubectl --context=hub get pods -n ramen-system 2>/dev/null | head -3 && 
        kubectl --context=dr1 get pods -n ramen-system 2>/dev/null | head -3 && 
        kubectl --context=dr2 get pods -n ramen-system 2>/dev/null | head -3
    '
}

# Application monitoring  
app_monitoring() {
    echo -e "${GREEN}📦 Starting Application & DR Resources Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • DRClusters and DRPolicies (Hub)"
    echo "  • VRGs, Pods, and PVCs (DR clusters)"
    echo "  • DRPC placement decisions"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 3 '
        echo "=== DR RESOURCES (Hub) ===" && 
        kubectl --context=hub get drclusters,drpolicy,drplacementcontrol -A 2>/dev/null || echo "Not ready yet" && 
        echo "" && 
        echo "=== VRG & APPLICATIONS (DR1) ===" && 
        kubectl --context=dr1 get vrg,pods,pvc -A 2>/dev/null | head -8 || echo "Not ready yet" && 
        echo "" && 
        echo "=== VRG & APPLICATIONS (DR2) ===" && 
        kubectl --context=dr2 get vrg,pods,pvc -A 2>/dev/null | head -6 || echo "Not ready yet"
    '
}

# Storage monitoring
storage_monitoring() {
    echo -e "${GREEN}💾 Starting Storage & VRG Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • VRGs and VolumeReplications"
    echo "  • Ceph storage pools and classes"
    echo "  • Volume snapshots and replication classes"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 5 '
        echo "=== STORAGE CLASSES ===" && 
        kubectl --context=dr1 get storageclass 2>/dev/null && 
        echo "" && 
        echo "=== VRG RESOURCES (DR1) ===" && 
        kubectl --context=dr1 get vrg,volumereplication -A 2>/dev/null || echo "VRG resources not ready" && 
        echo "" && 
        echo "=== VOLUME REPLICATION CLASSES ===" && 
        kubectl --context=dr1 get volumereplicationclass 2>/dev/null || echo "No VRC found" && 
        echo "" && 
        echo "=== CEPH BLOCK POOLS ===" && 
        kubectl --context=dr1 -n rook-ceph get cephblockpool 2>/dev/null || echo "No Ceph pools found"
    '
}

# Operators monitoring
operators_monitoring() {
    echo -e "${GREEN}⚙️  Starting Operators & CRDs Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • RamenDR operators on all clusters"
    echo "  • RamenDR CRDs installation status"
    echo "  • CSI addons and external snapshotter"
    echo "  • Rook operators"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 3 '
        echo "=== RAMENDR CRDS ===" && 
        kubectl --context=hub get crd | grep ramen && 
        echo "" && 
        echo "=== RAMENDR HUB OPERATOR ===" && 
        kubectl --context=hub get pods,deployments -n ramen-system 2>/dev/null | head -4 && 
        echo "" && 
        echo "=== RAMENDR DR1 OPERATOR ===" && 
        kubectl --context=dr1 get pods,deployments -n ramen-system 2>/dev/null | head -3 && 
        echo "" && 
        echo "=== CSI ADDONS ===" && 
        kubectl --context=dr1 get pods -n csi-addons-system 2>/dev/null | head -3 || echo "CSI addons not ready" && 
        echo "" && 
        echo "=== ROOK OPERATOR ===" && 
        kubectl --context=dr1 get pods -n rook-ceph | grep operator | head -3 || echo "Rook not ready"
    '
}

# Ceph and RBD mirroring monitoring
ceph_monitoring() {
    echo -e "${GREEN}🪞 Starting Ceph & RBD Mirroring Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • Ceph cluster health"
    echo "  • RBD mirroring daemons"
    echo "  • Pool mirroring status"
    echo "  • OSD status"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 5 '
        echo "=== CEPH CLUSTERS ===" && 
        kubectl --context=dr1 -n rook-ceph get cephcluster 2>/dev/null && 
        kubectl --context=dr2 -n rook-ceph get cephcluster 2>/dev/null && 
        echo "" && 
        echo "=== RBD MIRROR DAEMONS ===" && 
        kubectl --context=dr1 -n rook-ceph get pods | grep rbd-mirror || echo "No RBD mirror on dr1" && 
        kubectl --context=dr2 -n rook-ceph get pods | grep rbd-mirror || echo "No RBD mirror on dr2" && 
        echo "" && 
        echo "=== CEPH HEALTH (DR1) ===" && 
        kubectl --context=dr1 -n rook-ceph exec deployment/rook-ceph-tools -- ceph status 2>/dev/null | head -10 || echo "Ceph tools not ready"
    '
}

# MinIO console setup
minio_console() {
    echo -e "${GREEN}🌐 Setting up MinIO Console Access...${NC}"
    echo ""
    
    # Check which cluster has MinIO
    local minio_cluster=""
    for cluster in hub dr1 dr2; do
        if kubectl --context=$cluster get namespace minio-system >/dev/null 2>&1; then
            minio_cluster=$cluster
            break
        fi
    done
    
    if [ -n "$minio_cluster" ]; then
        echo "Found MinIO on cluster: $minio_cluster"
        
        # Kill existing port-forwards
        pkill -f "kubectl port-forward.*minio" >/dev/null 2>&1 || true
        
        echo "Starting MinIO console port-forwarding on cluster $minio_cluster..."
        kubectl --context=$minio_cluster port-forward -n minio-system service/minio 9001:9001 > /dev/null 2>&1 &
        sleep 3
        
        echo ""
        echo -e "${GREEN}✅ MinIO Console Setup Complete!${NC}"
        echo ""
        echo "🌐 Access URLs:"
        echo "  • Console: http://localhost:9001"
        echo "  • API: http://localhost:9000"
        echo ""
        echo "🔑 Credentials:"
        echo "  • Username: minioadmin"
        echo "  • Password: minioadmin"
        echo ""
        echo "📦 Expected S3 Bucket: ramen-metadata"
    else
        echo -e "${YELLOW}⚠️  MinIO not found on any cluster${NC}"
    fi
}

# Show all commands for copy-paste
show_commands() {
    echo -e "${BLUE}📋 All Monitoring Commands (Copy-Paste Ready):${NC}"
    echo ""
    
    echo -e "${PURPLE}# Terminal 2: Cluster & Infrastructure Monitoring${NC}"
    echo 'watch -n 2 "
        echo \"=== REGIONAL DR CLUSTERS ===\" && 
        kubectl config get-contexts | head -n 1 && 
        kubectl config get-contexts | grep -E \"(hub|dr1|dr2)\" && 
        echo \"\" && 
        echo \"=== RAMEN OPERATORS ===\" && 
        kubectl --context=hub get pods -n ramen-system 2>/dev/null | head -3 && 
        kubectl --context=dr1 get pods -n ramen-system 2>/dev/null | head -3
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 3: Application & DR Resources${NC}"
    echo 'watch -n 3 "
        echo \"=== DR RESOURCES (Hub) ===\" && 
        kubectl --context=hub get drclusters,drpolicy,drplacementcontrol -A 2>/dev/null || echo \"Not ready\" && 
        echo \"\" && 
        echo \"=== VRG & APPS (DR1) ===\" && 
        kubectl --context=dr1 get vrg,pods,pvc -A 2>/dev/null | head -8
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 4: Storage & Ceph Monitoring${NC}"
    echo 'watch -n 5 "
        kubectl --context=dr1 get storageclass,volumereplicationclass 2>/dev/null && 
        kubectl --context=dr1 -n rook-ceph get cephblockpool,cephcluster 2>/dev/null | head -5
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 5: MinIO Console${NC}"
    echo "./regional-dr-monitoring.sh # Choose option 7"
    echo ""
    
    echo -e "${PURPLE}# Comprehensive All-in-One Monitoring${NC}"
    echo "./regional-dr-monitoring.sh # Choose option 6"
}

# Help and examples
show_help() {
    echo -e "${BLUE}❓ RamenDR Regional DR Monitoring Help${NC}"
    echo ""
    echo -e "${PURPLE}🎯 Quick Start:${NC}"
    echo "  1. Ensure your regional DR environment is running"
    echo "  2. Run: ./regional-dr-monitoring.sh"
    echo "  3. Choose option 6 for comprehensive monitoring"
    echo "  4. Or use option 8 to copy commands to separate terminals"
    echo ""
    echo -e "${PURPLE}📊 Resource Explanations:${NC}"
    echo "  • vrg: VolumeReplicationGroup (RamenDR's core resource)"
    echo "  • volumereplication: CSI-level volume replication"
    echo "  • drclusters: Disaster Recovery cluster definitions"
    echo "  • drpolicy: DR policies and schedules"
    echo "  • drplacementcontrol: DR placement decisions"
    echo "  • cephcluster/cephblockpool: Ceph storage resources"
    echo "  • rbd-mirror: RBD mirroring daemon for cross-cluster replication"
    echo ""
    echo -e "${PURPLE}⚡ Regional DR Tips:${NC}"
    echo "  • Monitor all 3 clusters: hub (management), dr1 (primary), dr2 (secondary)"
    echo "  • Check RBD mirror health for CSI replication"
    echo "  • VRG resources show protection status"
    echo "  • Use MinIO console to monitor S3 metadata backups"
    echo ""
    echo -e "${PURPLE}🔧 Troubleshooting:${NC}"
    echo "  • If contexts not found: check drenv environment is running"
    echo "  • If no resources shown: operators may still be starting"
    echo "  • If Ceph issues: check rook-ceph namespace pods"
    echo "  • For RBD mirror status: exec into rook-ceph-tools pod"
}

# Main menu
main() {
    # Check contexts first
    check_contexts
    
    if [ $# -eq 1 ] && [ "$1" == "comprehensive" ]; then
        # Direct comprehensive monitoring without menu
        while true; do
            comprehensive_monitoring
            sleep 5
        done
    fi
    
    while true; do
        show_monitoring_options
        read -p "Choose an option (1-9) or 'q' to quit: " choice
        echo ""
        
        case $choice in
            1) cluster_monitoring ;;
            2) app_monitoring ;;
            3) storage_monitoring ;;
            4) operators_monitoring ;;
            5) ceph_monitoring ;;
            6) 
                echo -e "${GREEN}🔄 Starting Comprehensive All-in-One Monitoring...${NC}"
                echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
                sleep 2
                while true; do
                    comprehensive_monitoring
                    sleep 5
                done
                ;;
            7) minio_console ;;
            8) show_commands ;;
            9) show_help ;;
            q|Q) echo "Exiting..."; exit 0 ;;
            *) echo -e "${RED}❌ Invalid option. Please choose 1-9 or 'q'${NC}"; echo ;;
        esac
        
        if [ "$choice" != "7" ] && [ "$choice" != "8" ] && [ "$choice" != "9" ]; then
            echo ""
            echo -e "${YELLOW}Press any key to return to menu...${NC}"
            read -n 1 -s
            echo ""
        fi
    done
}

# Run main function
main "$@"