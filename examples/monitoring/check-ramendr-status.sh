#!/bin/bash
# Check RamenDR Status and PVC Backup Progress
# 
# This script provides comprehensive status of RamenDR backups and replication

set -e

echo "🔍 RamenDR Status and Backup Verification"
echo "========================================"

# Function to check resource across contexts
check_resource() {
    local resource=$1
    local context=$2
    local namespace=${3:-ramen-system}
    
    echo "📋 Checking $resource in $context..."
    kubectl --context="$context" get "$resource" -n "$namespace" 2>/dev/null || echo "  No $resource found in $context"
}

# Function to check resource details
describe_resource() {
    local resource=$1
    local name=$2
    local context=$3
    local namespace=${4:-ramen-system}
    
    echo "🔍 Details for $resource/$name in $context:"
    kubectl --context="$context" describe "$resource" "$name" -n "$namespace" 2>/dev/null | grep -A 10 -B 5 "Status\|Conditions\|State" || echo "  No detailed status available"
}

echo ""
echo "🏢 === HUB CLUSTER STATUS ==="
HUB_CONTEXT="kind-ramen-hub"

echo "1. DRCluster Resources:"
check_resource "drclusters" "$HUB_CONTEXT"

echo ""
echo "2. DRPolicy Resources:"
check_resource "drpolicies" "$HUB_CONTEXT"

echo ""
echo "3. DRPlacementControl Resources:"
check_resource "drplacementcontrols" "$HUB_CONTEXT"

echo ""
echo "4. Hub Operator Status:"
kubectl --context="$HUB_CONTEXT" get pods -n ramen-system -l app.kubernetes.io/name=ramen-hub-operator 2>/dev/null || echo "  Hub operator not found"

echo ""
echo "🌊 === DR CLUSTER STATUS ==="
DR1_CONTEXT="kind-ramen-dr1"
DR2_CONTEXT="kind-ramen-dr2"

for dr_context in "$DR1_CONTEXT" "$DR2_CONTEXT"; do
    echo ""
    echo "📍 Checking $dr_context..."
    
    echo "  • DR Cluster Operator:"
    kubectl --context="$dr_context" get pods -n ramen-system -l app.kubernetes.io/name=ramen-dr-cluster-operator 2>/dev/null || echo "    DR operator not found"
    
    echo "  • VolumeReplicationGroups:"
    check_resource "volumereplicationgroups" "$dr_context" "default"
    check_resource "volumereplicationgroups" "$dr_context" "ramen-system"
    
    echo "  • VolSync Resources:"
    kubectl --context="$dr_context" get pods -n volsync-system 2>/dev/null || echo "    VolSync not found"
    
    echo "  • Protected PVCs:"
    kubectl --context="$dr_context" get pvc -A --show-labels 2>/dev/null | grep -i "ramen\|replication" || echo "    No protected PVCs found"
done

echo ""
echo "📊 === DETAILED STATUS ANALYSIS ==="

# Check DRCluster status in detail
echo "1. DRCluster Detailed Status:"
kubectl --context="$HUB_CONTEXT" get drclusters -n ramen-system -o yaml 2>/dev/null | grep -A 20 -B 5 "status:\|conditions:" || echo "  No DRCluster status available"

echo ""
echo "2. DRPolicy Detailed Status:"
kubectl --context="$HUB_CONTEXT" get drpolicies -n ramen-system -o yaml 2>/dev/null | grep -A 20 -B 5 "status:\|conditions:" || echo "  No DRPolicy status available"

echo ""
echo "🔄 === REPLICATION STATUS ==="

# Check for VolumeReplicationGroup status
for dr_context in "$DR1_CONTEXT" "$DR2_CONTEXT"; do
    echo ""
    echo "📍 VRG Status in $dr_context:"
    
    VRG_LIST=$(kubectl --context="$dr_context" get vrg -A --no-headers 2>/dev/null | awk '{print $1 "/" $2}' || echo "")
    
    if [[ -n "$VRG_LIST" ]]; then
        for vrg in $VRG_LIST; do
            namespace=$(echo "$vrg" | cut -d'/' -f1)
            name=$(echo "$vrg" | cut -d'/' -f2)
            
            echo "  • VRG: $namespace/$name"
            kubectl --context="$dr_context" get vrg "$name" -n "$namespace" -o jsonpath='{.status.state}' 2>/dev/null || echo "    Status: Unknown"
            echo ""
        done
    else
        echo "  No VolumeReplicationGroups found"
    fi
done

echo ""
echo "📈 === BACKUP VERIFICATION SUMMARY ==="

# Count resources
DRCLUSTERS=$(kubectl --context="$HUB_CONTEXT" get drclusters -n ramen-system --no-headers 2>/dev/null | wc -l || echo "0")
DRPOLICIES=$(kubectl --context="$HUB_CONTEXT" get drpolicies -n ramen-system --no-headers 2>/dev/null | wc -l || echo "0") 
DRPCS=$(kubectl --context="$HUB_CONTEXT" get drplacementcontrols -n ramen-system --no-headers 2>/dev/null | wc -l || echo "0")

VRG_DR1=$(kubectl --context="$DR1_CONTEXT" get vrg -A --no-headers 2>/dev/null | wc -l || echo "0")
VRG_DR2=$(kubectl --context="$DR2_CONTEXT" get vrg -A --no-headers 2>/dev/null | wc -l || echo "0")

echo "📊 Resource Summary:"
echo "  • DRClusters: $DRCLUSTERS"
echo "  • DRPolicies: $DRPOLICIES" 
echo "  • DRPlacementControls: $DRPCS"
echo "  • VRGs in DR1: $VRG_DR1"
echo "  • VRGs in DR2: $VRG_DR2"

if [[ "$DRCLUSTERS" -gt 0 && "$DRPOLICIES" -gt 0 ]]; then
    echo ""
    echo "✅ RamenDR configuration appears to be active!"
    
    if [[ "$VRG_DR1" -gt 0 || "$VRG_DR2" -gt 0 ]]; then
        echo "✅ Volume replication is configured!"
        echo ""
        echo "📝 Next steps:"
        echo "  1. Check S3 bucket contents with: ./examples/s3-config/check-minio-backups.sh"
        echo "  2. Create test applications with PVCs to verify end-to-end replication"
        echo "  3. Monitor operator logs for backup activity"
    else
        echo "⚠️  No VolumeReplicationGroups found - create applications with PVCs to trigger replication"
    fi
else
    echo ""
    echo "⚠️  RamenDR configuration incomplete:"
    echo "  • Check that DRCluster and DRPolicy resources are created"
    echo "  • Verify operators are running correctly"
    echo "  • Check operator logs for errors"
fi

echo ""
echo "✅ RamenDR status check completed!"
