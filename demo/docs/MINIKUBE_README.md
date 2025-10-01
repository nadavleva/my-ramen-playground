# 🎯 RamenDR Demo with minikube

This guide shows how to run the complete RamenDR demo using **minikube** instead of kind clusters.

## ✅ **Prerequisites**
- **vCPUs:** 2+ per cluster (4+ recommended for better performance)
- **RAM:** 4GB minimum per cluster, 8GB recommended
- **Docker** (for the `docker` driver)
- **minikube**
- **kubectl**
- **helm**

## Storage Backend Options

### Option A: HostPath Storage (Default - Simple)
```bash
# Uses minikube's default hostpath storage
./demo/scripts/minikube_setup.sh
```

### Option B: Ceph Storage (Advanced - Production-like)
```bash
# Setup with Ceph distributed storage
./demo/scripts/minikube_setup.sh --storage-backend=ceph

# Additional requirements for Ceph:
# - Extra 2GB RAM per cluster
# - Block devices for OSDs (can be set in the Block Device Setup)
# - Longer setup time (~10-15 minutes

## Block Device Setup

Each DR cluster requires a dedicated block device for Ceph OSD. These are typically created as loop devices backed by image files:

```bash
# Example for two DR clusters
sudo mkdir -p /var/lib/minikube-disks/ramen-dr1
sudo mkdir -p /var/lib/minikube-disks/ramen-dr2
sudo dd if=/dev/zero of=/var/lib/minikube-disks/ramen-dr1/ceph-osd.img bs=1G count=10
sudo dd if=/dev/zero of=/var/lib/minikube-disks/ramen-dr2/ceph-osd.img bs=1G count=10
sudo losetup /dev/loop0 /var/lib/minikube-disks/ramen-dr1/ceph-osd.img
sudo losetup /dev/loop1 /var/lib/minikube-disks/ramen-dr2/ceph-osd.img
```

### **Required Tools:**
```bash
# Install minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl

# Install clusteradm (for OCM setup)
curl -LO https://github.com/open-cluster-management-io/clusteradm/releases/download/v0.9.0/clusteradm_linux_amd64.tar.gz
tar -xzf clusteradm_linux_amd64.tar.gz
sudo install clusteradm /usr/local/bin/clusteradm


# Install Docker (for minikube driver)
sudo apt update && sudo apt install -y docker.io
sudo usermod -aG docker $USER
```

### **System Requirements:**
- **Memory**: At least 9GB RAM (3GB per cluster × 3 clusters) 
  - ⚠️ **Minikube minimum**: 1800MB per cluster (enforced)
- **CPU**: At least 6 cores (2 cores per cluster × 3 clusters)
  - ⚠️ **Minikube minimum**: 2 cores per cluster (enforced)
- **Disk**: 20GB free space
- **OS**: Linux with Docker support

**🚨 CRITICAL**: These are hard minimums enforced by minikube. Lower values will fail with resource errors.

## Critical Requirements

1. OCM Controller Placement
   - cluster-manager: ONLY on hub cluster
   - klusterlet: ONLY on DR clusters
   - Do NOT install cluster-manager on DR clusters

2. Resource Placement
   - Hub-only resources: DRPolicy, DRPlacementControl, PlacementRule
   - DR cluster resources: ClusterClaim, application workloads

3. Networking
   - Use Minikube IP for hub API server
   - Do not use hostNetwork unless absolutely necessary
   - Verify connectivity between clusters

### **🚨 CRITICAL: Environment Setup**
```bash
# MUST unset KUBECONFIG before starting minikube demo
unset KUBECONFIG

# Verify it's unset
echo $KUBECONFIG  # Should be empty
```

**⚠️ Why this matters**: If `KUBECONFIG` points to other Kubernetes installations (like k3s), minikube will fail to start with permission errors.

## Common Issues

1. Registration Failures
   - Check cluster-manager is only on hub
   - Verify ManagedCluster status
   - Check klusterlet logs

2. Resource Misplacement
   - DRPolicy must be on hub only
   - Clean up any stray resources on DR clusters

3. Network Connectivity
   - Use `minikube -p ramen-hub ip` to get hub address
   - Test connectivity with wget or curl

## 🚀 **Quick Start**

### **Option 1: Automated Setup (Not Recommended - need to validate with the ocm setup)**
```bash
# Complete automated demo with minikube
./scripts/fresh-demo-minikube.sh
```

### **Option 2: Manual Step-by-Step Setup**
```bash
# 0. Clean existing environment (if needed)
./demo/scripts/cleanup-all.sh
# Or remove clusters directly:
minikube delete -p ramen-hub
minikube delete -p ramen-dr1
minikube delete -p ramen-dr2
# Remove context
kubectl config delete-context ramen-hub
kubectl config delete-context ramen-dr1
kubectl config delete-context ramen-dr2

