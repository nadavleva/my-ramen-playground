# 🎯 RamenDR Demo with minikube

This guide shows how to run the complete RamenDR demo using **minikube** instead of kind clusters.

## ✅ **Prerequisites**

### **Required Tools:**
```bash
# Install minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl

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

### **🚨 CRITICAL: Environment Setup**
```bash
# MUST unset KUBECONFIG before starting minikube demo
unset KUBECONFIG

# Verify it's unset
echo $KUBECONFIG  # Should be empty
```

**⚠️ Why this matters**: If `KUBECONFIG` points to other Kubernetes installations (like k3s), minikube will fail to start with permission errors.

## 🚀 **Quick Start**

### **Option 1: Automated Setup (Recommended)**
```bash
# Complete automated demo with minikube
./scripts/fresh-demo-minikube.sh
```

### **Option 2: Manual Step-by-Step Setup**
```bash
# 1. Setup minikube clusters
./demo/scripts/minikube_setup.sh

# 2. Install RamenDR operators
echo "3" | ./demo/scripts/minikube_quick-install.sh

# 3. Deploy S3 storage
./demo/scripts/deploy-ramendr-s3.sh

# 4. Setup cross-cluster access
./scripts/setup-cross-cluster-s3.sh

# 5. Run failover demo
./demo/scripts/minikube_demo-failover.sh
```

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

## 📚 **Next Steps**

After completing the minikube demo:

1. 📖 **Read Architecture Guide**: `./examples/RAMENDR_ARCHITECTURE_GUIDE.md`
2. 🔍 **Explore CRDs**: `kubectl get crd | grep ramendr`
3. 📊 **Monitor Components**: `kubectl get pods -n ramen-system -A`
4. 🧪 **Test with Real Apps**: Deploy your own applications with VRGs
5. 🔄 **Practice DR Workflows**: Test different failure scenarios

Happy disaster recovery testing with minikube! 🚀
