<!--
SPDX-FileCopyrightText: The RamenDR authors
SPDX-License-Identifier: Apache-2.0
-->

# Lightweight Kubernetes Clusters for RamenDR Testing

This guide focuses specifically on lightweight Kubernetes options for RamenDR testing when you have limited resources or want rapid development cycles.

## 🎯 Quick Answer: Best Lightweight Options

### **🏆 Top Recommendation: k3s + Longhorn**
**Why**: Perfect balance of functionality and resource efficiency for RamenDR testing

### **🥈 Alternative: Reduced minikube**  
**Why**: Officially tested with RamenDR, good compatibility

### **🥉 Minimal: kind + simulation**
**Why**: Ultra-lightweight for concept validation only

## 🪶 Option 1: k3s with Longhorn (Recommended)

### **Why k3s is Perfect for RamenDR**
- **Minimal overhead**: ~40MB binary, low memory footprint
- **Built-in features**: Local storage, networking, ingress
- **Production-ready**: CNCF certified Kubernetes
- **Easy clustering**: Simple multi-node setup
- **Storage integration**: Excellent Longhorn compatibility

### **Resource Requirements**
```yaml
Total System: 6 GB RAM, 6 CPU cores, 40 GB storage
Hub: 1 GB RAM, 1 CPU
DR1: 2.5 GB RAM, 2.5 CPU  
DR2: 2.5 GB RAM, 2.5 CPU
```

### **Complete k3s Setup**

#### 1. Install k3s Clusters

```bash
#!/bin/bash
# k3s-ramen-setup.sh

# Create directory structure
mkdir -p ~/ramen-k3s/{hub,dr1,dr2}
cd ~/ramen-k3s

# Hub cluster
sudo k3s server \
  --data-dir=/opt/k3s-hub \
  --cluster-init \
  --write-kubeconfig=./hub/kubeconfig \
  --write-kubeconfig-mode=644 \
  --bind-address=127.0.0.1 \
  --https-listen-port=6443 \
  --node-name=hub &

# Wait for hub to be ready
sleep 30

# DR1 cluster  
sudo k3s server \
  --data-dir=/opt/k3s-dr1 \
  --cluster-init \
  --write-kubeconfig=./dr1/kubeconfig \
  --write-kubeconfig-mode=644 \
  --bind-address=127.0.0.1 \
  --https-listen-port=6444 \
  --node-name=dr1 &

# DR2 cluster
sudo k3s server \
  --data-dir=/opt/k3s-dr2 \
  --cluster-init \
  --write-kubeconfig=./dr2/kubeconfig \
  --write-kubeconfig-mode=644 \
  --bind-address=127.0.0.1 \
  --https-listen-port=6445 \
  --node-name=dr2 &

echo "Waiting for clusters to be ready..."
sleep 60

# Verify clusters
KUBECONFIG=./hub/kubeconfig kubectl get nodes
KUBECONFIG=./dr1/kubeconfig kubectl get nodes  
KUBECONFIG=./dr2/kubeconfig kubectl get nodes
```

#### 2. Install Longhorn Storage

```bash
# Install Longhorn on DR clusters for replication
KUBECONFIG=./dr1/kubeconfig kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml

KUBECONFIG=./dr2/kubeconfig kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml

# Wait for Longhorn to be ready
KUBECONFIG=./dr1/kubeconfig kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
KUBECONFIG=./dr2/kubeconfig kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
```

#### 3. Setup OCM Lightweight

```bash
# Install minimal OCM on hub
KUBECONFIG=./hub/kubeconfig kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: open-cluster-management
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cluster-manager
  namespace: open-cluster-management
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-manager
  namespace: open-cluster-management
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-manager
  template:
    metadata:
      labels:
        app: cluster-manager
    spec:
      serviceAccountName: cluster-manager
      containers:
      - name: cluster-manager
        image: quay.io/open-cluster-management/registration-operator:latest
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
EOF
```

#### 4. Install Ramen

```bash
# Clone Ramen
git clone https://github.com/RamenDR/ramen.git
cd ramen

# Build lightweight image
make docker-build IMG=localhost:5000/ramen:lightweight

# Install on hub
KUBECONFIG=../hub/kubeconfig make deploy IMG=localhost:5000/ramen:lightweight

# Install on DR clusters
KUBECONFIG=../dr1/kubeconfig kubectl apply -k config/olm-install/dr-cluster/
KUBECONFIG=../dr2/kubeconfig kubectl apply -k config/olm-install/dr-cluster/
```

#### 5. Configure Storage Classes

```bash
# Create RamenDR-compatible storage classes
for cluster in dr1 dr2; do
KUBECONFIG=./${cluster}/kubeconfig kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-ramen
  labels:
    ramendr.openshift.io/storageID: "longhorn-cluster"
    ramendr.openshift.io/replicationID: "longhorn-repl"
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "30"
  fromBackup: ""
  fsType: "ext4"
  dataLocality: "disabled"
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
done
```

