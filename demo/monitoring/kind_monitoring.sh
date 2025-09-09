#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# RamenDR Demo Monitoring Script
# Provides comprehensive real-time monitoring for RamenDR demonstrations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# KUBECONFIG check for kind demo
check_kubeconfig_for_kind() {
    if [ -z "$KUBECONFIG" ]; then
        echo -e "${YELLOW}⚠️  KUBECONFIG not set, setting to default: ~/.kube/config${NC}"
        export KUBECONFIG=~/.kube/config
    fi
    
    # Check for kind contexts
    if ! kubectl config get-contexts 2>/dev/null | grep -q "kind-"; then
        echo -e "${RED}❌ No kind contexts found${NC}"
        echo ""
        echo "🔧 To fix this:"
        echo "   export KUBECONFIG=~/.kube/config"
        echo "   kubectl config get-contexts"
        echo ""
        echo "Or run: ../../scripts/fix-kubeconfig.sh"
        exit 1
    fi
    echo -e "${GREEN}✅ Kind contexts available${NC}"
}

# Check KUBECONFIG before starting
check_kubeconfig_for_kind

echo -e "${PURPLE}🎬 RamenDR Demo Monitoring Helper${NC}"
echo "=================================="
echo ""
echo "This script helps you set up comprehensive monitoring for RamenDR demos."
echo ""

# Function to display monitoring options
show_monitoring_options() {
    echo -e "${BLUE}📊 Available Monitoring Options:${NC}"
    echo ""
    echo "1. 🏗️  Cluster & Infrastructure Monitoring"
    echo "2. 📦 Application & DR Resources Monitoring"  
    echo "3. 💾 KubeVirt & Storage Resources Monitoring"
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
    echo "  • Kind clusters status"
    echo "  • Kubectl contexts"
    echo "  • RamenDR operator pods"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 2 '
        echo "=== CLUSTERS ===" && 
        kind get clusters && 
        echo "" && 
        echo "=== CONTEXTS ===" && 
        kubectl config get-contexts | grep kind && 
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
        kubectl --context=kind-ramen-hub get drclusters,drpolicies -n ramen-system 2>/dev/null || echo "Not ready yet" && 
        echo "" && 
        echo "=== VRG & APPLICATIONS (DR1) ===" && 
        kubectl --context=kind-ramen-dr1 get vrg,pods,pvc -A 2>/dev/null | head -8 || echo "Not ready yet" && 
        echo "" && 
        echo "=== VRG & APPLICATIONS (DR2) ===" && 
        kubectl --context=kind-ramen-dr2 get vrg,pods,pvc -A 2>/dev/null | head -6 || echo "Not ready yet"
    '
}