# 1. Setup minikube clusters
./demo/scripts/minikube_setup.sh

# 2. Setup OCM resources (CRITICAL) - using clusteradm
./demo/scripts/set-ocm-using-clustadmin.sh
./demo/scripts/setup-ocm-resources.sh

# 3. Install RamenDR operators
echo "3" | ./demo/scripts/minikube_quick-install.sh

# Verify OCM setup
# Check that cluster-manager exists ONLY on hub
kubectl --context=ramen-hub -n open-cluster-management get deployment
# Check ManagedCluster status
kubectl --context=ramen-hub get managedcluster

# 3. Install storage dependencies (VolSync, Velero CRDs)
./demo/scripts/install-storage-dependencies.sh
./demo/scripts/install-missing-resource-classes.sh

# 4. Install RamenDR operators
echo "3" | ./demo/scripts/minikube_quick-install.sh

# 5. Create DR Policy and Placement Resources
./demo/scripts/setup-dr-policy.sh

# 6. Deploy S3 storage 
./demo/scripts/deploy-ramendr-s3.sh

# 7. Setup cross-cluster access
./demo/scripts/setup-cross-cluster-s3.sh

# 8. Verify S3 access
# Test MinIO access from DR clusters
HOST_IP=$(minikube -p ramen-hub ip)
kubectl --context=ramen-dr1 run test-minio --image=minio/mc --rm -i --restart=Never -- \
    /bin/sh -c "mc alias set myminio http://${HOST_IP}:30900 minioadmin minioadmin && mc ls myminio/ramen-metadata/"

# 9. Create test application (Choose your approach)

# Approach A: Direct VRG (Simple - same as KIND demo)
```bash
# Deploy nginx application with PVC
kubectl --context=ramen-dr1 apply -f demo/yaml/test-application/nginx-with-pvc-fixed.yaml

# Create VRG to protect the application  
kubectl --context=ramen-dr1 apply -f demo/yaml/test-application/nginx-vrg-correct.yaml

# Verify VRG creation
kubectl --context=ramen-dr1 get vrg -n test-app
```

## Approach B: DRPlacement (Advanced - OCM managed)
```bash
# Uses OCM for automated placement management
./demo/scripts/setup-test-app-drpc.sh

# Verify DRPC creation
kubectl --context=ramen-hub get drplacementcontrol -n test-app
```

**Which to choose?**
- **Approach A**: Simpler, direct control, same as KIND demo
- **Approach B**: Production-like, automated placement, requires OCM

# 10. Run failover demo
./demo/scripts/minikube_demo-failover.sh
```

**⚠️ Important Notes:**
1. OCM setup (step 3) is **critical** - without it, clusters won't register properly
2. Verify that `cluster-manager` runs **only on the hub cluster**
3. Check ManagedCluster status shows `Joined` and `Available` before proceeding
4. Ensure S3 endpoint uses the correct Minikube IP address

## 🔧 **minikube Configuration**

The setup creates 3 minikube profiles:

- **`ramen-hub`** - RamenDR hub operator (management cluster)
- **`ramen-dr1`** - Primary DR cluster
- **`ramen-dr2`** - Secondary DR cluster

### **Default Settings:**
- **Driver**: `docker` (can be changed with `--driver=virtualbox`)
- **Memory**: `4096MB` per cluster
- **CPUs**: `2` per cluster
- **Kubernetes**: `v1.27.3`
- **Addons**: `storage-provisioner`, `default-storageclass`, `volumesnapshots`, `csi-hostpath-driver`

### **CSI and Storage Support:**
✅ **Volume Snapshots**: Enabled via `volumesnapshots` addon  
✅ **CSI Hostpath Driver**: Enabled via `csi-hostpath-driver` addon  
✅ **Storage Classes**: Multiple classes for different scenarios  
✅ **Persistent Storage**: Real persistent storage (better than kind)  
✅ **VolSync Compatible**: CSI driver supports snapshot-based replication

### **Custom Configuration:**
```bash
# Use different settings
./scripts/setup-minikube.sh --memory=6144 --cpus=3 --driver=virtualbox
```

## 📊 **Managing minikube Clusters**

### **Switching Between Clusters:**
```bash
# Switch kubectl context
kubectl config use-context ramen-hub
kubectl config use-context ramen-dr1  
kubectl config use-context ramen-dr2

