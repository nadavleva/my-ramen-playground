# 🚀 **Complete RamenDR Automated Setup & Demo**

## ❌ **Current Demo Scripts DO NOT Install kind Clusters**

The `examples/` demo scripts assume clusters already exist. For complete automation, you need to run **3 separate phases**:

## 🏗️ **Phase 1: Install kind Clusters**
**Location:** `../scripts/` directory

### **Option A: Automated Setup (Recommended)**
```bash
cd scripts/
./setup.sh kind
```

**What this does:**
- ✅ Installs Docker (if needed)
- ✅ Installs kind binary
- ✅ Creates 3 kind clusters: ramen-hub, ramen-dr1, ramen-dr2
- ✅ Verifies cluster health

### **Option B: Manual Setup**
```bash
cd scripts/
./setup-linux.sh          # Install prerequisites
./setup-kind-enhanced.sh   # Create kind clusters only
```

## 🤖 **Phase 2: Install RamenDR Operators**
**Location:** `../scripts/` directory

```bash
cd scripts/
./quick-install.sh
```

**What this does:**
- ✅ Builds RamenDR operator image
- ✅ Loads image into all kind clusters
- ✅ Installs hub operator on ramen-hub
- ✅ Installs DR cluster operators on ramen-dr1 & ramen-dr2
- ✅ Installs storage dependencies (VolSync, VolumeReplication CRDs)

## 🎭 **Phase 3: Run RamenDR Demo**
**Location:** `examples/` directory

```bash
cd examples/
./ramendr-demo.sh demo
```

**What this does:**
- ✅ Deploys MinIO S3 storage
- ✅ Creates test application with PVC
- ✅ Sets up VolumeReplicationGroup
- ✅ Demonstrates RamenDR functionality
- ✅ Shows S3 integration and monitoring

## 🎯 **Complete End-to-End Automation**

### **From Scratch (One Command Each):**
```bash
# 1. Install everything
cd scripts/
./setup.sh kind

# 2. Install RamenDR
./quick-install.sh

# 3. Run demo  
cd ../examples/
./ramendr-demo.sh demo
```

### **Verify Installation:**
```bash
# Check clusters
kind get clusters
# Should show: ramen-dr1, ramen-dr2, ramen-hub

# Check operators
kubectl config use-context kind-ramen-hub
kubectl get pods -n ramen-system

kubectl config use-context kind-ramen-dr1  
kubectl get pods -n ramen-system

kubectl config use-context kind-ramen-dr2
kubectl get pods -n ramen-system
```

## 📋 **Prerequisites Check**

### **Before Starting:**
```bash
# Check Docker
docker version

# Check kubectl  
kubectl version --client

# Check if kind is installed
kind version
```

### **If Missing Prerequisites:**
```bash
cd scripts/
./setup-linux.sh    # Installs Docker, kubectl, kind, helm
```

## 🔧 **Troubleshooting Common Issues**

### **Docker Permission Issues:**
```bash
sudo usermod -aG docker $USER
newgrp docker
# Then restart setup
```

### **kind Clusters Not Starting:**
```bash
# Clean up and retry
kind delete clusters --all
./setup.sh kind
```

### **RamenDR Operators Failing:**
```bash
# Check logs
kubectl logs deployment/ramen-hub-operator -n ramen-system
kubectl logs deployment/ramen-dr-cluster-operator -n ramen-system
```

## 🎪 **Demo Showcase Workflow**

### **For Live Presentations:**
```bash
# 1. Quick status check
cd examples/
./monitoring/check-ramendr-status.sh

# 2. Run automated demo
./ramendr-demo.sh demo

# 3. Access web console
./access-minio-console.sh
# Open: http://localhost:9001 (minioadmin/minioadmin)

# 4. Show S3 integration  
./s3-config/check-minio-backups.sh

# 5. Clean up
./ramendr-demo.sh cleanup
```

## 🕐 **Time Estimates**

| Phase | Time | Description |
|-------|------|-------------|
| **Phase 1** | 5-10 min | kind cluster installation |
| **Phase 2** | 10-15 min | RamenDR operator installation |
| **Phase 3** | 2-3 min | Demo execution |
| **Total** | **20-30 min** | Complete setup + demo |

## 📁 **File Structure Overview**

```
ramen/
├── scripts/                    # Infrastructure setup
│   ├── setup.sh               # Main setup script
│   ├── quick-install.sh       # RamenDR operator installer
│   └── setup-*.sh            # Platform-specific setup
└── examples/                   # Demo and showcase
    ├── ramendr-demo.sh        # Main demo script
    ├── monitoring/            # Status check scripts
    ├── s3-config/            # S3 setup and verification
    └── README.md             # Demo documentation
```

## 🏆 **What You Get**

### **Complete RamenDR Environment:**
- ✅ **3 kind clusters** with Docker networking
- ✅ **RamenDR operators** on hub + DR clusters
- ✅ **MinIO S3 storage** for metadata
- ✅ **Test applications** with PVC protection
- ✅ **Monitoring tools** for status verification
- ✅ **Web console access** for S3 bucket browsing

### **Ready for:**
- 🧪 **Development and testing**
- 📚 **Learning RamenDR concepts**
- 🎭 **Live demonstrations**
- 🔧 **Configuration validation**
- 📊 **Policy testing and verification**

## 🚨 **Important Notes**

1. **Storage Replication:** Demo shows orchestration only, no actual data replication (kind limitation)
2. **Network Requirements:** All clusters run locally on Docker
3. **Resource Usage:** ~4-6GB RAM for all clusters
4. **Cleanup:** Use `kind delete clusters --all` to remove everything

**For complete automated setup, you need both `scripts/` AND `examples/` directories!** 🎯
