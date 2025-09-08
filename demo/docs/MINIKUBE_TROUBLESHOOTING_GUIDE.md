# MINIKUBE RamenDR Troubleshooting Guide

## 🚨 **CRITICAL ISSUES & SOLUTIONS FROM DEMO EXPERIENCE**

This guide documents the major issues we encountered and solved during RamenDR minikube demo development.

## 🔧 **Environment Setup Issues**

### **Problem: KUBECONFIG Conflicts**

**Symptoms:**
- Minikube fails to start with "permission denied" errors
- Error: "failed to start node: Failed kubeconfig update"
- Error: "mkdir /etc/rancher: permission denied"

**Root Cause:** 
Existing `KUBECONFIG` environment variable pointing to other K8s installations (k3s, etc.) conflicts with minikube.

### **✅ Solution: Clean Environment Setup**

```bash
# CRITICAL: Always unset KUBECONFIG before minikube demo
unset KUBECONFIG

# Verify it's unset
echo $KUBECONFIG  # Should be empty

# Then proceed with minikube commands
minikube start -p ramen-hub --driver=docker
```

**⚠️ Add to your demo checklist**: Always run `unset KUBECONFIG` first!

### **Problem: Hub Operator CrashLoopBackOff**

**Symptoms:**
- Hub operator pod shows `CrashLoopBackOff` status
- Logs show errors like `"timed out waiting for cache to be synced for Kind *v1.ManagedCluster"`
- Missing OCM (Open Cluster Management) CRDs

**Root Cause:** 
The RamenDR hub operator expects certain OCM CRDs to be present, even in lightweight Kubernetes environments like minikube.

### **✅ Solution: Automatic OCM CRD Installation**

✅ **Fixed in v2.0+**: The installation script now automatically installs the required OCM CRDs:
- `ManagedCluster`
- `PlacementRule` 
- `Placement`
- `ManagedClusterView`
- `ManifestWork`

**Manual Fix (if needed):**
```bash
# Switch to hub cluster
kubectl config use-context ramen-hub

# Restart hub operator after CRDs are installed
kubectl rollout restart deployment ramen-hub-operator -n ramen-system

# Verify operator is running
kubectl get pods -n ramen-system
```

## 🌐 **Cross-Cluster Connectivity Issues**

### **Problem: Minikube Cluster Isolation**

**Symptoms:**
- Empty S3 buckets (no backups created)
- VRG status shows "Unknown" instead of "primary"
- Cross-cluster replication fails
- S3 connection errors in operator logs

**Root Cause:** 
Minikube clusters are isolated by default - they cannot communicate with each other or access services across clusters.

### **✅ Solution 1: Host Network MinIO (Recommended)**

✅ **Fixed in v2.0+**: The MinIO deployment now automatically uses host network + NodePort for cross-cluster access.

**Automatic Configuration:**
- **Host Network**: `hostNetwork: true` breaks out of minikube isolation
- **NodePort Service**: Exposes MinIO on host network (30900=API, 30901=Console)
- **Dynamic S3 Endpoint**: Script automatically detects hub cluster IP and configures S3 endpoint

**Technical Details:**
Deploy MinIO on host network to break out of minikube isolation:

```bash
# Deploy MinIO with host network access
kubectl --context ramen-hub apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: minio-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      hostNetwork: true  # 🔑 KEY: Breaks out of minikube isolation
      containers:
      - name: minio
        image: minio/minio:latest
        command:
        - /bin/bash
        - -c
        args:
        - minio server /data --console-address :9001
        ports:
        - containerPort: 9000
          hostPort: 9000  # Bind to host port
        - containerPort: 9001
          hostPort: 9001
        env:
        - name: MINIO_ROOT_USER
          value: minioadmin
        - name: MINIO_ROOT_PASSWORD
          value: minioadmin
        volumeMounts:
        - name: storage
          mountPath: /data
      volumes:
      - name: storage
        emptyDir: {}
EOF
```

### **✅ Solution 2: Get Host IP for S3 Endpoint**

```bash
# Get your host IP (NOT cluster IP)
HOST_IP=$(ip route get 8.8.8.8 | awk '{print $7}' | head -1)
echo "🎯 Use this S3 endpoint: http://$HOST_IP:9000"

# Test accessibility from all clusters
for cluster in ramen-hub ramen-dr1 ramen-dr2; do
  echo "Testing $cluster connectivity to MinIO..."
  kubectl --context $cluster exec -n ramen-system deployment/ramen-dr-cluster-operator -- \
    curl -s http://$HOST_IP:9000/minio/health/live && echo " ✅" || echo " ❌"
done
```

## 📦 **S3 Configuration Issues**

### **Problem: Wrong Field Names & Structure**

**Symptoms:**
- Operator logs: "s3 endpoint has not been configured in s3 profile"
- JSON unmarshaling errors
- S3 profile not found errors

### **🔍 Critical Field Name Discovery**

**❌ WRONG:** `s3Endpoint`  
**✅ CORRECT:** `s3CompatibleEndpoint`

Found in [`api/v1alpha1/ramenconfig_types.go:61`](../../api/v1alpha1/ramenconfig_types.go)

### **✅ Correct S3 Configuration Structure**

```yaml
# CORRECT RamenConfig ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: ramen-dr-cluster-config
  namespace: ramen-system
data:
  ramen_manager_config.yaml: |
    apiVersion: ramendr.openshift.io/v1alpha1
    kind: RamenConfig
    metadata:
      name: ramen-config
      namespace: ramen-system
    # 🔑 CRITICAL: Must be ARRAY format, not object
    s3StoreProfiles:
    - s3ProfileName: minio-s3
      s3Bucket: ramen-metadata
      # 🔑 FIELD NAME MUST BE EXACT:
      s3CompatibleEndpoint: "http://HOST_IP:9000"  # NOT s3Endpoint!
      s3Region: us-east-1
      s3SecretRef:
        name: ramen-s3-secret
        namespace: ramen-system
```