# Or use minikube profile
minikube profile ramen-hub
kubectl get nodes
```

### **Accessing Services:**
```bash
# MinIO console on hub cluster
minikube service minio --profile=ramen-hub --url
# Then navigate to the URL in your browser

# Alternative: Port forwarding
kubectl port-forward -n minio-system service/minio 9001:9001 --context=ramen-hub
```

### **Cluster Status:**
```bash
# List all profiles
minikube profile list

# Check specific cluster status
minikube status --profile=ramen-hub
minikube status --profile=ramen-dr1
minikube status --profile=ramen-dr2
```

### **Cluster Operations:**
```bash
# Start a stopped cluster
minikube start --profile=ramen-dr1

# Stop a cluster (preserves data)
minikube stop --profile=ramen-dr1

# SSH into cluster node
minikube ssh --profile=ramen-hub

# View cluster dashboard
minikube dashboard --profile=ramen-hub
```

## 🔄 **Demo Workflow**

### **1. Application Protection Demo:**
```bash
# Deploy and protect an application
kubectl config use-context ramen-dr1
kubectl create namespace test-app

# Deploy nginx with PVC
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: test-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: nginx-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-pvc
  namespace: test-app
  labels:
    app: nginx
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# Create VRG to protect the application
kubectl apply -f examples/test-application/nginx-vrg-correct.yaml
```

### **2. Disaster Recovery Demo:**
```bash
# Run the automated failover demo
./examples/demo-failover-minikube.sh
```

## 🧹 **Cleanup**

### **Remove Demo Resources:**
```bash
# Remove test applications
kubectl delete namespace test-app --context=ramen-dr1
kubectl delete namespace test-app --context=ramen-dr2
```

### **Full Cleanup:**
```bash
# Delete all minikube profiles
minikube delete --profile=ramen-hub
minikube delete --profile=ramen-dr1  
minikube delete --profile=ramen-dr2

# Or use the cleanup script
./scripts/cleanup-all.sh
```

## 🔧 **Troubleshooting**

### **Common Issues:**

**1. Insufficient Resources:**
```bash
# Error: Not enough memory/CPU
# Solution: Reduce cluster resources or increase system resources
./scripts/setup-minikube.sh --memory=2048 --cpus=1
```

**2. Docker Driver Issues:**
```bash
# Error: Docker daemon not running
sudo systemctl start docker
sudo systemctl enable docker

# Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in
```

**3. Context Issues:**
```bash
# Contexts not available
minikube update-context --profile=ramen-hub
minikube update-context --profile=ramen-dr1
minikube update-context --profile=ramen-dr2
```

**4. Pod Scheduling Issues:**
```bash
# Check node resources
kubectl top nodes --context=ramen-dr1

# Check pod resource requests
kubectl describe pods -n ramen-system --context=ramen-dr1
```

**5. Storage Issues:**
```bash
# Check storage classes
kubectl get storageclass --context=ramen-dr1

# Verify PVCs
kubectl get pvc -A --context=ramen-dr1
```

### **Performance Tips:**

1. **Use Docker Driver**: More efficient than VirtualBox
2. **Allocate Sufficient Resources**: At least 4GB RAM per cluster
3. **Use SSD Storage**: Faster I/O for containers
4. **Close Unused Applications**: Free up system resources

## 📈 **minikube vs kind Comparison**

| Feature | minikube | kind |
|---------|----------|------|
| **Setup** | More complex (multiple profiles) | Simpler (multiple clusters) |
| **Resources** | Higher resource usage | Lower resource usage |
| **Networking** | More stable | Requires workarounds |
| **Storage** | Better persistent storage | Limited storage options |
| **Production-like** | More realistic environment | More containerized |
| **Debugging** | Better dashboard/tools | Simpler logs |

## 🎯 **Use Cases**

**Choose minikube when:**
- You need realistic persistent storage behavior
- Want to test storage classes and CSI drivers
- Need better networking stability
- Want to use the Kubernetes dashboard
- Testing production-like scenarios

**Choose kind when:**
- You need faster startup times
- Want to test multiple Kubernetes versions
- Need CI/CD integration
- Working with limited system resources
- Focus on application testing rather than infrastructure

## 🗄️ **Storage Demo: Rook Ceph SAN/VSAN Scenarios**

This section demonstrates storage-focused disaster recovery scenarios using Rook Ceph to provide different storage types (Block, File, and Object) for testing SAN and VSAN replication patterns.

### **Prerequisites for Storage Demo**

Before running the storage demo, ensure your minikube clusters are configured with adequate resources:

```bash
# Recommended minikube settings for Ceph
minikube start --profile=ramen-dr1 --memory=6144 --cpus=3 --disk-size=20gb
minikube start --profile=ramen-dr2 --memory=6144 --cpus=3 --disk-size=20gb
minikube start --profile=ramen-hub --memory=4096 --cpus=2 --disk-size=10gb
```

**⚠️ Important**: Ceph requires more resources than basic demos. Each DR cluster needs at least 6GB RAM and 3 CPUs.

### **Storage Types Supported**

| Storage Type | Use Case | StorageClass | Access Mode | Replication Method |
|--------------|----------|--------------|-------------|------------------|
| **Block (RBD)** | Traditional SAN | `rook-ceph-block` | RWO | VolSync (async) |
| **File (CephFS)** | Shared file storage | `rook-cephfs` | RWX | VolSync (async) |
| **Object (S3)** | VSAN metadata | `rook-ceph-bucket` | N/A | Object replication |

### **Quick Start: Storage-Only Demo**

**Step 1: Setup Basic Clusters**
```bash
# Setup minikube clusters (if not already done)
./demo/scripts/minikube_setup.sh

