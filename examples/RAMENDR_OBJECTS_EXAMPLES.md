# 📖 RamenDR Objects Examples & Reference

This document provides copy-paste ready examples of all RamenDR objects with detailed explanations.

## 🎯 Quick Reference

| **Object** | **Purpose** | **Required For** |
|------------|-------------|------------------|
| **DRPolicy** | Define DR policy between clusters | All deployments |
| **DRCluster** | Register clusters in DR | All deployments |
| **VRG** | Protect application volumes | Kind/Lightweight K8s |
| **DRPlacementControl** | Manage app placement | OpenShift ACM only |
| **VolumeSnapshotClass** | Configure snapshots | Volume operations |
| **VolumeReplicationClass** | Configure replication | Volume operations |

---

## 🏛️ **DRPolicy** - Disaster Recovery Policy

**Purpose**: Defines the disaster recovery policy that governs replication between clusters.

```yaml
---
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

apiVersion: ramendr.openshift.io/v1alpha1
kind: DRPolicy
metadata:
  name: ramen-dr-policy
  namespace: ramen-system
  labels:
    app.kubernetes.io/name: ramen-dr-policy
    app.kubernetes.io/component: disaster-recovery
spec:
  # Clusters participating in DR
  drClusterSet:
  - name: ramen-dr1
    region: east
  - name: ramen-dr2  
    region: west
  
  # Replication frequency
  schedulingInterval: 5m
  
  # Volume replication class selector
  replicationClassSelector:
    matchLabels:
      ramendr.openshift.io/replicationID: ramen-volsync
  
  # Volume snapshot class selector  
  volumeSnapshotClassSelector:
    matchLabels:
      velero.io/csi-volumesnapshot-class: "true"
```

**Usage**:
```bash
kubectl apply -f drpolicy.yaml --context=kind-ramen-hub
```

---

## 🌐 **DRCluster** - Cluster Registration

**Purpose**: Registers clusters in the disaster recovery configuration.

```yaml
---
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# DR Cluster 1 (East Region)
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRCluster
metadata:
  name: ramen-dr1
  labels:
    cluster.ramendr.openshift.io/region: east
    app.kubernetes.io/name: ramen-dr-cluster
spec:
  # S3 profile for metadata storage
  s3ProfileName: minio-s3
  
  # Geographic region
  region: east
  
  # Additional cluster metadata
  clusterFence: false

---
# DR Cluster 2 (West Region)
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRCluster
metadata:
  name: ramen-dr2
  labels:
    cluster.ramendr.openshift.io/region: west
    app.kubernetes.io/name: ramen-dr-cluster
spec:
  # S3 profile for metadata storage
  s3ProfileName: minio-s3
  
  # Geographic region
  region: west
  
  # Additional cluster metadata
  clusterFence: false
```

**Usage**:
```bash
kubectl apply -f drclusters.yaml --context=kind-ramen-hub
```

---

## 📦 **VolumeReplicationGroup (VRG)** - Application Volume Protection

**Purpose**: Manages volume replication for applications. This is the main object for protecting application data.

### **Primary VRG** (Active cluster)

```yaml
---
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

apiVersion: ramendr.openshift.io/v1alpha1
kind: VolumeReplicationGroup
metadata:
  name: nginx-test-vrg
  namespace: nginx-test
  labels:
    app: nginx-test
    ramendr.openshift.io/replication-state: primary
spec:
  # Select PVCs to protect by label
  pvcSelector:
    matchLabels:
      app: nginx-test
  
  # Replication state: primary (active) or secondary (standby)
  replicationState: primary
  
  # S3 profiles for metadata backup
  s3Profiles:
  - minio-s3
  
  # Synchronization configuration
  sync:
    mode: sync
    schedulingInterval: "5m"
  
  # Volume replication class (optional)
  replicationClassSelector:
    matchLabels:
      ramendr.openshift.io/replicationID: ramen-volsync
  
  # Volume snapshot class (optional)  
  volumeSnapshotClassSelector:
    matchLabels:
      velero.io/csi-volumesnapshot-class: "true"
```

### **Secondary VRG** (Standby cluster)

