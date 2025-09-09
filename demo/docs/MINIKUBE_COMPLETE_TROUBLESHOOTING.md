# MINIKUBE RamenDR Complete Troubleshooting Guide

## 🚨 **CRITICAL: ALL KNOWN ISSUES & BULLETPROOF FIXES**

This guide documents **every issue we've encountered** during RamenDR minikube demo development and provides **automatic prevention**.

---

## 🔧 **AUTOMATIC ISSUE PREVENTION**

### ✅ **Fixed in v2.0+ Scripts - No Manual Action Needed:**

1. **KUBECONFIG Conflicts** → Auto-detection and unset
2. **inotify Limits** → Persistent system configuration  
3. **OCM CRDs** → Automatic installation
4. **Cross-cluster Networking** → Host network + dynamic endpoints
5. **Image Registry** → Podman-to-docker copying
6. **File Paths** → Corrected after reorganization
7. **Sequential Creation** → Eliminates timing issues
8. **Resource Requirements** → Documented minimums

---

## 📋 **ISSUE CATALOG & SOLUTIONS**

### **Issue #1: KUBECONFIG Conflicts**

**Symptoms:**
```bash
minikube start -p ramen-hub
# ❌ Error: failed to start node: Failed kubeconfig update
# ❌ Error: mkdir /etc/rancher: permission denied
```

**Root Cause:** 
Existing `KUBECONFIG` environment variable (often from k3s installation in `~/.bashrc`)

**✅ Automatic Fix in Scripts:**
```bash
# Scripts now auto-detect and handle this
unset KUBECONFIG
env KUBECONFIG="" minikube start -p ramen-hub
```

**Manual Fix (if needed):**
```bash
# Check your ~/.bashrc for this line:
grep KUBECONFIG ~/.bashrc
# Remove: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Or temporarily override:
unset KUBECONFIG
```

---

### **Issue #2: inotify System Limits**

**Symptoms:**
```bash
# ramen-dr2 cluster fails to start
minikube logs -p ramen-dr2
# Shows: "inotify_init: too many open files"
# Shows: "restart counter is at 102"
```

**Root Cause:**
Linux kernel inotify limits too low for Kubernetes file watching

**✅ Automatic Fix in Scripts:**
```bash
# Scripts now create persistent configuration
sudo sysctl -w fs.inotify.max_user_watches=1048576
sudo sysctl -w fs.inotify.max_user_instances=8192

# Persistent configuration in /etc/sysctl.d/99-kubernetes-inotify.conf
```

**Manual Verification:**
```bash
cat /proc/sys/fs/inotify/max_user_watches
# Should show: 1048576
```

---

### **Issue #3: Missing OCM CRDs**

**Symptoms:**
```bash
kubectl logs deployment/ramen-hub-operator -n ramen-system -c manager
# ❌ ERROR: timed out waiting for cache to be synced for Kind *v1.ManagedCluster
# ❌ ERROR: no matches for kind "ManagedCluster"
```

**Root Cause:**
RamenDR hub operator expects OCM (Open Cluster Management) CRDs that aren't installed in lightweight K8s

**✅ Automatic Fix in Scripts:**
Scripts now automatically install 5 missing OCM CRDs:
- `ManagedCluster`
- `PlacementRule`
- `Placement` 
- `ManagedClusterView`
- `ManifestWork`

**Manual Fix (if needed):**
```bash
kubectl config use-context ramen-hub
kubectl rollout restart deployment ramen-hub-operator -n ramen-system
```

---

### **Issue #4: Cross-Cluster Networking**

**Symptoms:**
```bash
# Empty S3 buckets (no backups)
mc ls minio-host/ramen-metadata/
# Empty or connection refused

# VRG status stuck
kubectl get vrg -A
# Status: Unknown instead of Primary/Secondary
```

**Root Cause:**
Minikube clusters are network-isolated; cannot access services across clusters

**✅ Automatic Fix in Scripts:**
```bash
# MinIO now uses host network + NodePort
hostNetwork: true
type: NodePort
nodePort: 30900  # S3 API
nodePort: 30901  # Console

# S3 endpoint dynamically configured
http://<hub-cluster-ip>:30900
```

**Manual Verification:**
```bash
# Test S3 connectivity from DR clusters
curl http://$(minikube ip -p ramen-hub):30900/minio/health/live
# Should return: 200 OK
```

---

### **Issue #5: Podman-to-Docker Image Issues**