# Setup OCM for cluster management
./demo/scripts/set-ocm-using-clustadmin.sh
./demo/scripts/setup-ocm-resources.sh
```

**Step 2: Deploy Rook Ceph Storage**
```bash
# Install Rook Ceph on DR clusters only
./demo/scripts/storage/set_ceph_storage.sh

# Verify Ceph cluster health
kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
kubectl --context=ramen-dr2 -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
```

**Step 3: Install Storage Dependencies**
```bash
# Install VolSync and other storage dependencies
./demo/scripts/install-storage-dependencies.sh
./demo/scripts/install-missing-resource-classes.sh
```

**Step 4: Install RamenDR Operators**
```bash
# Install RamenDR with storage focus
echo "3" | ./demo/scripts/minikube_quick-install.sh
```

**Step 5: Verify Storage Classes**
```bash
# Check available storage classes
kubectl --context=ramen-dr1 get storageclass
kubectl --context=ramen-dr2 get storageclass

# Expected output should include:
# - rook-ceph-block (for SAN scenarios)  
# - rook-cephfs (for shared storage)
# - standard (minikube default)
```

### **Demo Scenarios**

#### **Scenario 1: Block Storage SAN Demo**

Test traditional SAN-like block storage replication:

```bash
# Deploy nginx application with block storage
kubectl --context=ramen-dr1 apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: block-storage-demo
  labels:
    ramendr.openshift.io/protected: "true"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-block-pvc
  namespace: block-storage-demo
  labels:
    app: nginx-block
    ramendr.openshift.io/protected: "true"
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: rook-ceph-block
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-block
  namespace: block-storage-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-block
  template:
    metadata:
      labels:
        app: nginx-block
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        volumeMounts:
        - name: storage
          mountPath: /usr/share/nginx/html
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo "<h1>Block Storage SAN Demo</h1>" > /usr/share/nginx/html/index.html
          echo "<p>Storage Type: Rook Ceph RBD (Block)</p>" >> /usr/share/nginx/html/index.html
          echo "<p>Timestamp: \$(date)</p>" >> /usr/share/nginx/html/index.html
          echo "<p>Node: \$(hostname)</p>" >> /usr/share/nginx/html/index.html
          nginx -g "daemon off;"
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: nginx-block-pvc
EOF

# Create VRG for protection
kubectl --context=ramen-dr1 apply -f - <<EOF
apiVersion: ramendr.openshift.io/v1alpha1
kind: VolumeReplicationGroup
metadata:
  name: block-storage-vrg
  namespace: block-storage-demo
spec:
  pvcSelector:
    matchLabels:
      app: nginx-block
  replicationState: primary
  s3Profiles:
  - minio-s3
  async:
    schedulingInterval: 2m
    replicationClassSelector:
      matchLabels:
        ramendr.openshift.io/replicationID: ramen-volsync
    volumeSnapshotClassSelector:
      matchLabels:
        velero.io/csi-volumesnapshot-class: "true"
EOF

