<!--
SPDX-FileCopyrightText: The RamenDR authors
SPDX-License-Identifier: Apache-2.0
-->

# 🎬 RamenDR Demo Flow Guide

## 📋 **Pre-Demo Preparation**

### **Environment Setup (5-10 minutes before demo)**
```bash
# 1. Clean slate (if needed)
./scripts/cleanup-all.sh

# 2. Verify prerequisites
docker --version
kind version  
kubectl version --client
```

### **Demo Environment**
- **Audience**: Developers, DevOps engineers, Platform teams
- **Duration**: 15-20 minutes
- **Goal**: Show end-to-end RamenDR disaster recovery automation

---

## 🎯 **Demo Flow Script**

### **Phase 1: Introduction & Problem Statement** (2 minutes)

**🗣️ Talking Points:**
> "Today I'll show you RamenDR - Kubernetes-native disaster recovery that protects your applications and data across multiple clusters. We'll see how RamenDR automatically backs up application metadata to S3 and coordinates disaster recovery workflows."

**📊 Show Architecture Diagram:**
```bash
# Open architecture guide
cat examples/RAMENDR_ARCHITECTURE_GUIDE.md | head -30
```

**🎯 Key Messages:**
- **Problem**: Applications need DR protection across Kubernetes clusters
- **Solution**: RamenDR provides automated backup and failover
- **Demo**: Complete automation from cluster creation to DR testing

---

### **Phase 2: Automated Environment Setup** (3-4 minutes)

**🗣️ Talking Points:**
> "Let's start with a completely clean environment and set up everything automatically. Our automation will create 3 kind clusters, install RamenDR operators, and configure S3 storage."

#### **Step 1: Launch Complete Setup**
```bash
# One command does everything!
./scripts/fresh-demo.sh
```

**🎙️ While Running - Explain What's Happening:**
- **Cluster Creation**: 3 kind clusters (hub + 2 DR sites)
- **Operator Installation**: RamenDR hub and DR cluster operators
- **Storage Setup**: MinIO S3-compatible storage
- **Validation**: Each step includes verification

#### **Step 2: Monitor Progress**
```bash
# In another terminal - show real-time cluster status
watch -n 2 'echo "=== CLUSTERS ===" && kind get clusters && echo "=== CONTEXTS ===" && kubectl config get-contexts'
```

**🎯 Key Messages:**
- **Automation**: Zero manual configuration required
- **Validation**: Built-in health checks at each step
- **Production-Ready**: Same process works with real clusters

---

### **Phase 3: Environment Validation** (2 minutes)

**🗣️ Talking Points:**
> "Let's verify our complete RamenDR environment is ready. We'll check clusters, operators, and S3 storage."

#### **Step 1: Cluster Status**
```bash
# Show all clusters are running
kind get clusters
echo ""

# Show cluster details
for cluster in ramen-hub ramen-dr1 ramen-dr2; do
    echo "=== $cluster ==="
    docker exec -it ${cluster}-control-plane kubectl get nodes
done
```

#### **Step 2: RamenDR Operators**
```bash
# Check operators across all clusters
for context in kind-ramen-hub kind-ramen-dr1 kind-ramen-dr2; do
    echo "=== $context ==="
    kubectl config use-context $context
    kubectl get pods -n ramen-system
    echo ""
done
```

#### **Step 3: Storage & CRDs**
```bash
# Switch to hub cluster
kubectl config use-context kind-ramen-hub

# Show MinIO S3 storage
kubectl get pods -n minio-system

# Show RamenDR CRDs
kubectl get crd | grep ramen

# Show S3 configuration
kubectl get configmap -n ramen-system | grep ramen
```

**🎯 Key Messages:**
- **Multi-Cluster**: 3 clusters with different roles
- **Operators**: Hub orchestrates, DR clusters execute
- **Storage**: S3 for metadata backup and recovery

---

### **Phase 4: Application Protection Demo** (5-6 minutes)

