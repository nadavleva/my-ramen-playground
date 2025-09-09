<!--
SPDX-FileCopyrightText: The RamenDR authors
SPDX-License-Identifier: Apache-2.0
-->

# RamenDR Backup Verification Guide

This guide explains **exactly what to look for** when verifying that RamenDR is successfully backing up your PVCs and volumes to S3 storage.

## 🎯 What RamenDR Actually Backs Up

**Important**: RamenDR **does NOT backup actual volume data** to S3. Instead, it stores **metadata** and uses **VolSync for data replication**.

### **S3 Storage Contents (Metadata Only)**
```
s3://your-bucket/
├── cluster-metadata/
│   ├── drcluster-configurations/
│   ├── drpolicy-definitions/
│   └── cluster-state-info/
├── application-metadata/
│   ├── namespace-configurations/
│   ├── resource-definitions/
│   └── placement-decisions/
└── volume-metadata/
    ├── volume-replication-configs/
    ├── snapshot-metadata/
    └── protection-groups/
```

### **Actual Volume Data (Handled by VolSync)**
- **Data replication**: VolSync (rsync, rclone, restic)
- **Storage location**: Target cluster storage (not S3)
- **S3 role**: Only metadata about replication configuration

## 🔍 Step-by-Step Verification Process

### **1. Check S3 Bucket Contents**

#### **For MinIO:**
```bash
# Run automated check
./examples/s3-config/check-minio-backups.sh

# Manual MinIO console access
kubectl port-forward -n minio-system service/minio 9001:9001
# Open http://localhost:9001 (minioadmin/minioadmin)
```

#### **For AWS S3:**
```bash
# Run automated check  
./examples/s3-config/check-aws-backups.sh your-bucket-name

# Manual AWS CLI check
aws s3 ls s3://your-bucket-name/ --recursive
```

#### **What to Look For in S3:**
- **Folder structure**: Organized metadata directories
- **JSON files**: RamenDR configuration metadata
- **Object count**: Should increase as you protect more applications
- **File patterns**: Names containing `vrg`, `drpc`, `namespace`, `app`

### **2. Check RamenDR Kubernetes Resources**

```bash
# Run comprehensive status check
./examples/monitoring/check-ramendr-status.sh

# Manual checks
kubectl get drclusters,drpolicies -n ramen-system
kubectl get volumereplicationgroups -A
kubectl get drplacementcontrols -A
```

#### **What to Look For in Kubernetes:**
- **DRCluster**: Status should show "Available" 
- **DRPolicy**: Should reference your clusters
- **VolumeReplicationGroups (VRG)**: Created for each protected PVC
- **Operator logs**: Should show backup activity

### **3. Verify PVC Protection Status**

```bash
# Check for protected PVCs (with RamenDR labels)
kubectl get pvc -A --show-labels | grep ramen

# Check VRG status for specific application
kubectl get vrg -n your-app-namespace
kubectl describe vrg your-app-vrg -n your-app-namespace
```

#### **VRG Status Values:**
- **Primary**: PVC is actively used and protected
- **Secondary**: PVC is replicated target (standby)
- **Relocating**: Failover in progress
- **Error**: Problem with replication

## 📋 Expected S3 Object Examples

### **Typical MinIO/S3 Contents After Protecting Applications:**

```
ramen-metadata/
├── clusters/
│   ├── ramen-dr1-config.json
│   └── ramen-dr2-config.json
├── policies/
│   └── ramen-dr-policy-config.json
├── applications/
│   ├── my-app-namespace/
│   │   ├── deployment-config.json
│   │   ├── pvc-config.json
│   │   └── vrg-status.json
│   └── another-app/
│       └── protection-group.json
└── replication/
    ├── volume-replication-class.json
    └── sync-schedules.json
```

### **Sample Object Content (VRG Metadata):**
```json
{
  "apiVersion": "ramendr.openshift.io/v1alpha1",
  "kind": "VolumeReplicationGroup",
  "metadata": {
    "name": "my-app-vrg",
    "namespace": "my-app"
  },
  "spec": {
    "replicationState": "primary",
    "s3Profiles": ["minio-s3"],
    "volumeReplicationClasses": [...]
  },
  "status": {
    "state": "Primary",
    "conditions": [...]
  }
}
```

