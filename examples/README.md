<!--
SPDX-FileCopyrightText: The RamenDR authors
SPDX-License-Identifier: Apache-2.0
-->

# RamenDR Configuration Examples

This directory contains example configurations for setting up **RamenDR (Disaster Recovery for Kubernetes applications)** with **S3 storage** and **multi-cluster replication**.

## 📁 Directory Structure

```
examples/
├── README.md                 # This file
├── minio-deployment/         # MinIO S3 storage setup
│   └── minio-s3.yaml        # Complete MinIO deployment
├── s3-config/               # S3 credentials and configuration
│   └── s3-secret.yaml       # S3 access credentials
└── dr-policy/               # RamenDR cluster and policy configuration
    ├── drclusters.yaml      # DR cluster definitions
    └── drpolicy.yaml        # DR replication policy
```

## 🚀 Quick Start

### **📋 Prerequisites**
1. **3 Kubernetes clusters** (1 hub + 2 DR clusters)
2. **RamenDR operators** installed on all clusters
3. **VolSync** installed on DR clusters  
4. **VolumeReplication CRDs** installed

### **⚡ Automated Setup (Recommended)**

For a complete automated setup from scratch:

```bash
# One-command setup: clusters + operators + demo
./scripts/fresh-demo.sh

# Or step-by-step:
./scripts/cleanup-all.sh      # Clean existing environment
./scripts/setup.sh kind       # Setup kind clusters  
./scripts/quick-install.sh    # Install RamenDR operators
./examples/ramendr-demo.sh    # Run demo
```

**📖 See Also:**
- [`AUTOMATED_DEMO_QUICKSTART.md`](AUTOMATED_DEMO_QUICKSTART.md) - Quick demo guide
- [`COMPLETE_AUTOMATED_SETUP.md`](COMPLETE_AUTOMATED_SETUP.md) - Full setup guide  
- [`RAMENDR_ARCHITECTURE_GUIDE.md`](RAMENDR_ARCHITECTURE_GUIDE.md) - Architecture & code deep-dive

### **Step 1: Deploy MinIO S3 Storage**
```bash
# Deploy MinIO to hub cluster
kubectl config use-context hub-cluster
kubectl apply -f minio-deployment/minio-s3.yaml

# Wait for MinIO to be ready
kubectl wait --for=condition=available --timeout=300s deployment/minio -n minio-system

# Verify MinIO is running
kubectl get pods -n minio-system
```

### **Step 2: Configure S3 Credentials**
```bash
# Create S3 secret on hub cluster
kubectl apply -f s3-config/s3-secret.yaml

# Verify secret creation
kubectl get secret ramen-s3-secret -n ramen-system
```

### **Step 3: Create DR Clusters**
```bash
# Create DRCluster resources on hub cluster
kubectl apply -f dr-policy/drclusters.yaml

# Verify DR clusters
kubectl get drclusters -n ramen-system
```

### **Step 4: Create DR Policy**
```bash
# Create DRPolicy for replication
kubectl apply -f dr-policy/drpolicy.yaml

# Verify DR policy
kubectl get drpolicies -n ramen-system
```

### **Step 5: Access MinIO Console (Optional)**
```bash
# Port-forward to access MinIO console
kubectl port-forward -n minio-system service/minio 9001:9001

# Open browser to http://localhost:9001
# Login: minioadmin / minioadmin
```

## 🔧 Configuration Details

### **MinIO S3 Storage**
- **Purpose**: Stores RamenDR metadata about protected applications
- **Access**: Internal cluster DNS (`minio.minio-system.svc.cluster.local:9000`)
- **Credentials**: `minioadmin` / `minioadmin` (change for production!)
- **Storage**: Uses `emptyDir` (ephemeral) - modify for persistent storage

### **S3 Secret Configuration**
- **Purpose**: Provides S3 credentials to RamenDR operators
- **Namespace**: `ramen-system` (must match operator namespace)
- **Fields**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

### **DRCluster Resources**
- **Purpose**: Defines participating disaster recovery clusters
- **Requirements**: Exactly 2 clusters per DRPolicy
- **S3 Profile**: References S3 storage configuration
- **Regions**: Different regions for geographic separation