# Test the application
kubectl --context=ramen-dr1 get pods -n block-storage-demo
kubectl --context=ramen-dr1 get vrg -n block-storage-demo
```

#### **Scenario 2: File Storage (CephFS) Demo**

Test shared file storage scenarios:

```bash
# Deploy shared file storage application
kubectl --context=ramen-dr1 apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: file-storage-demo
  labels:
    ramendr.openshift.io/protected: "true"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-file-pvc
  namespace: file-storage-demo
  labels:
    app: file-demo
    ramendr.openshift.io/protected: "true"
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: rook-cephfs
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: file-writer
  namespace: file-storage-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: file-writer
  template:
    metadata:
      labels:
        app: file-writer
    spec:
      containers:
      - name: writer
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
        - |
          while true; do
            echo "Writer \$(hostname) - \$(date)" >> /shared/log.txt
            sleep 30
          done
        volumeMounts:
        - name: shared-storage
          mountPath: /shared
      volumes:
      - name: shared-storage
        persistentVolumeClaim:
          claimName: shared-file-pvc
EOF

# Verify shared access
kubectl --context=ramen-dr1 get pods -n file-storage-demo
kubectl --context=ramen-dr1 exec -n file-storage-demo deployment/file-writer -- tail -f /shared/log.txt
```

#### **Scenario 3: Object Storage VSAN Demo**

Test object storage for VSAN-like scenarios:

```bash
# Create object bucket claim
kubectl --context=ramen-dr1 apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: object-storage-demo
---
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: vsan-bucket
  namespace: object-storage-demo
spec:
  generateBucketName: vsan-demo
  storageClassName: rook-ceph-bucket
EOF

# Check bucket creation
kubectl --context=ramen-dr1 get obc -n object-storage-demo
kubectl --context=ramen-dr1 get secret -n object-storage-demo
```

### **Troubleshooting Storage Issues**

#### **Common Ceph Issues**

**1. Ceph Cluster Not Ready**
```bash
# Check Ceph cluster status
kubectl --context=ramen-dr1 -n rook-ceph get cephcluster

# Debug with toolbox
kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd status
```

**2. CephFS Creation Timeout**
```bash
# Check CephFS status
kubectl --context=ramen-dr1 -n rook-ceph get cephfilesystem myfs -o wide

# Check MDS pods (required for CephFS)
kubectl --context=ramen-dr1 -n rook-ceph get pods -l app=rook-ceph-mds

# Debug MDS deployment
kubectl --context=ramen-dr1 -n rook-ceph describe cephfilesystem myfs

# If stuck, delete and recreate CephFS
kubectl --context=ramen-dr1 -n rook-ceph delete cephfilesystem myfs
kubectl --context=ramen-dr1 apply -f demo/yaml/storage-demos/ceph-filesystem.yaml
```

**3. PVC Stuck in Pending**
```bash
# Check storage class
kubectl --context=ramen-dr1 get storageclass

# Check provisioner logs
kubectl --context=ramen-dr1 -n rook-ceph logs deployment/rook-ceph-operator

# Check CSI driver
kubectl --context=ramen-dr1 -n rook-ceph get pods -l app=csi-rbdplugin
kubectl --context=ramen-dr1 -n rook-ceph get pods -l app=csi-cephfsplugin
```

**4. Insufficient Storage Space**
```bash
# Check available space in Ceph
kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph df

# Check OSD status
kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd df

# Check disk usage on minikube node
minikube ssh -p ramen-dr1 -- df -h
```

**5. Operator/Component Issues**
```bash
# Check Rook operator status
kubectl --context=ramen-dr1 -n rook-ceph get pods -l app=rook-ceph-operator

# Check operator logs
kubectl --context=ramen-dr1 -n rook-ceph logs deployment/rook-ceph-operator --tail=50

# Check all Ceph components
kubectl --context=ramen-dr1 -n rook-ceph get pods
```

**6. Script Timeout Issues**
If the storage setup script times out during long operations:

```bash
# Check if resources were created despite timeout
kubectl --context=ramen-dr1 -n rook-ceph get all

# Monitor CephFS creation progress
watch kubectl --context=ramen-dr1 -n rook-ceph get cephfilesystem myfs

# Check events for error messages
kubectl --context=ramen-dr1 -n rook-ceph get events --sort-by=.metadata.creationTimestamp
```

**7. Webhook and API Validation Errors**
When applying YAML files results in validation errors:

```bash
# Common webhook/validation error: "strict decoding error: unknown field"
# This means the YAML contains fields not supported by the CRD version

# Check CRD version and supported fields
kubectl get crd cephclusters.ceph.rook.io -o yaml | grep -A 10 openAPIV3Schema