```yaml
---
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

apiVersion: ramendr.openshift.io/v1alpha1
kind: VolumeReplicationGroup
metadata:
  name: nginx-test-vrg-dr2
  namespace: nginx-test
  labels:
    app: nginx-test
    ramendr.openshift.io/replication-state: secondary
spec:
  # Select PVCs to protect by label
  pvcSelector:
    matchLabels:
      app: nginx-test
  
  # Replication state: secondary (standby)
  replicationState: secondary
  
  # S3 profiles for metadata backup
  s3Profiles:
  - minio-s3
  
  # Synchronization configuration
  sync:
    mode: sync
    schedulingInterval: "5m"
```

**Usage**:
```bash
# Create on primary cluster (DR1)
kubectl apply -f nginx-vrg-primary.yaml --context=kind-ramen-dr1

# Create on secondary cluster (DR2)  
kubectl apply -f nginx-vrg-secondary.yaml --context=kind-ramen-dr2
```

---

## 🎯 **DRPlacementControl** - Application Placement (OpenShift ACM Only)

**Purpose**: Manages application placement and automatically creates VRGs. **Only needed with OpenShift ACM**.

**⚠️ Note**: Our kind demo **does NOT need** DRPlacementControl - we create VRGs directly.

```yaml
---
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# For OpenShift ACM environments only
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRPlacementControl
metadata:
  name: nginx-test-drpc
  namespace: nginx-test
  labels:
    app: nginx-test
spec:
  # Reference to DRPolicy
  drPolicyRef:
    name: ramen-dr-policy
    namespace: ramen-system
  
  # Preferred cluster (where app normally runs)
  preferredCluster: ramen-dr1
  
  # Failover cluster (where app goes during DR)
  failoverCluster: ramen-dr2
  
  # PVC selector - which volumes to protect
  pvcSelector:
    matchLabels:
      app: nginx-test
  
  # Initial replication state
  replicationState: primary
  
  # PlacementRule reference (requires OpenShift ACM)
  placementRef:
    kind: PlacementRule
    name: nginx-test-placement
    namespace: nginx-test
```

**Requirements**:
- OpenShift Advanced Cluster Management (ACM)
- PlacementRule CRD
- ManagedCluster CRD

---

## 📸 **VolumeSnapshotClass** - Snapshot Configuration

**Purpose**: Configures how volume snapshots are created.

```yaml
---
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: demo-snapclass
  labels:
    # Required label for VRG selector matching
    velero.io/csi-volumesnapshot-class: "true"
    app.kubernetes.io/name: ramen-demo
driver: hostpath.csi.k8s.io  # For kind clusters
deletionPolicy: Delete
parameters:
  # Parameters for hostpath CSI driver in kind
  csi.storage.k8s.io/snapshotter-secret-name: ""
  csi.storage.k8s.io/snapshotter-secret-namespace: ""
```

**Usage**:
```bash
kubectl apply -f volumesnapshotclass.yaml
```

---

## 🔄 **VolumeReplicationClass** - Replication Configuration

**Purpose**: Configures how volume replication is performed.

```yaml
---
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplicationClass
metadata:
  name: demo-replication-class
  labels:
    # Required label for VRG selector matching
    ramendr.openshift.io/replicationID: ramen-volsync
    app.kubernetes.io/name: ramen-demo
spec:
  provisioner: hostpath.csi.k8s.io  # For kind clusters
  parameters:
    # Replication secrets (empty for demo)
    replication.storage.openshift.io/replication-secret-name: ""
    replication.storage.openshift.io/replication-secret-namespace: ""
    
    # VolSync-specific parameters for kind clusters
    copyMethod: Snapshot
    capacity: 1Gi
```

**Usage**:
```bash
kubectl apply -f volumereplicationclass.yaml
```

---

## 🗄️ **RamenConfig** - S3 Backend Configuration

**Purpose**: Configures S3 storage for metadata backup.

