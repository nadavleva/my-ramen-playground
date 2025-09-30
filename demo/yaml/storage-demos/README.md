# RamenDR Storage Demos

This directory contains comprehensive storage demonstration files for RamenDR with Rook Ceph, showcasing different storage scenarios for disaster recovery testing.

## 📁 Files Overview

### Core Demo Applications
- **`block-storage-demo.yaml`** - Block storage (RBD) SAN scenario with nginx
- **`file-storage-demo.yaml`** - File storage (CephFS) VSAN scenario with multiple writers
- **`object-storage-demo.yaml`** - Object storage (S3) scenario with MinIO client

### Protection Configuration
- **`block-storage-vrg.yaml`** - VolumeReplicationGroup for block storage protection
- **`file-storage-vrg.yaml`** - VolumeReplicationGroup for file storage protection

### Storage Infrastructure
- **`rook-ceph-storage-classes.yaml`** - Complete storage class definitions for all scenarios

## 🗄️ Storage Types Demonstrated

### 1. Block Storage (SAN Scenario)
- **Storage Class:** `rook-ceph-block`
- **Access Mode:** ReadWriteOnce (RWO)
- **Use Case:** Traditional SAN storage, databases, single-writer applications
- **Replication:** VolSync-based async replication
- **Demo:** nginx with persistent data and performance testing

### 2. File Storage (VSAN Scenario)  
- **Storage Class:** `rook-cephfs`
- **Access Mode:** ReadWriteMany (RWX)
- **Use Case:** Shared file storage, multi-writer applications
- **Replication:** VolSync-based async replication
- **Demo:** Multiple writers logging to shared storage

### 3. Object Storage (S3/VSAN Metadata)
- **Storage Class:** `rook-ceph-bucket`
- **Access Mode:** S3 API
- **Use Case:** Object storage, backup metadata, VSAN-like scenarios
- **Replication:** Object-level replication
- **Demo:** S3 operations with directory structures

## 🚀 Quick Start

### Prerequisites
```bash
# Ensure minikube clusters are running
minikube status -p ramen-dr1
minikube status -p ramen-dr2
minikube status -p ramen-hub

# Deploy Rook Ceph storage
./demo/scripts/storage/set_ceph_storage.sh
```

### Run All Demos
```bash
# Run comprehensive storage demos
./demo/scripts/storage/run-storage-demos.sh all

# Or run individual demos
./demo/scripts/storage/run-storage-demos.sh block
./demo/scripts/storage/run-storage-demos.sh file  
./demo/scripts/storage/run-storage-demos.sh object
```

### Manual Deployment
```bash
# Deploy block storage demo
kubectl --context=ramen-dr1 apply -f block-storage-demo.yaml
kubectl --context=ramen-dr1 apply -f block-storage-vrg.yaml

# Deploy file storage demo
kubectl --context=ramen-dr1 apply -f file-storage-demo.yaml
kubectl --context=ramen-dr1 apply -f file-storage-vrg.yaml

# Deploy object storage demo
kubectl --context=ramen-dr1 apply -f object-storage-demo.yaml
```

## 🧪 Testing and Validation

### Storage Functionality Tests
```bash
# Test all storage types
./demo/scripts/storage/run-storage-demos.sh test

# Manual testing
kubectl --context=ramen-dr1 get pvc -A
kubectl --context=ramen-dr1 get vrg -A
kubectl --context=ramen-dr1 get pods -A
```

### Data Persistence Verification
```bash
# Block storage test
kubectl --context=ramen-dr1 -n block-storage-demo exec deployment/nginx-block -- ls -la /data/san-test/

# File storage test  
kubectl --context=ramen-dr1 -n file-storage-demo exec deployment/file-writer -- tail -10 /shared/logs/activity.log

# Object storage test
kubectl --context=ramen-dr1 -n object-storage-demo logs deployment/s3-client
```

## 🔧 Troubleshooting

### Common Issues

**1. PVC Pending State**
```bash
# Check storage classes
kubectl --context=ramen-dr1 get storageclass

# Check Ceph cluster status
kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
```

**2. CephFS Issues**
```bash
# Check file system status
kubectl --context=ramen-dr1 -n rook-ceph get cephfilesystem

# Check MDS pods
kubectl --context=ramen-dr1 -n rook-ceph get pods -l app=rook-ceph-mds
```

**3. Object Storage Issues**
```bash
# Check object bucket claims
kubectl --context=ramen-dr1 get obc -A

# Check RGW service
kubectl --context=ramen-dr1 -n rook-ceph get svc -l app=rook-ceph-rgw
```

### Performance Optimization
```bash
# Increase minikube resources for better performance
minikube stop -p ramen-dr1
minikube start -p ramen-dr1 --memory=8192 --cpus=4 --disk-size=30gb
```

## 📊 Monitoring and Metrics

### Storage Usage
```bash
# Check Ceph usage
kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph df

# Check OSD status
kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd status
```

### Application Metrics
```bash
# Block storage metrics
kubectl --context=ramen-dr1 -n block-storage-demo describe pvc nginx-block-pvc

# File storage metrics
kubectl --context=ramen-dr1 -n file-storage-demo describe pvc shared-file-pvc

# Object storage metrics
kubectl --context=ramen-dr1 -n object-storage-demo describe obc vsan-bucket-claim
```

## 🧹 Cleanup

```bash
# Clean up all demos
./demo/scripts/storage/run-storage-demos.sh cleanup

# Manual cleanup
kubectl --context=ramen-dr1 delete namespace block-storage-demo
kubectl --context=ramen-dr1 delete namespace file-storage-demo  
kubectl --context=ramen-dr1 delete namespace object-storage-demo
kubectl --context=ramen-dr2 delete namespace block-storage-demo
kubectl --context=ramen-dr2 delete namespace file-storage-demo
kubectl --context=ramen-dr2 delete namespace object-storage-demo
```

## 📚 Integration with RamenDR

These demos integrate with RamenDR's disaster recovery capabilities:

1. **VolumeReplicationGroups** protect PVCs across clusters
2. **S3 profiles** store metadata for recovery operations  
3. **Storage classes** enable different replication strategies
4. **Volume snapshots** provide point-in-time recovery

For complete DR testing, combine these storage demos with:
- OCM cluster management
- RamenDR operator deployment
- S3 storage for metadata
- Failover testing scenarios

## 🔗 References

- [RamenDR Documentation](../../../README.md)
- [Rook Ceph Documentation](https://rook.io/docs/rook/latest/)
- [Minikube Storage Guide](../docs/MINIKUBE_README.md#storage-demo-rook-ceph-sanvsan-scenarios)
- [Storage Architecture](../docs/storage/)
