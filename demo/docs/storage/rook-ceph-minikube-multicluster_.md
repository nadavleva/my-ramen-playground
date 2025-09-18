# Rook + Ceph Storage for Multi-Minikube Clusters with RamenDR/OCM

This section describes how to adapt your setup for single-node Minikube clusters using Rook to provide different types of Ceph storage (block, file, and object/bucket) in a RamenDR/OCM DR scenario.

---

## 1. Cluster Layout

- **ramen-dr1:** Minikube cluster, 1 node, runs Rook+Ceph + ramen-dr-cluster-operator
- **ramen-dr2:** Minikube cluster, 1 node, runs Rook+Ceph + ramen-dr-cluster-operator
- **ramen-hub:** Minikube cluster, 1 node, runs OCM + ramen-hub-operator (no Ceph needed)

---

## 2. Required Changes to Minikube Clusters

### A. Storage Device Setup

Since Minikube nodes are containers (Docker driver), and generally do not have extra block devices, you need to provide a loopback device for Ceph OSDs:

```bash
# On your Fedora host, for each dr cluster:
sudo mkdir -p /var/lib/minikube-disks/ramen-dr1
sudo dd if=/dev/zero of=/var/lib/minikube-disks/ramen-dr1/ceph-osd.img bs=1G count=10
sudo losetup /dev/loop10 /var/lib/minikube-disks/ramen-dr1/ceph-osd.img

# Mount the loop device into ramen-dr1 Minikube node
minikube -p ramen-dr1 ssh -- 'sudo mkdir -p /mnt/ceph'
# (see Minikube’s --mount and --mount-string options if you want to automate this)
```
Repeat for `ramen-dr2` (use `/dev/loop11` etc).

---

## 3. Validation and Checks

### 3.1 Validate the Device Has Enough Disk Space

Before creating the loop device, ensure your host (Fedora) has enough available disk space:

```bash
df -h /var/lib/minikube-disks
# Or check overall available space
df -h
```

Ensure there is at least as much free space as you want to allocate to the Ceph OSD image (e.g., 10G).

### 3.2 Check StorageClass Availability in Minikube

After installing Rook and Ceph:

```bash
kubectl get storageclass --context=ramen-dr1
kubectl get storageclass --context=ramen-dr2
```

You should see:
- rook-ceph-block
- rook-cephfs
- rook-ceph-bucket

If missing, revisit your Rook StorageClass manifests and apply them.

---

## 4. Rook StorageClass Manifests

### 4.1 Ceph Block Storage (RBD)
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
reclaimPolicy: Delete
allowVolumeExpansion: true
```

### 4.2 Ceph File Storage (CephFS)
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-cephfs
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: rook-ceph
  fsName: myfs
  pool: myfs-data0
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
reclaimPolicy: Delete
allowVolumeExpansion: true
```

### 4.3 Ceph Object Storage (S3-like Buckets)
```yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: my-ceph-bucket
spec:
  generateBucketName: mybucket
  storageClassName: rook-ceph-bucket
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-bucket
provisioner: rook-ceph.ceph.rook.io/bucket
parameters:
  objectStoreName: my-store
  objectStoreNamespace: rook-ceph
```
---

## 5. Cleanup

To clean up the Minikube clusters and the created disk devices:

```bash
# Stop and delete the Minikube cluster
minikube delete -p ramen-dr1
minikube delete -p ramen-dr2

# Remove the loop device and the backing file (do this on the Fedora host)
sudo losetup -d /dev/loop10
sudo rm -rf /var/lib/minikube-disks/ramen-dr1

sudo losetup -d /dev/loop11
sudo rm -rf /var/lib/minikube-disks/ramen-dr2
```

---

## 6. Using Rook and Ceph with Kubernetes on AWS (EKS/ASM) or OpenShift (CRC/ROSA)

### 6.1 AWS – EKS (or Amazon Service Mesh/ASM)

- **Block/File Storage:**  
  Deploy Rook and Ceph using persistent volumes (EBS) as OSD devices.
  - Use storageClassName: gp2, gp3 (EBS types) for Ceph OSDs.
  - Make sure EBS volumes are attached and available to your worker nodes.

- **Object Storage:**  
  You can deploy Rook/Ceph RGW for S3-compatible buckets or use AWS S3 directly.

- **Installation:**  
  - Follow [Rook AWS EKS guide](https://rook.io/docs/rook/latest/Getting-Started/eks/)
  - Use EBS-backed PVs for OSDs in your CephCluster CR.
  - Make sure IAM permissions allow EBS/EC2 operations as needed.

### 6.2 OpenShift (CRC/ROSA/ARO)

- **Block/File/Object:**  
  Rook and Ceph are supported on OpenShift. For CRC (CodeReady Containers), you can use emptyDir or hostPath for OSDs.  
  For production (ROSA/ARO), use additional disks attached to each worker node.

- **Installation:**  
  - For CRC: Expose a directory as a hostPath or loop device for Ceph OSDs.
  - For ROSA/ARO: Attach real disks or use cloud volumes (e.g., AWS EBS).
  - Follow [Rook OpenShift guide](https://rook.io/docs/rook/latest/Getting-Started/openshift/).

- **StorageClass:**  
  - Apply the same StorageClass manifests as above (block, file, object).
  - Validate with `oc get storageclass`.

---

## 7. Example: Verifying StorageClasses

```bash
kubectl get storageclass --context=ramen-dr1
kubectl get storageclass --context=ramen-dr2
```

You should see:
- rook-ceph-block
- rook-cephfs
- rook-ceph-bucket

---

## 8. References

- [Rook Block Storage](https://rook.io/docs/rook/latest/Storage-Configuration/Block-Storage/)
- [Rook File Storage (CephFS)](https://rook.io/docs/rook/latest/Storage-Configuration/File-Storage/)
- [Rook Object Storage (S3)](https://rook.io/docs/rook/latest/Storage-Configuration/Object-Storage/)
- [Rook on EKS](https://rook.io/docs/rook/latest/Getting-Started/eks/)
- [Rook on OpenShift](https://rook.io/docs/rook/latest/Getting-Started/openshift/)