# KubeVirt and storage monitoring
kubevirt_monitoring() {
    echo -e "${GREEN}💾 Starting KubeVirt & Storage Resources Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • VMs, VMIs (KubeVirt resources)"
    echo "  • Pods, PVCs, VRGs, VRs"
    echo "  • Storage classes and volume snapshots"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 5 '
        echo "=== KUBEVIRT RESOURCES (DR1) ===" && 
        kubectl --context=kind-ramen-dr1 get vm,vmi,pods,pvc,vrg,vr -n kubevirt-sample 2>/dev/null | head -10 || echo "No KubeVirt resources deployed" && 
        echo "" && 
        echo "=== STORAGE CLASSES ===" && 
        kubectl --context=kind-ramen-dr1 get storageclass 2>/dev/null && 
        echo "" && 
        echo "=== VOLUME SNAPSHOTS ===" && 
        kubectl --context=kind-ramen-dr1 get volumesnapshots -A 2>/dev/null | head -5 || echo "No snapshots found"
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
        kubectl --context=kind-ramen-hub get crd | grep ramen && 
        echo "" && 
        echo "=== RAMENDR HUB OPERATOR ===" && 
        kubectl --context=kind-ramen-hub get pods,deployments -n ramen-system 2>/dev/null | head -4 && 
        echo "" && 
        echo "=== RAMENDR DR1 OPERATOR ===" && 
        kubectl --context=kind-ramen-dr1 get pods,deployments -n ramen-system 2>/dev/null | head -3 && 
        echo "" && 
        echo "=== RAMENDR DR2 OPERATOR ===" && 
        kubectl --context=kind-ramen-dr2 get pods,deployments -n ramen-system 2>/dev/null | head -3 && 
        echo "" && 
        echo "=== VOLSYNC OPERATOR ===" && 
        kubectl --context=kind-ramen-dr1 get pods -n volsync-system 2>/dev/null | head -3 || echo "VolSync not deployed" && 
        echo "" && 
        echo "=== STORAGE CRDS ===" && 
        kubectl --context=kind-ramen-dr1 get crd | grep -E "(snapshot|replication|volume)" | head -5 && 
        echo "" && 
        echo "=== MINIO OPERATOR ===" && 
        kubectl --context=kind-ramen-hub get pods -n minio-system 2>/dev/null | head -3 || echo "MinIO not deployed"
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
    echo "  • KubeVirt resources and storage"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop monitoring${NC}"
    echo ""
    sleep 2
    
    watch -n 3 '
        echo "=== CLUSTERS & CONTEXTS ===" && 
        kind get clusters && 
        echo "" && 
        kubectl config get-contexts | grep kind && 
        echo "" && 
        echo "=== RAMENDR CRDS ===" && 
        kubectl --context=kind-ramen-hub get crd | grep ramen | head -5 && 
        echo "" && 
        echo "=== HUB OPERATORS & RESOURCES ===" && 
        kubectl --context=kind-ramen-hub get pods,drclusters,drpolicies -n ramen-system 2>/dev/null | head -6 && 
        echo "" && 
        echo "=== DR1 OPERATORS & VRG ===" && 
        kubectl --context=kind-ramen-dr1 get pods -n ramen-system 2>/dev/null && 
        kubectl --context=kind-ramen-dr1 get vrg,pvc -A 2>/dev/null | head -4 && 
        echo "" && 
        echo "=== DR2 OPERATORS & VRG ===" && 
        kubectl --context=kind-ramen-dr2 get pods -n ramen-system 2>/dev/null && 
        kubectl --context=kind-ramen-dr2 get vrg,pvc -A 2>/dev/null | head -3 && 
        echo "" && 
        echo "=== STORAGE DEPS ===" && 
        kubectl --context=kind-ramen-dr1 get pods -n volsync-system 2>/dev/null | head -3 || echo "VolSync not ready" && 
        echo "" && 
        echo "=== SNAPSHOT CRDS ===" && 
        kubectl --context=kind-ramen-dr1 get crd | grep snapshot | head -3
    '
}

# MinIO console setup
minio_console() {
    echo -e "${GREEN}🌐 Setting up MinIO Console Access...${NC}"
    echo ""
    
    if [ -f "../scripts/access-minio-console.sh" ]; then
        ../scripts/access-minio-console.sh
    else
        echo -e "${YELLOW}⚠️  MinIO console script not found${NC}"
        echo "Manual setup:"
        echo "  kubectl port-forward -n minio-system service/minio 9001:9001 &"
        echo "  Open: http://localhost:9001"
        echo "  Login: minioadmin / minioadmin"
    fi
}

