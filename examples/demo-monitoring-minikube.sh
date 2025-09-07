#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# RamenDR Demo Monitoring Script for minikube
# Provides comprehensive real-time monitoring for RamenDR demonstrations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# KUBECONFIG check for minikube demo
check_kubeconfig_for_minikube() {
    if [ -z "$KUBECONFIG" ]; then
        echo -e "${YELLOW}⚠️  KUBECONFIG not set, setting to default: ~/.kube/config${NC}"
        export KUBECONFIG=~/.kube/config
    fi
    
    # Check for minikube contexts (ramen-*)
    local minikube_contexts=$(kubectl config get-contexts -o name 2>/dev/null | grep "^ramen-" | wc -l)
    if [ "$minikube_contexts" -eq 0 ]; then
        echo -e "${RED}❌ No minikube contexts found (ramen-*)${NC}"
        echo ""
        echo "🔧 To fix this:"
        echo "   minikube update-context --profile=ramen-hub"
        echo "   minikube update-context --profile=ramen-dr1"
        echo "   kubectl config get-contexts"
        echo ""
        echo "Or run: ./scripts/setup-minikube.sh"
        exit 1
    fi
    echo -e "${GREEN}✅ Minikube contexts available ($minikube_contexts found)${NC}"
}

# Check KUBECONFIG before starting
check_kubeconfig_for_minikube

echo -e "${PURPLE}🎬 RamenDR Demo Monitoring Helper (minikube)${NC}"
echo "=============================================="
echo ""
echo "This script helps you set up comprehensive monitoring for RamenDR minikube demos."
echo ""

# Function to display monitoring options
show_monitoring_options() {
    echo -e "${BLUE}📊 Available Monitoring Options:${NC}"
    echo ""
    echo "1. 🏗️  Cluster & Infrastructure Monitoring"
    echo "2. 📦 Application & DR Resources Monitoring"  
    echo "3. 💾 Storage & VRG Monitoring"
    echo "4. ⚙️  Operators & CRDs Monitoring"
    echo "5. 🔄 All-in-One Comprehensive Monitoring"
    echo "6. 🌐 MinIO Console Access Setup"
    echo "7. 📋 Show All Commands (for copy-paste)"
    echo "8. ❓ Help & Examples"
    echo ""
}

# Cluster monitoring
cluster_monitoring() {
    echo -e "${GREEN}🏗️  Starting Cluster & Infrastructure Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • minikube clusters status"
    echo "  • Kubectl contexts"
    echo "  • RamenDR operator pods"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 2 '
        echo "=== MINIKUBE CLUSTERS ===" && 
        minikube profile list 2>/dev/null | tail -n +2 || echo "minikube not available" && 
        echo "" && 
        echo "=== CONTEXTS ===" && 
        kubectl config get-contexts | grep ramen && 
        echo "" && 
        echo "=== RAMEN PODS ===" && 
        kubectl get pods -A | grep ramen | head -5
    '
}

# Application monitoring  
app_monitoring() {
    echo -e "${GREEN}📦 Starting Application & DR Resources Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • DRClusters and DRPolicies (Hub)"
    echo "  • VRGs, Pods, and PVCs (DR clusters)"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 3 '
        echo "=== DR RESOURCES (Hub) ===" && 
        kubectl --context=ramen-hub get drclusters,drpolicies -n ramen-system 2>/dev/null || echo "Not ready yet" && 
        echo "" && 
        echo "=== VRG & APPLICATIONS (DR1) ===" && 
        kubectl --context=ramen-dr1 get vrg,pods,pvc -A 2>/dev/null | head -8 || echo "Not ready yet" && 
        echo "" && 
        echo "=== CURRENT CONTEXT ===" && 
        kubectl config current-context
    '
}

# Storage monitoring (adapted for minikube CSI)
storage_monitoring() {
    echo -e "${GREEN}💾 Starting Storage & VRG Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • VRGs and VolumeReplications"
    echo "  • Pods, PVCs with CSI hostpath driver"
    echo "  • Storage classes and volume snapshots"
    echo "  • VolSync replication resources"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 5 '
        echo "=== VRG RESOURCES (DR1) ===" && 
        kubectl --context=ramen-dr1 get vrg,volumereplication,replicationsource,replicationdestination -A 2>/dev/null || echo "VRG resources not ready" && 
        echo "" && 
        echo "=== STORAGE CLASSES (minikube CSI) ===" && 
        kubectl --context=ramen-dr1 get storageclass 2>/dev/null && 
        echo "" && 
        echo "=== VOLUME SNAPSHOTS (CSI) ===" && 
        kubectl --context=ramen-dr1 get volumesnapshots,volumesnapshotcontents -A 2>/dev/null | head -5 || echo "No snapshots found" && 
        echo "" && 
        echo "=== PERSISTENT VOLUMES ===" && 
        kubectl --context=ramen-dr1 get pv,pvc -A 2>/dev/null | head -5 || echo "No PVs found"
    '
}

