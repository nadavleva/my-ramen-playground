# How to Create a File-Backed Loop Device as a Spare Disk for Minikube

This guide explains how to create a file-backed loop device on Linux (e.g., Fedora, Ubuntu) and use it as a block device for Rook/Ceph or other storage in Minikube clusters.

---

## 1. Why Use a File-Backed Loop Device?

- **Minikube (and most local Kubernetes setups) do not have spare physical disks.**
- Ceph and similar storage systems prefer to use raw block devices.
- A **loop device** is a file on your host that the OS presents as a block device—perfect for simulating extra disks for storage daemons.

---

## 2. Steps to Create and Use a Loop Device

### Step 1: Create a Disk Image File

Choose a location with enough free disk space (e.g., `/var/lib/minikube-disks/ramen-dr1`):

```bash
sudo mkdir -p /var/lib/minikube-disks/ramen-dr1
sudo dd if=/dev/zero of=/var/lib/minikube-disks/ramen-dr1/ceph-osd.img bs=1G count=10
```

- `bs=1G count=10` creates a 10GB file. Adjust size as needed.

### Step 2: Attach the File as a Loop Device

```bash
sudo losetup -fP /var/lib/minikube-disks/ramen-dr1/ceph-osd.img
```
- This will use the first available `/dev/loopX` device.

**To find which loop device was used:**
```bash
sudo losetup -a
```
Look for the line containing your file path, e.g. `/dev/loop10: [2065]:... (/var/lib/minikube-disks/ramen-dr1/ceph-osd.img)`

### Step 3: Pass the Loop Device into Minikube

How you do this depends on your Minikube driver:
- **Docker driver:** You can mount host devices into the Minikube container.
- **Example:**  
  1. Stop Minikube if running:
     ```bash
     minikube stop -p ramen-dr1
     ```
  2. Start Minikube with the device mounted:
     ```bash
     minikube start -p ramen-dr1 \
       --mount --mount-string="/dev/loop10:/dev/loop10"
     ```
  3. Verify inside Minikube node:
     ```bash
     minikube ssh -p ramen-dr1
     lsblk
     # You should see /dev/loop10 as a raw device
     ```

> **Note:** If Minikube is running as a VM (KVM, VirtualBox), you may need to attach the disk as a virtual disk or use `--mount`.

---

## 3. Using the Loop Device with Rook/Ceph

- In your Rook CephCluster manifest, specify the device in the `devices` section, e.g.:
    ```yaml
    storage:
      useAllNodes: true
      useAllDevices: false
      devices:
      - name: "loop10"
    ```
- Apply your CephCluster manifest as usual.

---

## 4. Cleaning Up

When done, detach and remove the loop device and backing file:

```bash
sudo losetup -d /dev/loop10
sudo rm -f /var/lib/minikube-disks/ramen-dr1/ceph-osd.img
```

---

## 5. Tips

- You can create multiple such loop devices for more OSDs.
- Always make sure the loop device is not in use before detaching.
- If Minikube is restarted, you may need to re-attach and re-mount the loop device.

---

## References

- [losetup man page](https://man7.org/linux/man-pages/man8/losetup.8.html)
- [Rook Ceph Getting Started](https://rook.io/docs/rook/latest/Getting-Started/)