**Symptoms:**
```bash
kubectl get pods -n ramen-system
# ❌ ramen-hub-operator: ImagePullBackOff
# ❌ ramen-dr-cluster-operator: ImagePullBackOff
```

**Root Cause:**
Images built with podman but minikube uses docker registry

**✅ Automatic Fix in Scripts:**
```bash
# Scripts now automatically copy images
if make podman-build; then
    podman save quay.io/ramendr/ramen-operator:latest | docker load
    minikube -p <profile> image load quay.io/ramendr/ramen-operator:latest
fi
```

**Manual Fix (if needed):**
```bash
podman save quay.io/ramendr/ramen-operator:latest | docker load
minikube -p ramen-hub image load quay.io/ramendr/ramen-operator:latest
```

---

### **Issue #6: Sequential vs Parallel Cluster Creation**

**Symptoms:**
```bash
# Third cluster (ramen-dr2) fails consistently
minikube status -p ramen-dr2
# kubelet: Stopped, apiserver: Stopped
# Certificate/timing issues
```

**Root Cause:**
Parallel cluster creation causes resource contention and timing issues

**✅ Automatic Fix in Scripts:**
```bash
# Scripts now use sequential creation with proper waiting
minikube start -p ramen-hub --wait=true
wait_for_ready
minikube start -p ramen-dr1 --wait=true  
wait_for_ready
minikube start -p ramen-dr2 --wait=true
```

---

### **Issue #7: File Path Issues After Reorganization**

**Symptoms:**
```bash
./demo/scripts/deploy-ramendr-s3.sh
# ❌ Error: MinIO deployment file not found!
# ❌ Error: ./scripts/utils.sh: No such file or directory
```

**Root Cause:**
File reorganization from `examples/` to `demo/` structure broke paths

**✅ Automatic Fix in Scripts:**
```bash
# All paths now corrected:
EXAMPLES_DIR="$(dirname "$(dirname "$0")")/yaml"  # demo/yaml/
source "$SCRIPT_DIR/utils.sh"  # demo/scripts/utils.sh
```

---

## 🎯 **PREVENTION CHECKLIST FOR USERS**

### **Before Starting Demo:**
```bash
# 1. Clean KUBECONFIG conflicts
unset KUBECONFIG
echo $KUBECONFIG  # Should be empty

# 2. Verify system resources
free -h  # Need 8GB+ RAM
nproc    # Need 6+ cores

# 3. Clean previous attempts  
minikube delete --all --purge
docker system prune -f

# 4. Verify inotify limits
cat /proc/sys/fs/inotify/max_user_watches
# Should be >= 1048576
```

### **Use Enhanced Scripts:**
```bash
# All issues automatically prevented:
./demo/scripts/minikube_setup.sh           # ✅ Issue-aware cluster creation
echo "3" | ./demo/scripts/minikube_quick-install.sh  # ✅ Complete operator setup
./demo/scripts/deploy-ramendr-s3.sh        # ✅ Cross-cluster S3 setup  
```

---

## 🚀 **SCRIPT ENHANCEMENT SUMMARY**

| Script | Issues Fixed | Auto-Prevention |
|--------|--------------|-----------------|
| `minikube_setup.sh` | KUBECONFIG, inotify, sequential creation | ✅ |
| `minikube_quick-install.sh` | OCM CRDs, image copying, file paths | ✅ |  
| `deploy-ramendr-s3.sh` | Cross-cluster networking, dynamic endpoints | ✅ |
| `minikube_monitoring.sh` | Context updates, path corrections | ✅ |

---

## 📞 **WHEN THINGS STILL GO WRONG**

### **Diagnostic Commands:**
```bash
# 1. Check cluster health
minikube status -p ramen-hub
minikube status -p ramen-dr1  
minikube status -p ramen-dr2

# 2. Check operator status
kubectl get pods -n ramen-system --context=ramen-hub
kubectl get pods -n ramen-system --context=ramen-dr1
kubectl get pods -n ramen-system --context=ramen-dr2

# 3. Check S3 connectivity
curl http://$(minikube ip -p ramen-hub):30900/minio/health/live

# 4. Use monitoring script
./demo/monitoring/minikube_monitoring.sh
```

### **Nuclear Option (Clean Restart):**
```bash
# Complete cleanup and restart
minikube delete --all --purge
rm -rf ~/.minikube
docker system prune -af
unset KUBECONFIG

# Then restart with enhanced scripts
./demo/scripts/minikube_setup.sh
```

This guide represents **all learned knowledge** from extensive troubleshooting. Following these guidelines should result in **zero repeated issues**.