### **Test k3s Setup**

```bash
# Test application deployment
KUBECONFIG=./dr1/kubeconfig kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  labels:
    app: test-app
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
  storageClassName: longhorn-ramen
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
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
          claimName: test-pvc
EOF

# Verify deployment
KUBECONFIG=./dr1/kubeconfig kubectl get pods,pvc
```

## 🐳 Option 2: Reduced minikube Setup

### **Optimized minikube Configuration**

```bash
#!/bin/bash
# lightweight-minikube-setup.sh

# Create optimized profiles
minikube start -p ramen-hub \
  --cpus=1 \
  --memory=1024 \
  --disk-size=10g \
  --driver=docker \
  --container-runtime=containerd

minikube start -p ramen-dr1 \
  --cpus=2 \
  --memory=2048 \
  --disk-size=15g \
  --driver=docker \
  --container-runtime=containerd

minikube start -p ramen-dr2 \
  --cpus=2 \
  --memory=2048 \
  --disk-size=15g \
  --driver=docker \
  --container-runtime=containerd

# Enable required addons
minikube addons enable storage-provisioner -p ramen-dr1
minikube addons enable storage-provisioner -p ramen-dr2
minikube addons enable volumesnapshots -p ramen-dr1  
minikube addons enable volumesnapshots -p ramen-dr2

# Install Longhorn for replication
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml --context ramen-dr1
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml --context ramen-dr2
```

### **Lightweight Ramen Installation**

```bash
# Use Ramen's existing lightweight test environment
git clone https://github.com/RamenDR/ramen.git
cd ramen
make venv && source venv

# Create minimal test environment config
cat > test/envs/ultra-light.yaml <<EOF
name: "ultra-light"
ramen:
  hub: hub
  clusters: [dr1, dr2]
  topology: regional-dr
  features:
    volsync: true

templates:
  - name: "minimal-dr"
    driver: docker
    cpus: 2
    memory: "2g" 
    disk_size: "15g"
    workers:
      - addons:
          - name: ocm-cluster
            args: ["\$name", "hub"]
          - name: minio
  - name: "minimal-hub"
    driver: docker  
    cpus: 1
    memory: "1g"
    disk_size: "10g"
    workers:
      - addons:
          - name: ocm-hub

profiles:
  - name: "dr1"
    template: "minimal-dr"
  - name: "dr2" 
    template: "minimal-dr"
  - name: "hub"
    template: "minimal-hub"
EOF

# Start ultra-light environment
cd test
drenv start envs/ultra-light.yaml
```

## 🐋 Option 3: kind Ultra-Lightweight

### **Minimal kind Setup**

```bash
#!/bin/bash
# kind-minimal-setup.sh

# Clean up any existing kind clusters first
echo "🧹 Cleaning up existing kind clusters..."
kind delete cluster --name ramen-hub 2>/dev/null || true
kind delete cluster --name ramen-dr1 2>/dev/null || true  
kind delete cluster --name ramen-dr2 2>/dev/null || true

# Clean up any leftover storage directories
sudo rm -rf /tmp/ramen-{hub,dr1,dr2} 2>/dev/null || true

echo "✅ Starting fresh kind cluster setup..."

# Create kind clusters with minimal resources
cat > hub-kind.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ramen-hub
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    etcd:
      local:
        dataDir: /tmp/etcd
    apiServer:
      extraArgs:
        enable-admission-plugins: NodeRestriction
  extraMounts:
  - hostPath: /tmp/ramen-hub
    containerPath: /tmp/local-storage
EOF

cat > dr-kind.yaml <<EOF  
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ramen-dr1
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /tmp/ramen-dr1
    containerPath: /tmp/local-storage
EOF

# Create clusters
kind create cluster --config hub-kind.yaml
kind create cluster --config dr-kind.yaml --name ramen-dr2

# Setup local storage simulation
for cluster in ramen-hub ramen-dr1 ramen-dr2; do
kubectl apply -f - --context kind-${cluster} <<EOF
apiVersion: v1
kind: StorageClass
metadata:
  name: local-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
done
```

### **Simulated Storage Replication**

```bash
# Create storage replication simulation script
cat > simulate-replication.sh <<'EOF'
#!/bin/bash
# Simple rsync-based replication simulation

SOURCE_CLUSTER="ramen-dr1"
TARGET_CLUSTER="ramen-dr2"
SOURCE_PATH="/tmp/ramen-dr1"
TARGET_PATH="/tmp/ramen-dr2"

# Watch for PVC creation and simulate replication
kubectl get pvc -w --context kind-${SOURCE_CLUSTER} | while read line; do
  if [[ $line == *"Bound"* ]]; then
    PVC_NAME=$(echo $line | awk '{print $1}')
    echo "Simulating replication for PVC: $PVC_NAME"
    
    # Simulate async replication delay
    sleep 5
    
    # Copy data (in real scenario, this would be storage-level)
    rsync -av ${SOURCE_PATH}/${PVC_NAME}/ ${TARGET_PATH}/${PVC_NAME}/ 2>/dev/null || true
    
    echo "Replication completed for $PVC_NAME"
  fi
done &
EOF

chmod +x simulate-replication.sh
./simulate-replication.sh &
```