**🗣️ Talking Points:**
> "Now let's see RamenDR in action. We'll deploy a test application and show how RamenDR automatically protects it by backing up metadata to S3."

#### **Step 1: Deploy Test Application**
```bash
# Deploy nginx application with persistent storage
kubectl apply -f examples/test-application/nginx-with-pvc.yaml

# Show what was created
kubectl get all,pvc -n nginx-test
```

#### **Step 2: Create VolumeReplicationGroup**
```bash
# Apply VRG to protect the application
kubectl apply -f examples/test-application/nginx-vrg-correct.yaml

# Watch VRG creation and status
kubectl get vrg -n nginx-test -w
```

**🎙️ While VRG Initializes - Explain:**
- **VRG**: Core RamenDR resource that protects PVCs
- **Label Selector**: Automatically discovers matching PVCs
- **S3 Backup**: Stores Kubernetes metadata for recovery

#### **Step 3: Show VRG Status**
```bash
# Detailed VRG status
kubectl describe vrg nginx-test-vrg -n nginx-test

# Show protected PVCs
kubectl get pvc -n nginx-test --show-labels

# Show generated backup resources
kubectl get volumereplication -n nginx-test 2>/dev/null || echo "VolumeReplication resources creating..."
```

---

### **Phase 5: S3 Backup Verification** (3-4 minutes)

**🗣️ Talking Points:**
> "Let's verify that RamenDR is backing up our application metadata to S3 storage. This metadata enables recovery on any cluster."

#### **Step 1: Access MinIO Console**
```bash
# Start MinIO console access
./examples/access-minio-console.sh
```

**🌐 Browser Demo:**
- Open http://localhost:9001
- Login: `minioadmin` / `minioadmin`
- Navigate to `ramen-metadata` bucket
- Show backup files and structure

#### **Step 2: Command-Line S3 Verification**
```bash
# Check S3 contents via CLI
./examples/monitoring/check-minio-backups.sh

# Show bucket contents
kubectl port-forward -n minio-system service/minio 9000:9000 &
sleep 3
mc ls minio/ramen-metadata/ --recursive 2>/dev/null || echo "Bucket initializing..."
pkill -f "port-forward.*minio" || true
```

#### **Step 3: RamenDR Status Overview**
```bash
# Comprehensive status check
./examples/monitoring/check-ramendr-status.sh
```

**🎯 Key Messages:**
- **Metadata Backup**: Application configs stored in S3
- **Cross-Cluster Recovery**: Metadata enables restoration anywhere
- **Monitoring**: Built-in tools for verification

---

### **Phase 6: DR Capabilities Demonstration** (2-3 minutes)

**🗣️ Talking Points:**
> "In a real DR scenario, RamenDR would orchestrate failover between clusters. Let's see the components that make this possible."

#### **Step 1: Show DRPolicy Configuration**
```bash
# Show DR policy that defines replication between clusters
kubectl apply -f examples/dr-policy/drclusters.yaml
kubectl apply -f examples/dr-policy/drpolicy.yaml

# Display the policy
kubectl get drpolicy,drcluster -o wide
```

#### **Step 2: Simulate DR Scenario**
```bash
# Switch to DR cluster to show where recovery would happen
kubectl config use-context kind-ramen-dr1

# Show this cluster is ready to receive applications
kubectl get nodes
kubectl get storageclass
```

#### **Step 3: Show OCM Integration Points**
```bash
# Back to hub - show placement concepts
kubectl config use-context kind-ramen-hub

# Show how DRPlacementControl would work (demo resource)
cat examples/test-application/nginx-drpc.yaml
```

**🎯 Key Messages:**
- **Policy-Driven**: DRPolicy defines replication rules
- **Multi-Cluster**: Any cluster can become primary or secondary
- **OCM Integration**: Leverages Open Cluster Management for orchestration

---

### **Phase 7: Monitoring & Operations** (2 minutes)