### **DRPolicy Configuration**
- **Purpose**: Governs replication behavior between DR clusters
- **Clusters**: Lists the 2 participating DR clusters
- **Selector**: Matches VolumeReplicationClass resources
- **Scheduling**: Optional intervals for replication operations

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Hub Cluster   │    │  DR Cluster 1   │    │  DR Cluster 2   │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ Hub Operator│ │    │ │DR Operator  │ │    │ │DR Operator  │ │
│ │             │ │    │ │             │ │    │ │             │ │
│ │ DRPolicy    │ │    │ │ VolSync     │ │    │ │ VolSync     │ │
│ │ DRCluster   │ │    │ │ Apps + Data │ │    │ │ Apps + Data │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    └─────────────────┘    └─────────────────┘
│ │ MinIO S3    │ │             │                        │
│ │ (Metadata)  │ │◄────────────┼────────────────────────┘
│ └─────────────┘ │             │
└─────────────────┘             │
                                │
                    ┌───────────▼──────────┐
                    │    Replication       │
                    │  (VolSync/Rsync)     │
                    └──────────────────────┘
```

## 🔨 Customization

### **For Production AWS S3**
1. **Update s3-secret.yaml**:
   ```yaml
   stringData:
     AWS_ACCESS_KEY_ID: your-real-access-key
     AWS_SECRET_ACCESS_KEY: your-real-secret-key
   ```

2. **Update drclusters.yaml**:
   ```yaml
   spec:
     s3ProfileName: aws-s3-production
     region: us-west-2  # Your AWS region
   ```

### **For Different Storage Classes**
Update `drclusters.yaml` to include your storage classes:
```yaml
spec:
  storageClasses:
  - name: fast-ssd
    provisioner: ebs.csi.aws.com
  - name: shared-storage
    provisioner: efs.csi.aws.com
```

### **For Custom Replication Scheduling**
Update `drpolicy.yaml`:
```yaml
spec:
  schedulingInterval: 15m  # Custom interval
  replicationClassSelector:
    matchLabels:
      storage.type: critical
```

## 🧪 Testing the Setup

### **1. Verify All Components**
```bash
# Check MinIO
kubectl get pods -n minio-system

# Check RamenDR resources
kubectl get drclusters,drpolicies -n ramen-system

# Check operators (on each cluster)
kubectl get pods -n ramen-system
```

### **2. Create a Test Application**
```bash
# Apply test application with PVCs
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  labels:
    app: test-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: app
        image: nginx
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: test-app-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-app-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

### **3. Verify Replication**
```bash
# Check VolumeReplicationGroups
kubectl get vrg -A

# Check replication status
kubectl describe drcluster ramen-dr1 -n ramen-system
```

## 🚨 Troubleshooting

### **Common Issues**

**MinIO not starting:**
```bash
kubectl logs -n minio-system deployment/minio
kubectl describe pod -n minio-system -l app=minio
```

**DRCluster creation fails:**
```bash
kubectl describe drcluster ramen-dr1 -n ramen-system
kubectl logs -n ramen-system deployment/ramen-hub-operator
```

**Replication not working:**
```bash
# Check VolSync
kubectl get pods -n volsync-system

# Check VolumeReplicationClass
kubectl get volumereplicationclass

# Check operator logs
kubectl logs -n ramen-system deployment/ramen-dr-cluster-operator
```

### **Known Limitations**
- **kind clusters**: May have networking issues with API server timeouts
- **VolSync**: Can timeout in development environments  
- **S3 connectivity**: Requires proper DNS resolution between clusters

## 📚 References

- [RamenDR Documentation](https://github.com/RamenDR/ramen)
- [VolSync Documentation](https://volsync.readthedocs.io/)
- [MinIO Documentation](https://min.io/docs/)
- [Kubernetes Disaster Recovery Best Practices](https://kubernetes.io/docs/concepts/cluster-administration/disaster-recovery-backup/)

---

**Created**: September 2025  
**Status**: Tested with kind clusters on Docker