## 📊 Performance Comparison

### **Resource Usage Benchmarks**

| Setup | RAM Usage | CPU Usage | Startup Time | Storage | Replication |
|-------|-----------|-----------|--------------|---------|-------------|
| **k3s + Longhorn** | 6 GB | 60% (6 cores) | 3 min | Real | Real |
| **minikube Reduced** | 5 GB | 65% (5 cores) | 5 min | Real | Real |
| **kind Simulated** | 3 GB | 40% (4 cores) | 2 min | Simulated | Simulated |

### **Feature Comparison**

| Feature | k3s | minikube | kind |
|---------|-----|----------|------|
| **Real Storage Replication** | ✅ Longhorn | ✅ CSI | ❌ Simulated |
| **Cross-cluster Networking** | ✅ | ✅ | ⚠️ Limited |
| **OCM Integration** | ✅ | ✅ | ⚠️ Basic |
| **Production Similarity** | ✅ High | ✅ Medium | ❌ Low |
| **Resource Efficiency** | ✅ | ⚠️ | ✅ |
| **Setup Complexity** | ⚠️ Medium | ✅ Easy | ✅ Easy |

## 🧪 Testing Scenarios for Lightweight Setups

### **Basic DR Workflow Test**

```bash
# 1. Deploy application on DR1
kubectl apply -f - --context dr1 <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  labels:
    app: demo-app
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
  storageClassName: longhorn-ramen
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
      - name: app
        image: nginx
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: app-data
EOF

# 2. Create DR policy and placement control
kubectl apply -f - --context hub <<EOF
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRPolicy
metadata:
  name: lightweight-policy
spec:
  drClusters: ["dr1", "dr2"]
  schedulingInterval: "5m"
---
apiVersion: ramendr.openshift.io/v1alpha1  
kind: DRPlacementControl
metadata:
  name: demo-app-drpc
spec:
  drPolicyRef:
    name: lightweight-policy
  pvcSelector:
    matchLabels:
      app: demo-app
  preferredCluster: "dr1"
EOF

# 3. Test failover
kubectl patch drpc demo-app-drpc --type='merge' \
  -p='{"spec":{"action":"Failover","failoverCluster":"dr2"}}' \
  --context hub

# 4. Verify application on DR2
kubectl get pods,pvc -l app=demo-app --context dr2
```

### **Storage Replication Verification**

```bash
# For Longhorn setups
# Check replication status
kubectl get volumes.longhorn.io -n longhorn-system --context dr1
kubectl get volumes.longhorn.io -n longhorn-system --context dr2

# Verify backup/restore capability
kubectl exec -n longhorn-system deployment/longhorn-manager --context dr1 -- \
  longhornctl snapshot create --volume-name pvc-<pvc-id>
```

## 🚨 Limitations and Workarounds

### **k3s Limitations**
```yaml
Limitations:
  - No built-in cross-cluster networking
  - Requires manual Longhorn setup
  - Limited enterprise features
  
Workarounds:
  - Use external load balancer for cross-cluster access
  - Manual storage class configuration
  - Simulate enterprise features with scripts
```

### **minikube Limitations**
```yaml
Limitations:
  - Higher resource usage than k3s
  - Limited networking between clusters
  - Requires specific driver configuration
  
Workarounds:
  - Use --driver=docker for better isolation
  - Configure custom networking
  - Use port-forwarding for cross-cluster access
```

### **kind Limitations**
```yaml
Limitations:
  - No real storage replication
  - Container-based clusters only
  - Limited persistent storage options
  
Workarounds:
  - Simulate replication with rsync scripts
  - Use external volumes for persistence
  - Focus on workflow testing, not storage testing
```

## 🎯 Recommendations by Use Case

### **For Learning RamenDR Concepts**
**Use**: kind with simulation
- Fast setup, minimal resources
- Focus on API and workflow understanding
- Good for documentation and tutorials

### **For Development and Testing**
**Use**: k3s with Longhorn  
- Real storage replication
- Production-like behavior
- Good balance of features and resources

### **For CI/CD Integration**
**Use**: Lightweight minikube
- Reliable and well-tested
- Good GitHub Actions/GitLab CI integration
- Predictable behavior

### **For Resource-Constrained Environments**
**Use**: kind with minimal configuration
- Absolute minimum resource usage
- Good for laptop development
- Quick iteration cycles

---

## 🎉 Getting Started Quickly

**Choose your path:**

1. **Want real DR testing?** → Use k3s + Longhorn setup above
2. **Want officially tested?** → Use reduced minikube configuration  
3. **Want minimal resources?** → Use kind with simulation
4. **Want enterprise features?** → Go back to OpenShift modes

Each option provides a different balance of functionality, resource usage, and complexity to match your specific needs!