# Operators and CRDs monitoring
operators_monitoring() {
    echo -e "${GREEN}⚙️  Starting Operators & CRDs Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • RamenDR operators on all clusters"
    echo "  • RamenDR CRDs installation status"
    echo "  • VolSync and External Snapshotter operators"
    echo "  • Storage and replication CRDs"
    echo "  • MinIO operator and pods"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 3 '
        echo "=== RAMENDR CRDS ===" && 
        kubectl --context=ramen-hub get crd | grep ramen && 
        echo "" && 
        echo "=== RAMENDR HUB OPERATOR ===" && 
        kubectl --context=ramen-hub get pods,deployments -n ramen-system 2>/dev/null | head -4 && 
        echo "" && 
        echo "=== RAMENDR DR1 OPERATOR ===" && 
        kubectl --context=ramen-dr1 get pods,deployments -n ramen-system 2>/dev/null | head -3 && 
        echo "" && 
        echo "=== VOLSYNC OPERATOR ===" && 
        kubectl --context=ramen-dr1 get pods -n volsync-system 2>/dev/null | head -3 || echo "VolSync not deployed" && 
        echo "" && 
        echo "=== STORAGE CRDS (CSI-enabled) ===" && 
        kubectl --context=ramen-dr1 get crd | grep -E "(snapshot|replication|volume)" | head -5 && 
        echo "" && 
        echo "=== MINIO OPERATOR ===" && 
        kubectl --context=ramen-hub get pods -n minio-system 2>/dev/null | head -3 || echo "MinIO not deployed"
    '
}

# Comprehensive monitoring
comprehensive_monitoring() {
    echo -e "${GREEN}🔄 Starting Comprehensive All-in-One Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • Clusters, contexts, and operator pods"
    echo "  • DR resources across all clusters"
    echo "  • RamenDR and related CRDs"
    echo "  • Operators (RamenDR, VolSync, External Snapshotter)"
    echo "  • Storage with CSI hostpath driver"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 3 '
        echo "=== MINIKUBE PROFILES & CONTEXTS ===" && 
        minikube profile list 2>/dev/null | tail -n +2 || echo "minikube profiles not available" && 
        echo "" && 
        kubectl config get-contexts | grep ramen && 
        echo "" && 
        echo "=== RAMENDR CRDS ===" && 
        kubectl --context=ramen-hub get crd | grep ramen | head -5 && 
        echo "" && 
        echo "=== HUB OPERATORS & RESOURCES ===" && 
        kubectl --context=ramen-hub get pods,drclusters,drpolicies -n ramen-system 2>/dev/null | head -6 && 
        echo "" && 
        echo "=== DR1 OPERATORS & VRG ===" && 
        kubectl --context=ramen-dr1 get pods -n ramen-system 2>/dev/null && 
        kubectl --context=ramen-dr1 get vrg,pvc -A 2>/dev/null | head -4 && 
        echo "" && 
        echo "=== STORAGE DEPS (minikube CSI) ===" && 
        kubectl --context=ramen-dr1 get pods -n volsync-system 2>/dev/null | head -3 || echo "VolSync not ready" && 
        echo "" && 
        echo "=== SNAPSHOT CRDS ===" && 
        kubectl --context=ramen-dr1 get crd | grep snapshot | head -3
    '
}

# MinIO console setup
minio_console() {
    echo -e "${GREEN}🌐 Setting up MinIO Console Access...${NC}"
    echo ""
    
    # Kill existing port-forwards
    pkill -f "kubectl port-forward.*minio" >/dev/null 2>&1 || true
    
    echo "Starting MinIO console port-forwarding..."
    kubectl --context=ramen-hub port-forward -n minio-system service/minio 9001:9001 > /dev/null 2>&1 &
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
    echo ""
    
    # Test connectivity
    if curl -s http://localhost:9001 >/dev/null; then
        echo -e "${GREEN}✅ Console is accessible!${NC}"
    else
        echo -e "${YELLOW}⚠️  Console starting up... (try in a few seconds)${NC}"
    fi
}