## 🚨 Troubleshooting Common Issues

### **Problem: S3 Bucket is Empty**
**Possible Causes:**
- No applications with PVCs protected yet
- DRPolicy not created or misconfigured
- S3 credentials incorrect
- Operators not running

**Solutions:**
```bash
# 1. Check operator status
kubectl get pods -n ramen-system

# 2. Check operator logs
kubectl logs -n ramen-system deployment/ramen-hub-operator

# 3. Verify S3 credentials
kubectl get secret ramen-s3-secret -n ramen-system -o yaml

# 4. Create test application
kubectl apply -f examples/test-app-with-pvc.yaml
```

### **Problem: VRGs Created but No S3 Objects**
**Possible Causes:**
- S3 profile misconfigured in DRCluster
- Network connectivity to S3 endpoint
- Bucket permissions issues

**Solutions:**
```bash
# 1. Test S3 connectivity from cluster
kubectl run s3-test --rm -it --image=amazon/aws-cli --restart=Never -- s3 ls s3://your-bucket/

# 2. Check DRCluster S3 configuration
kubectl describe drcluster ramen-dr1 -n ramen-system

# 3. Verify S3 endpoint accessibility
kubectl run network-test --rm -it --image=busybox --restart=Never -- nslookup minio.minio-system.svc.cluster.local
```

### **Problem: Objects in S3 but Data Not Replicating**
**Possible Causes:**
- VolSync not installed/configured
- VolumeReplicationClass missing
- Storage class issues

**Solutions:**
```bash
# 1. Check VolSync status
kubectl get pods -n volsync-system

# 2. Check VolumeReplicationClass
kubectl get volumereplicationclass

# 3. Check VRG detailed status
kubectl describe vrg -A
```

## 📊 Monitoring Dashboard Commands

### **Quick Status Overview:**
```bash
echo "=== RamenDR Overview ==="
echo "DRClusters: $(kubectl get drclusters -n ramen-system --no-headers | wc -l)"
echo "DRPolicies: $(kubectl get drpolicies -n ramen-system --no-headers | wc -l)"  
echo "Protected Apps: $(kubectl get vrg -A --no-headers | wc -l)"
echo "S3 Objects: $(mc ls minio/ramen-metadata/ --recursive | wc -l 2>/dev/null || echo 'Check manually')"
```

### **Application Protection Status:**
```bash
# Show all protected applications
kubectl get vrg -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATE:.status.state,AGE:.metadata.creationTimestamp"
```

### **Operator Health Check:**
```bash
# Check all RamenDR components
kubectl get pods -n ramen-system -o wide
kubectl get pods -n volsync-system -o wide  
kubectl get pods -n minio-system -o wide
```

## 🎯 Success Criteria Checklist

**✅ RamenDR is Working Correctly When:**

- [ ] **S3 bucket contains metadata objects** (JSON files)
- [ ] **DRCluster resources show "Available" status**
- [ ] **VRG resources exist for protected PVCs**
- [ ] **VRG status shows "Primary" or "Secondary"**
- [ ] **Operator logs show successful backup operations**
- [ ] **No error conditions in DRCluster/DRPolicy status**

**⚠️ Warning Signs:**

- [ ] **Empty S3 bucket after protecting applications**
- [ ] **VRG stuck in "Error" state**
- [ ] **Operators constantly restarting**
- [ ] **S3 connectivity errors in logs**
- [ ] **Missing VolumeReplicationClass resources**

## 🔗 Quick Reference Commands

```bash
# Complete verification workflow
./examples/monitoring/check-ramendr-status.sh
./examples/s3-config/check-minio-backups.sh

# Create test application to verify protection
kubectl apply -f examples/test-application/nginx-with-pvc.yaml

# Watch VRG creation and status
kubectl get vrg -A --watch

# Monitor operator logs
kubectl logs -f -n ramen-system deployment/ramen-hub-operator
```

---

**Remember**: RamenDR stores **metadata in S3** and uses **VolSync for actual data replication**. Both components must be working for complete disaster recovery protection!