**🗣️ Talking Points:**
> "RamenDR includes comprehensive monitoring and operational tools for production environments."

#### **Step 1: Built-in Monitoring**
```bash
# Show all monitoring scripts
ls -la examples/monitoring/

# Run comprehensive status check
./examples/monitoring/check-ramendr-status.sh

# Show operator logs
kubectl logs -n ramen-system -l app.kubernetes.io/name=ramen --tail=10
```

#### **Step 2: Operational Commands**
```bash
# Show VRG events and status
kubectl get events -n nginx-test --sort-by='.lastTimestamp'

# Show backup verification
./examples/verify-ramendr-backups.sh 2>/dev/null || echo "Backup verification available"
```

**🎯 Key Messages:**
- **Observability**: Rich logging and event tracking
- **Automation**: Scripts for common operational tasks
- **Production Ready**: Comprehensive monitoring included

---

### **Phase 8: Demo Cleanup** (1 minute)

**🗣️ Talking Points:**
> "Our automation also includes safe cleanup with verification to return to a clean state."

```bash
# Safe cleanup with validation
./scripts/cleanup-all.sh
```

**🎙️ While Cleaning Up:**
- **Validation**: Cleanup verifies what was removed
- **Safe**: Asks for confirmation before destructive actions
- **Complete**: Removes clusters, containers, and resources

---

## 🎯 **Key Demo Takeaways**

### **For Developers:**
- ✅ **Zero Configuration**: One command sets up complete DR environment
- ✅ **Kubernetes Native**: Uses familiar K8s resources and patterns
- ✅ **Storage Agnostic**: Works with any CSI-compatible storage

### **For DevOps/SRE:**
- ✅ **Production Ready**: Comprehensive validation and monitoring
- ✅ **Multi-Cloud**: Supports any Kubernetes distribution
- ✅ **Automated Operations**: Rich scripting and operational tools

### **For Platform Teams:**
- ✅ **Policy Driven**: Centralized DR policies and governance
- ✅ **OCM Integration**: Leverages existing cluster management
- ✅ **S3 Compatible**: Works with AWS, MinIO, or other S3 stores

---

## 📚 **Follow-up Resources**

**For Technical Deep-Dive:**
- [`RAMENDR_ARCHITECTURE_GUIDE.md`](RAMENDR_ARCHITECTURE_GUIDE.md) - Complete architecture overview
- [`../internal/controller/`](../internal/controller/) - Source code walkthrough
- [`../api/v1alpha1/`](../api/v1alpha1/) - CRD definitions

**For Hands-On Practice:**
- [`AUTOMATED_DEMO_QUICKSTART.md`](AUTOMATED_DEMO_QUICKSTART.md) - Quick setup guide
- [`COMPLETE_AUTOMATED_SETUP.md`](COMPLETE_AUTOMATED_SETUP.md) - Detailed setup instructions
- [`../scripts/`](../scripts/) - All automation scripts

---

## ⚡ **Demo Tips & Tricks**

### **Preparation:**
- Run through the demo once beforehand
- Have backup terminals ready for monitoring
- Bookmark MinIO console URL: http://localhost:9001

### **Timing:**
- Allow 3-5 minutes for fresh-demo.sh to complete
- Have monitoring commands ready in separate terminals
- Prepare for questions about production deployment

### **Common Questions:**
1. **"How does this work with real storage?"** → Show CSI integration in architecture guide
2. **"What about network policies?"** → Mention OCM integration for secure cluster communication
3. **"Can this work with OpenShift?"** → Yes, RamenDR originated as OpenShift DR solution

### **Technical Variations:**
- **Short Demo (10 min)**: Skip detailed monitoring, focus on automation
- **Technical Deep-Dive (30 min)**: Include architecture explanation and code walkthrough
- **Workshop Format (60 min)**: Let audience run commands themselves

---

**🎬 This demo showcases RamenDR as a production-ready, cloud-native disaster recovery solution with comprehensive automation! 🚀**