# Show all commands
show_commands() {
    echo -e "${BLUE}📋 All Monitoring Commands (Copy-Paste Ready):${NC}"
    echo ""
    
    echo -e "${PURPLE}# Terminal 2: Cluster & Infrastructure Monitoring${NC}"
    echo 'watch -n 2 "
        echo \"=== MINIKUBE CLUSTERS ===\" && 
        minikube profile list 2>/dev/null | tail -n +2 || echo \"minikube not available\" && 
        echo \"\" && 
        echo \"=== CONTEXTS ===\" && 
        kubectl config get-contexts | grep ramen && 
        echo \"\" && 
        echo \"=== RAMEN PODS ===\" && 
        kubectl get pods -A | grep ramen | head -5
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 3: Application & DR Resources${NC}"
    echo 'watch -n 3 "
        echo \"=== DR RESOURCES (Hub) ===\" && 
        kubectl --context=ramen-hub get drclusters,drpolicies -n ramen-system 2>/dev/null || echo \"Not ready\" && 
        echo \"\" && 
        echo \"=== VRG & APPS (DR1) ===\" && 
        kubectl --context=ramen-dr1 get vrg,pods,pvc -A 2>/dev/null | head -8
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 4: Operators & CRDs Monitoring${NC}"
    echo 'watch -n 3 "
        echo \"=== RAMENDR CRDS ===\" && 
        kubectl --context=ramen-hub get crd | grep ramen && 
        echo \"\" && 
        echo \"=== HUB OPERATOR ===\" && 
        kubectl --context=ramen-hub get pods,deployments -n ramen-system 2>/dev/null | head -4 && 
        echo \"\" && 
        echo \"=== DR1 OPERATOR ===\" && 
        kubectl --context=ramen-dr1 get pods,deployments -n ramen-system 2>/dev/null | head -3 && 
        echo \"\" && 
        echo \"=== VOLSYNC ===\" && 
        kubectl --context=ramen-dr1 get pods -n volsync-system 2>/dev/null | head -3
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 5: Storage & VRG (minikube CSI)${NC}"
    echo 'watch -n 5 "
        kubectl --context=ramen-dr1 get vrg,volumereplication,pvc,volumesnapshots -A 2>/dev/null | head -10 || echo \"Storage resources not ready\"
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 6: MinIO Console${NC}"
    echo "./examples/demo-monitoring-minikube.sh (option 6)"
    echo ""
    
    echo -e "${PURPLE}# Comprehensive All-in-One Monitoring${NC}"
    echo 'watch -n 3 "
        echo \"=== RAMENDR CRDS ===\" && 
        kubectl --context=ramen-hub get crd | grep ramen | head -5 && 
        echo \"\" && 
        echo \"=== HUB OPERATORS ===\" && 
        kubectl --context=ramen-hub get pods,drclusters,drpolicies -n ramen-system 2>/dev/null | head -6 && 
        echo \"\" && 
        echo \"=== DR1 OPERATORS & VRG ===\" && 
        kubectl --context=ramen-dr1 get pods -n ramen-system 2>/dev/null && 
        kubectl --context=ramen-dr1 get vrg,pvc -A 2>/dev/null | head -4
    "'
}

# Help and examples
show_help() {
    echo -e "${BLUE}❓ RamenDR Demo Monitoring Help (minikube)${NC}"
    echo ""
    echo -e "${PURPLE}🎯 Quick Start:${NC}"
    echo "  1. Run: ./examples/demo-monitoring-minikube.sh"
    echo "  2. Choose option 7 to see all commands"
    echo "  3. Copy commands to separate terminals"
    echo "  4. Start monitoring before running demo"
    echo ""
    echo -e "${PURPLE}📊 Resource Explanations:${NC}"
    echo "  • vrg: VolumeReplicationGroup (RamenDR's core resource)"
    echo "  • volumereplication: Storage-level replication"
    echo "  • drclusters: Disaster Recovery cluster definitions"
    echo "  • drpolicies: DR policies and schedules"
    echo "  • crd: Custom Resource Definitions (Kubernetes extensions)"
    echo "  • deployments: Kubernetes operator deployments"
    echo "  • volumesnapshots: CSI-enabled snapshots (minikube feature)"
    echo ""
    echo -e "${PURPLE}⚡ minikube-Specific Tips:${NC}"
    echo "  • minikube uses hostpath CSI driver for realistic storage"
    echo "  • Volume snapshots work with CSI (unlike kind)"
    echo "  • Use different refresh intervals: 2s for infrastructure, 3s for apps, 5s for storage"
    echo "  • MinIO console: http://localhost:9001 (minioadmin/minioadmin)"
    echo "  • Contexts: ramen-hub, ramen-dr1 (instead of kind-* names)"
    echo ""
    echo -e "${PURPLE}🔧 Troubleshooting:${NC}"
    echo "  • If contexts not found: run 'minikube update-context --profile=<profile>'"
    echo "  • If no resources shown: operators may still be starting"
    echo "  • If storage issues: check 'kubectl get storageclass' shows hostpath"
    echo "  • Missing ramen-dr2: that's expected (creation often fails)"
}

# Main menu
main() {
    while true; do
        show_monitoring_options
        read -p "Choose an option (1-8) or 'q' to quit: " choice
        echo ""
        
        case $choice in
            1) cluster_monitoring ;;
            2) app_monitoring ;;
            3) storage_monitoring ;;
            4) operators_monitoring ;;
            5) comprehensive_monitoring ;;
            6) minio_console ;;
            7) show_commands ;;
            8) show_help ;;
            q|Q) echo "Exiting..."; exit 0 ;;
            *) echo -e "${RED}❌ Invalid option. Please choose 1-8 or 'q'${NC}"; echo ;;
        esac
        
        echo ""
        echo -e "${YELLOW}Press any key to return to menu...${NC}"
        read -n 1 -s
        echo ""
    done
}

# Run main function
main