# Show all commands
show_commands() {
    echo -e "${BLUE}📋 All Monitoring Commands (Copy-Paste Ready):${NC}"
    echo ""
    
    echo -e "${PURPLE}# Terminal 2: Cluster & Infrastructure Monitoring${NC}"
    echo 'watch -n 2 "
        echo \"=== CLUSTERS ===\" && 
        kind get clusters && 
        echo \"\" && 
        echo \"=== CONTEXTS ===\" && 
        kubectl config get-contexts | grep kind && 
        echo \"\" && 
        echo \"=== RAMEN PODS ===\" && 
        kubectl get pods -A | grep ramen | head -5
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 3: Application & DR Resources${NC}"
    echo 'watch -n 3 "
        echo \"=== DR RESOURCES (Hub) ===\" && 
        kubectl --context=kind-ramen-hub get drclusters,drpolicies -n ramen-system 2>/dev/null || echo \"Not ready\" && 
        echo \"\" && 
        echo \"=== VRG & APPS (DR1) ===\" && 
        kubectl --context=kind-ramen-dr1 get vrg,pods,pvc -A 2>/dev/null | head -8
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 4: Operators & CRDs Monitoring${NC}"
    echo 'watch -n 3 "
        echo \"=== RAMENDR CRDS ===\" && 
        kubectl --context=kind-ramen-hub get crd | grep ramen && 
        echo \"\" && 
        echo \"=== HUB OPERATOR ===\" && 
        kubectl --context=kind-ramen-hub get pods,deployments -n ramen-system 2>/dev/null | head -4 && 
        echo \"\" && 
        echo \"=== DR1 OPERATOR ===\" && 
        kubectl --context=kind-ramen-dr1 get pods,deployments -n ramen-system 2>/dev/null | head -3 && 
        echo \"\" && 
        echo \"=== VOLSYNC ===\" && 
        kubectl --context=kind-ramen-dr1 get pods -n volsync-system 2>/dev/null | head -3
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 5: KubeVirt & Storage${NC}"
    echo 'watch -n 5 "
        kubectl --context=kind-ramen-dr1 get vm,vmi,pods,pvc,vrg,vr -n kubevirt-sample 2>/dev/null | head -10 || echo \"No KubeVirt resources\"
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 6: MinIO Console${NC}"
    echo "../scripts/access-minio-console.sh"
    echo ""
    
    echo -e "${PURPLE}# Comprehensive All-in-One Monitoring${NC}"
    echo 'watch -n 3 "
        echo \"=== RAMENDR CRDS ===\" && 
        kubectl --context=kind-ramen-hub get crd | grep ramen | head -5 && 
        echo \"\" && 
        echo \"=== HUB OPERATORS ===\" && 
        kubectl --context=kind-ramen-hub get pods,drclusters,drpolicies -n ramen-system 2>/dev/null | head -6 && 
        echo \"\" && 
        echo \"=== DR1 OPERATORS & VRG ===\" && 
        kubectl --context=kind-ramen-dr1 get pods -n ramen-system 2>/dev/null && 
        kubectl --context=kind-ramen-dr1 get vrg,pvc -A 2>/dev/null | head -4
    "'
}

# Help and examples
show_help() {
    echo -e "${BLUE}❓ RamenDR Demo Monitoring Help${NC}"
    echo ""
    echo -e "${PURPLE}🎯 Quick Start:${NC}"
    echo "  1. Run: ./kind_monitoring.sh"
    echo "  2. Choose option 7 to see all commands"
    echo "  3. Copy commands to separate terminals"
    echo "  4. Start monitoring before running demo"
    echo ""
    echo -e "${PURPLE}📊 Resource Explanations:${NC}"
    echo "  • vm/vmi: KubeVirt Virtual Machines and Instances"
    echo "  • vrg: VolumeReplicationGroup (RamenDR's core resource)"
    echo "  • vr: VolumeReplication (storage-level replication)"
    echo "  • drclusters: Disaster Recovery cluster definitions"
    echo "  • drpolicies: DR policies and schedules"
    echo "  • crd: Custom Resource Definitions (Kubernetes extensions)"
    echo "  • deployments: Kubernetes operator deployments"
    echo ""
    echo -e "${PURPLE}⚡ Pro Tips:${NC}"
    echo "  • Use different refresh intervals: 2s for infrastructure, 3s for apps, 5s for storage"
    echo "  • Position terminals so audience can see real-time changes"
    echo "  • Start MinIO console before demo: http://localhost:9001"
    echo "  • Have kubectl contexts ready: kind-ramen-hub, kind-ramen-dr1, kind-ramen-dr2"
    echo ""
    echo -e "${PURPLE}🔧 Troubleshooting:${NC}"
    echo "  • If contexts not found: run 'kind export kubeconfig --name <cluster>'"
    echo "  • If no resources shown: operators may still be starting"
    echo "  • If KubeVirt not found: that's normal for basic demos"
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
            3) kubevirt_monitoring ;;
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