# Retry with exponential backoff (built into our scripts)
# If persistent, check for invalid fields in YAML files

# For stuck resources with finalizers
kubectl --context=ramen-dr1 -n rook-ceph patch cephfilesystem myfs --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
```

**8. Zero OSDs Problem**
If Ceph shows "0 osds: 0 up, 0 in":

```bash
# This usually means no storage devices were found
# Check OSD preparation logs
kubectl --context=ramen-dr1 -n rook-ceph logs -l app=rook-ceph-osd-prepare

# Check if devices are available
kubectl --context=ramen-dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree

# For minikube, ensure storage directories exist
minikube ssh -p ramen-dr1 -- "sudo ls -la /var/lib/rook/"

# Recreate cluster with validated configuration
kubectl --context=ramen-dr1 -n rook-ceph delete cephcluster rook-ceph
kubectl --context=ramen-dr1 apply -f demo/yaml/storage-demos/ceph-cluster-simple.yaml
```

**9. Finalizer Stuck Resources**
When resources won't delete due to finalizers:

```bash
# Check for finalizers
kubectl --context=ramen-dr1 -n rook-ceph get cephfilesystem myfs -o yaml | grep -A 5 finalizers

# Remove finalizers (use with caution)
kubectl --context=ramen-dr1 -n rook-ceph patch cephfilesystem myfs --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'

# Force delete if still stuck
kubectl --context=ramen-dr1 -n rook-ceph delete cephfilesystem myfs --force --grace-period=0
```

#### **Performance Tuning**

**For Better Ceph Performance:**
```bash
# Increase minikube resources
minikube stop --profile=ramen-dr1
minikube start --profile=ramen-dr1 --memory=8192 --cpus=4

# Use faster storage if available
minikube start --profile=ramen-dr1 --disk-size=30gb
```

### **Storage Demo Cleanup**

```bash
# Clean up demo applications
kubectl --context=ramen-dr1 delete namespace block-storage-demo
kubectl --context=ramen-dr1 delete namespace file-storage-demo
kubectl --context=ramen-dr1 delete namespace object-storage-demo

# Clean up Ceph (optional)
kubectl --context=ramen-dr1 -n rook-ceph delete cephcluster rook-ceph
kubectl --context=ramen-dr2 -n rook-ceph delete cephcluster rook-ceph

# Remove Rook completely (optional)
kubectl --context=ramen-dr1 delete namespace rook-ceph
kubectl --context=ramen-dr2 delete namespace rook-ceph
```

### **Advanced Storage Scenarios**

#### **Multi-StorageClass Failover**
Test applications using multiple storage types simultaneously:

```bash
# Deploy app with both block and file storage
kubectl --context=ramen-dr1 apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: multi-storage-demo
---
# Block storage for database
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-block-pvc
  namespace: multi-storage-demo
  labels:
    app: multi-demo
    storage-type: block
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 2Gi}}
  storageClassName: rook-ceph-block
---
# File storage for shared content
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: web-file-pvc
  namespace: multi-storage-demo
  labels:
    app: multi-demo
    storage-type: file
spec:
  accessModes: [ReadWriteMany]
  resources: {requests: {storage: 1Gi}}
  storageClassName: rook-cephfs
EOF
```

#### **Storage Performance Testing**
Use fio to test storage performance:

```bash
kubectl --context=ramen-dr1 run fio-test --image=ljishen/fio \
  --rm -i --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"fio-test","image":"ljishen/fio","command":["fio","--name=test","--ioengine=libaio","--direct=1","--bs=4k","--rw=randwrite","--size=100M","--numjobs=1","--time_based","--runtime=60"],"volumeMounts":[{"name":"test-vol","mountPath":"/data"}]}],"volumes":[{"name":"test-vol","persistentVolumeClaim":{"claimName":"fio-test-pvc"}}]}}'
```

---

## 📚 **Next Steps**

After completing the minikube demo:

1. 📖 **Read Architecture Guide**: `./examples/RAMENDR_ARCHITECTURE_GUIDE.md`
2. 🔍 **Explore CRDs**: `kubectl get crd | grep ramendr`
3. 📊 **Monitor Components**: `kubectl get pods -n ramen-system -A`
4. 🧪 **Test with Real Apps**: Deploy your own applications with VRGs
5. 🔄 **Practice DR Workflows**: Test different failure scenarios
6. 🗄️ **Explore Storage**: Test different Ceph storage types and replication patterns

Happy disaster recovery testing with minikube! 🚀