### **✅ Required S3 Secret**

```bash
# MUST create on ALL DR clusters (not just hub)
for cluster in ramen-dr1 ramen-dr2; do
  kubectl --context $cluster create secret generic ramen-s3-secret \
    --namespace ramen-system \
    --from-literal=AWS_ACCESS_KEY_ID=minioadmin \
    --from-literal=AWS_SECRET_ACCESS_KEY=minioadmin
  echo "✅ Created ramen-s3-secret on $cluster"
done
```

## 🔧 **Complete Troubleshooting Checklist**

### **S3 Configuration Validation:**
```bash
# 1. Check if configmap exists on DR clusters
kubectl --context ramen-dr1 get configmap ramen-dr-cluster-config -n ramen-system
kubectl --context ramen-dr2 get configmap ramen-dr-cluster-config -n ramen-system

# 2. Check if secret exists on DR clusters  
kubectl --context ramen-dr1 get secret ramen-s3-secret -n ramen-system
kubectl --context ramen-dr2 get secret ramen-s3-secret -n ramen-system

# 3. Verify field names in configmap
kubectl --context ramen-dr1 get configmap ramen-dr-cluster-config -n ramen-system -o yaml | grep -E "(s3CompatibleEndpoint|s3StoreProfiles)"

# 4. Test S3 connectivity from DR clusters
for cluster in ramen-dr1 ramen-dr2; do
  kubectl --context $cluster exec -n ramen-system deployment/ramen-dr-cluster-operator -- \
    curl -v http://HOST_IP:9000/minio/health/live
done
```

### **VRG Status Validation:**
```bash
# Check VRG state (should be "primary", not "Unknown")
kubectl --context ramen-dr1 get vrg -o jsonpath='{.items[0].status.state}'

# Check VRG details
kubectl --context ramen-dr1 describe vrg

# Check if backups are actually happening
mc ls minio-s3/ramen-metadata  # Should show backup files
```

### **Operator Log Analysis:**
```bash
# Check for S3 errors
kubectl --context ramen-dr1 logs -n ramen-system deployment/ramen-dr-cluster-operator | grep -i "s3\|endpoint\|profile"

# Check for connectivity errors
kubectl --context ramen-dr1 logs -n ramen-system deployment/ramen-dr-cluster-operator | grep -i "connection\|failed\|error"
```

## 📋 **Quick Fix Commands**

### **Fix S3 Endpoint Configuration:**
```bash
# Get your host IP
HOST_IP=$(ip route get 8.8.8.8 | awk '{print $7}' | head -1)

# Update configmap on all DR clusters
for cluster in ramen-dr1 ramen-dr2; do
  kubectl --context $cluster patch configmap ramen-dr-cluster-config -n ramen-system --patch "
data:
  ramen_manager_config.yaml: |
    apiVersion: ramendr.openshift.io/v1alpha1
    kind: RamenConfig
    metadata:
      name: ramen-config
      namespace: ramen-system
    s3StoreProfiles:
    - s3ProfileName: minio-s3
      s3Bucket: ramen-metadata
      s3CompatibleEndpoint: \"http://$HOST_IP:9000\"
      s3Region: us-east-1
      s3SecretRef:
        name: ramen-s3-secret
        namespace: ramen-system"
done
```

### **Restart Operators After Config Changes:**
```bash
# Restart DR cluster operators to pick up new config
kubectl --context ramen-dr1 rollout restart deployment/ramen-dr-cluster-operator -n ramen-system
kubectl --context ramen-dr2 rollout restart deployment/ramen-dr-cluster-operator -n ramen-system

# Wait for rollout
kubectl --context ramen-dr1 rollout status deployment/ramen-dr-cluster-operator -n ramen-system
```

## ⚠️ **Common Mistakes to Avoid**

1. **❌ Wrong Field Name**
   - Using `s3Endpoint` instead of `s3CompatibleEndpoint`
   - **Fix:** Always use `s3CompatibleEndpoint`

2. **❌ Wrong Structure**
   - Using object format `s3StoreProfiles: {}` 
   - **Fix:** Use array format `s3StoreProfiles: []`

3. **❌ Missing Resources on DR Clusters**
   - Only creating configmap/secret on hub
   - **Fix:** Create on ALL DR clusters

4. **❌ Using Cluster IPs**
   - Using minikube internal IPs like `192.168.49.2`
   - **Fix:** Use host IP accessible from all clusters

5. **❌ Not Testing Connectivity**
   - Assuming configuration works without validation
   - **Fix:** Always test S3 connectivity from DR clusters

## 🎯 **Success Indicators**

When everything is working correctly:

```bash
# VRG shows "primary" state
kubectl get vrg -o jsonpath='{.items[0].status.state}'
# Output: primary

# S3 bucket contains backup data
mc ls minio-s3/ramen-metadata
# Output: Shows backup files with timestamps

# Operator logs show successful S3 operations
kubectl logs -n ramen-system deployment/ramen-dr-cluster-operator | grep -i "backup.*successful"
# Output: Shows successful backup messages

# No S3 errors in operator logs
kubectl logs -n ramen-system deployment/ramen-dr-cluster-operator | grep -i "s3.*error"
# Output: No error messages
```

---

💡 **This guide captures all the major issues that blocked our demo and provides tested solutions!**