```yaml
---
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

apiVersion: v1
kind: ConfigMap
metadata:
  name: ramen-dr-cluster-operator-config
  namespace: ramen-system
data:
  ramen_manager_config.yaml: |
    apiVersion: ramendr.openshift.io/v1alpha1
    kind: RamenConfig
    health:
      healthProbeBindAddress: :8081
    metrics:
      bindAddress: 127.0.0.1:9289
    webhook:
      port: 9443
    leaderElection:
      leaderElect: true
      resourceName: dr-cluster.ramendr.openshift.io
    ramenControllerType: dr-cluster
    maxConcurrentReconciles: 50
    volSync:
      destinationCopyMethod: Direct
    volumeUnprotectionEnabled: true
    ramenOpsNamespace: ramen-ops
    multiNamespace:
      FeatureEnabled: true
      volsyncSupported: true
    kubeObjectProtection:
      veleroNamespaceName: velero
    
    # S3 store profiles configuration
    s3StoreProfiles:
    - s3ProfileName: minio-s3
      s3Bucket: ramen-metadata
      s3Region: us-east-1
      # IMPORTANT: Use s3CompatibleEndpoint (not s3Endpoint)
      s3CompatibleEndpoint: http://minio.minio-system.svc.cluster.local:9000
      s3SecretRef:
        name: ramen-s3-secret
        namespace: ramen-system
    
    drClusterOperator:
      deploymentAutomationEnabled: true
```

**Usage**:
```bash
kubectl apply -f ramenconfig.yaml --context=kind-ramen-dr1
kubectl apply -f ramenconfig.yaml --context=kind-ramen-dr2
```

---

## 🚀 **Complete Deployment Workflows**

### **Kind/Lightweight Kubernetes (Our Demo)**

```bash
# 1. Deploy core objects on hub cluster
kubectl apply -f drpolicy.yaml --context=kind-ramen-hub
kubectl apply -f drclusters.yaml --context=kind-ramen-hub

# 2. Deploy resource classes on all clusters
kubectl apply -f volumesnapshotclass.yaml --context=kind-ramen-hub
kubectl apply -f volumesnapshotclass.yaml --context=kind-ramen-dr1
kubectl apply -f volumesnapshotclass.yaml --context=kind-ramen-dr2

kubectl apply -f volumereplicationclass.yaml --context=kind-ramen-dr1
kubectl apply -f volumereplicationclass.yaml --context=kind-ramen-dr2

# 3. Configure S3 on DR clusters
kubectl apply -f ramenconfig.yaml --context=kind-ramen-dr1
kubectl apply -f ramenconfig.yaml --context=kind-ramen-dr2

# 4. Create VRGs for application protection
kubectl apply -f nginx-vrg-primary.yaml --context=kind-ramen-dr1
kubectl apply -f nginx-vrg-secondary.yaml --context=kind-ramen-dr2
```

### **OpenShift + ACM**

```bash
# 1. Deploy core objects on hub cluster
kubectl apply -f drpolicy.yaml
kubectl apply -f drclusters.yaml

# 2. Create DRPlacementControl (ACM creates VRGs automatically)
kubectl apply -f nginx-drpc.yaml

# ACM handles the rest automatically
```

---

## 🎯 **Troubleshooting Examples**

### **Check VRG Status**
```bash
kubectl get vrg -A --context=kind-ramen-dr1
kubectl describe vrg nginx-test-vrg -n nginx-test --context=kind-ramen-dr1
```

### **Check S3 Connectivity**
```bash
kubectl logs deployment/ramen-dr-cluster-operator -n ramen-system --context=kind-ramen-dr1 | grep -i s3
```

### **Verify Resource Classes**
```bash
kubectl get volumesnapshotclass,volumereplicationclass --context=kind-ramen-dr1
```

### **Check DRPolicy Status**
```bash
kubectl get drpolicy,drcluster -A --context=kind-ramen-hub
```

---

## 📚 **Additional Resources**

- **Live Examples**: See `examples/` directory for working YAML files
- **Demo Script**: Run `./examples/ramendr-demo.sh` for interactive demo
- **Architecture Guide**: See `examples/RAMENDR_ARCHITECTURE_GUIDE.md`
- **Troubleshooting**: See `examples/monitoring/check-ramendr-status.sh`

---

**Created**: September 2025  
**Status**: Tested with RamenDR on kind clusters  
**Compatibility**: RamenDR v0.0.1+, Kubernetes 1.28+
