# Guide: Installing Rook and Ceph on Kubernetes (Including Minikube)

This guide walks you through installing Rook (as a storage orchestrator) and Ceph (as a distributed storage backend) on a Kubernetes cluster, including special tips for running on Minikube.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Choosing Storage Devices](#choosing-storage-devices)
3. [Install Rook on Kubernetes](#install-rook-on-kubernetes)
4. [Deploy Ceph Cluster with Rook](#deploy-ceph-cluster-with-rook)
5. [Deploying Rook & Ceph on Minikube](#deploying-rook--ceph-on-minikube)
6. [Verification](#verification)
7. [Cleanup](#cleanup)
8. [References](#references)

---

## Prerequisites

- Kubernetes cluster (v1.21+ recommended).
    - For Minikube: Minikube (v1.25+ recommended)
- kubectl installed and configured.
- Sufficient resources: at least 2 CPUs, 4GB RAM (8GB+ preferred for Ceph).
- For Ceph: At least one available raw block device per Ceph OSD (Object Storage Daemon).

---

## Choosing Storage Devices

**Ceph uses block devices for its OSDs.**  
You need to ensure your Kubernetes nodes have additional disks (not the root filesystem) attached, unformatted, and exclusively available for Ceph.

- **Bare-metal/VM:** Attach one or more empty disks per node.
- **Cloud (GCP/AWS/Azure):** Attach persistent disks/volumes.
- **Minikube:** Use hostPath or loopback devices (see below).

**Example:**  
- `/dev/sdb`, `/dev/sdc` as raw disks.
- If you don't have spare disks (e.g., in Minikube), use a file-backed loop device.

---

## Install Rook on Kubernetes

1. **Clone Rook repository:**
   ```sh
   git clone --single-branch --branch v1.13.2 https://github.com/rook/rook.git
   cd rook/deploy/examples
   ```

2. **Install the Rook Operator:**
   ```sh
   kubectl create -f crds.yaml -f common.yaml -f operator.yaml
   ```

---

## Deploy Ceph Cluster with Rook

1. **Create a Ceph Cluster Custom Resource (CR):**
   - Edit `cluster.yaml` to match your device setup.
   - Minimal example:
     ```yaml
     apiVersion: ceph.rook.io/v1
     kind: CephCluster
     metadata:
       name: rook-ceph
       namespace: rook-ceph
     spec:
       cephVersion:
         image: quay.io/ceph/ceph:v18.2.0
       dataDirHostPath: /var/lib/rook
       storage:
         useAllNodes: true
         useAllDevices: false
         devices:
         - name: "sdb" # Change to your disk
     ```
   - If using all available disks, set `useAllDevices: true`.

2. **Apply the cluster manifest:**
   ```sh
   kubectl create -f cluster.yaml
   ```

3. **Create StorageClass and Pool:**
   ```sh
   kubectl create -f csi/rbd/storageclass.yaml
   kubectl create -f csi/rbd/pvc.yaml
   ```

---

## Deploying Rook & Ceph on Minikube

**Minikube tips:**

- **Enable Minikube's `none` driver** for full access to host devices, or use Docker/VMs.
- **Create a loopback device** for Ceph OSD:

  ```sh
  # Create a 10GB file
  sudo dd if=/dev/zero of=/var/lib/rook-ceph-osd0.img bs=1G count=10
  # Set up loop device
  sudo losetup /dev/loop10 /var/lib/rook-ceph-osd0.img
  # Confirm
  lsblk | grep loop10
  ```

- **Edit `cluster.yaml`** to reference `/dev/loop10`:
  ```yaml
  devices:
    - name: "loop10"
  ```

- **Ensure `/var/lib/rook` exists and is writable on your Minikube VM.**

- **Start Minikube with more resources:**
  ```sh
  minikube start --cpus=4 --memory=8192
  ```

- **Install Rook and Ceph as above.**

---

## Verification

1. **Check Rook and Ceph pods:**
   ```sh
   kubectl -n rook-ceph get pods
   ```

2. **Check Ceph status:**
   ```sh
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
   ```

---

## Cleanup

To remove Rook and Ceph:

```sh
kubectl delete -f cluster.yaml
kubectl delete -f operator.yaml
kubectl delete -f common.yaml
kubectl delete -f crds.yaml
```

For Minikube, also detach the loop device:
```sh
sudo losetup -d /dev/loop10
sudo rm /var/lib/rook-ceph-osd0.img
```

---

## References

- [Rook Docs](https://rook.io/docs/rook/latest/)
- [Ceph Docs](https://docs.ceph.com/en/latest/)
- [YouTube: Storage on Minikube cluster using Ceph and Rook](https://www.youtube.com/watch?v=pG1pxnfplsc)