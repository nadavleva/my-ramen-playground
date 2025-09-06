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
- **Duration**: 18-23 minutes
- **Goal**: Show end-to-end RamenDR disaster recovery automation

---

## 🎯 **Manual Step-by-Step Execution Guide**

For those who prefer to run commands manually or want to understand each step in detail:

### **Step 0: Environment Check**
```bash
# Check current state
docker --version
kind get clusters
kubectl config get-contexts
```

### **Step 1: Environment Cleanup**
```bash
# Clean any existing environment
./scripts/cleanup-all.sh
```
**Expected**: Cleanup confirmation prompt → type `y`

### **Step 2: Setup Kind Clusters**
```bash
# Create 3 kind clusters (hub, dr1, dr2)
./scripts/setup.sh kind
```
**Expected**: 3 kind clusters created (hub, dr1, dr2)

### **Step 3: Install RamenDR Operators + All CRDs + Resource Classes**
```bash
# Install operators on all clusters with all dependencies
./scripts/quick-install.sh
# When prompted, choose option 3: "All clusters (automated multi-cluster setup)"
```
**Expected**: 
- ✅ **RamenDR operators** (hub + both DR clusters automatically)
- ✅ **VolumeSnapshot CRDs** (VolumeSnapshot, VolumeSnapshotClass, VolumeSnapshotContent)
- ✅ **VolumeReplication CRDs** (VolumeReplication, VolumeReplicationClass)
- ✅ **Resource classes** (demo-snapclass, demo-replication-class)
- ✅ **VolSync** (storage replication)
- ✅ **External Snapshotter** (snapshot controller)
- ✅ **Stub CRDs** (NetworkFenceClass, VolumeGroupReplication)

### **Step 4: Deploy S3 Storage and DR Policies**
```bash
# Deploy MinIO and configure DR policies
./examples/deploy-ramendr-s3.sh
```
**Expected**: MinIO S3 deployed + DRPolicy + DRClusters created

### **Step 5: Setup Cross-Cluster S3 Networking**
```bash
# Configure cross-cluster S3 access (critical fix!)
./scripts/setup-cross-cluster-s3.sh
```
**Expected**: Cross-cluster S3 networking configured + endpoints updated

### **Step 6: Run Interactive Demo**
```bash
# Run the main demo with VRG creation
./examples/ramendr-demo.sh
```
**Expected**: nginx test app + VRGs created + S3 metadata backup verified

### **Optional: Monitoring & Verification**
```bash
# Check overall status
./examples/monitoring/check-ramendr-status.sh

# Check S3 bucket contents
./examples/s3-config/check-minio-backups.sh

# Interactive monitoring (run in separate terminal)
./examples/monitoring/demo-monitoring.sh
```

### **Alternative: One-Command Demo**
```bash
# If you want everything automated in one go:
./scripts/fresh-demo.sh
```

### **🎯 Success Indicators:**
- ✅ All 3 kind clusters running
- ✅ RamenDR operators: Hub (2/2), DR1 (2/2), DR2 (2/2) ready  
- ✅ S3 bucket `ramen-metadata` contains backup files
- ✅ VRGs showing `CURRENTSTATE: primary/secondary`
- ✅ Monitoring script reports "Volume replication is configured!"

### **🛠️ Troubleshooting Commands:**
```bash
# Fix kubectl contexts if needed
./scripts/fix-kubeconfig.sh

# Check operator logs
kubectl logs -n ramen-system deployment/ramen-hub-operator --context=kind-ramen-hub
kubectl logs -n ramen-system deployment/ramen-dr-cluster-operator --context=kind-ramen-dr1

# Verify S3 connectivity
kubectl port-forward -n minio-system service/minio 9000:9000 &
mc ls minio/ramen-metadata/ --recursive
pkill -f "port-forward.*minio"
```

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
- **Comprehensive Operator Installation**: RamenDR operators on ALL clusters + all CRDs
  - Hub operator on kind-ramen-hub cluster
  - DR cluster operators on BOTH kind-ramen-dr1 AND kind-ramen-dr2 clusters  
  - VolumeSnapshot CRDs (3 types) + External Snapshotter
  - VolumeReplication CRDs (2 types) + resource classes
  - VolSync storage replication engine
  - Stub CRDs for optional features (NetworkFenceClass, etc.)
- **Storage Setup**: MinIO S3-compatible storage with cross-cluster networking
- **Resource Classes**: VolumeSnapshotClass + VolumeReplicationClass for VRG selectors
- **Validation**: Each step includes comprehensive verification

#### **Step 2: Monitor Progress******

**🖥️ Terminal 2: Cluster & Resource Monitoring**
```bash
# Real-time cluster and resource status
watch -n 2 'echo "=== CLUSTERS ===" && kind get clusters && echo "" && echo "=== CONTEXTS ===" && kubectl config get-contexts | grep kind && echo "" && echo "=== RAMEN PODS ===" && kubectl get pods -A | grep ramen | head -5'
```

**🖥️ Terminal 3: Application & Storage Monitoring**
```bash
# Monitor RamenDR resources and applications
watch -n 3 'echo "=== DR RESOURCES (Hub) ===" && kubectl --context=kind-ramen-hub get drclusters,drpolicies -n ramen-system 2>/dev/null || echo "Not ready yet" && echo "" && echo "=== VRG & APPLICATIONS (DR1) ===" && kubectl --context=kind-ramen-dr1 get vrg,pods,pvc -A 2>/dev/null | head -8 || echo "Not ready yet"'
```

**🖥️ Terminal 4: KubeVirt Resources (Optional)**
```bash
# Monitor KubeVirt and virtualization resources (if using VMs)
watch -n 5 'echo "=== KUBEVIRT RESOURCES (DR1) ===" && kubectl --context=kind-ramen-dr1 get vm,vmi,pods,pvc,vrg,vr -n kubevirt-sample 2>/dev/null | head -10 || echo "No KubeVirt resources" && echo "" && echo "=== STORAGE CLASSES ===" && kubectl --context=kind-ramen-dr1 get storageclass 2>/dev/null'
```

**🎯 Key Messages:**
- **Automation**: Zero manual configuration required
- **Validation**: Built-in health checks at each step
- **Production-Ready**: Same process works with real clusters

---

### **Phase 3: RamenDR Installation & Validation** (5-6 minutes)

**🗣️ Talking Points:**
> "Now we'll install RamenDR operators on our clusters and validate the complete environment. This shows the multi-cluster coordination that makes disaster recovery possible."

#### **Step 1: Cluster Status**
```bash
# Show all clusters are running
kind get clusters
echo ""

# Verify cluster connectivity
for context in kind-ramen-hub kind-ramen-dr1 kind-ramen-dr2; do
    echo "=== $context ==="
    kubectl config use-context $context 2>/dev/null || { echo "❌ Context $context not found"; continue; }
    kubectl get nodes --no-headers 2>/dev/null && echo "✅ $context: Connected" || echo "❌ $context: Connection failed"
    echo ""
done
```

#### **Step 2: Install RamenDR Operators**
```bash
# Install RamenDR operators and dependencies
echo "🚀 Installing RamenDR operators..."
./scripts/quick-install.sh

# Note: This installs:
# - RamenDR CRDs
# - Hub operator (ramen-hub cluster)  
# - DR cluster operators (ramen-dr1, ramen-dr2)
# - VolSync dependencies
# - S3 storage configuration
```

#### **Step 3: Verify Operator Installation**
```bash
# Check operators across all clusters
echo "📊 Checking RamenDR operators..."
for context in kind-ramen-hub kind-ramen-dr1 kind-ramen-dr2; do
    echo "=== $context ==="
    kubectl config use-context $context 2>/dev/null || { echo "❌ Context failed"; continue; }
    
    # Check if ramen-system namespace exists
    if kubectl get namespace ramen-system >/dev/null 2>&1; then
        kubectl get pods -n ramen-system 2>/dev/null || echo "No pods in ramen-system yet"
    else
        echo "⏳ ramen-system namespace not created yet"
    fi
    echo ""
done
```

#### **Step 4: Storage & CRDs Validation**
```bash
# Switch to hub cluster for validation
kubectl config use-context kind-ramen-hub

# Show RamenDR CRDs are installed
echo "📋 RamenDR Custom Resource Definitions:"
kubectl get crd | grep ramen || echo "⏳ RamenDR CRDs still being created"

# Show MinIO S3 storage (if deployed)
echo ""
echo "💾 S3 Storage Status:"
kubectl get pods -n minio-system 2>/dev/null || echo "⏳ MinIO not deployed yet"

# Show VolSync installation
echo ""
echo "🔄 VolSync Status:"
kubectl get pods -n volsync-system 2>/dev/null || echo "⏳ VolSync not deployed yet"
```

**🎯 Key Messages:**
- **Multi-Cluster Architecture**: Hub orchestrates, DR clusters execute
- **Gradual Deployment**: Operators install progressively across clusters
- **Dependencies**: VolSync, S3 storage, and CRDs work together
- **Real-time Validation**: See components come online during demo

**🛠️ Troubleshooting:**
- If `kubectl config use-context` fails: Run `kind export kubeconfig --name <cluster>` to refresh contexts
- If you see `localhost:8080` errors: Check current context with `kubectl config current-context`
- If operators don't appear: Wait 2-3 minutes for installation to complete

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

#### **Step 2: Real-time Resource Monitoring**
```bash
# Comprehensive DR resource monitoring across all clusters
watch -n 3 'echo "=== HUB CLUSTER (kind-ramen-hub) ===" && kubectl --context=kind-ramen-hub get drclusters,drpolicies,pods -n ramen-system 2>/dev/null && echo "" && echo "=== DR1 CLUSTER (kind-ramen-dr1) ===" && kubectl --context=kind-ramen-dr1 get vrg,pods,pvc -A 2>/dev/null | head -6 && echo "" && echo "=== DR2 CLUSTER (kind-ramen-dr2) ===" && kubectl --context=kind-ramen-dr2 get vrg,pods,pvc -A 2>/dev/null | head -6'
```

#### **Step 3: KubeVirt & Storage Monitoring (Optional)**
```bash
# Monitor virtualization workloads and storage replication
watch -n 5 'echo "=== KUBEVIRT RESOURCES (DR1) ===" && kubectl --context=kind-ramen-dr1 get vm,vmi,pods,pvc,vrg,vr -n kubevirt-sample 2>/dev/null | head -10 || echo "No KubeVirt resources deployed" && echo "" && echo "=== STORAGE CLASSES ===" && kubectl --context=kind-ramen-dr1 get storageclass && echo "" && echo "=== VOLUME SNAPSHOTS ===" && kubectl --context=kind-ramen-dr1 get volumesnapshots -A 2>/dev/null | head -5 || echo "No snapshots"'
```

#### **Step 4: Operational Commands**
```bash
# Show VRG events and status
kubectl get events -n nginx-test --sort-by='.lastTimestamp'

# Show backup verification
./examples/verify-ramendr-backups.sh 2>/dev/null || echo "Backup verification available"

# Monitor S3 backup activity
./examples/monitoring/check-minio-backups.sh
```

**🎯 Key Messages:**
- **Multi-Cluster Observability**: Real-time monitoring across hub and DR clusters
- **Resource Tracking**: Comprehensive view of VMs, pods, PVCs, VRGs, and storage
- **KubeVirt Integration**: Specialized monitoring for virtualized workloads
- **Storage Monitoring**: Volume snapshots and replication status
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

### **Multi-Terminal Monitoring Setup:**

**📊 Recommended Terminal Layout:**
```bash
# Terminal 1: Main demo commands (interactive)
./examples/demo-assistant.sh

# Terminal 2: Cluster & Infrastructure Monitoring
watch -n 2 'echo "=== CLUSTERS ===" && kind get clusters && echo "" && echo "=== CONTEXTS ===" && kubectl config get-contexts | grep kind && echo "" && echo "=== RAMEN PODS ===" && kubectl get pods -A | grep ramen | head -5'

# Terminal 3: Application & DR Resources
watch -n 3 'echo "=== DR RESOURCES (Hub) ===" && kubectl --context=kind-ramen-hub get drclusters,drpolicies -n ramen-system 2>/dev/null || echo "Not ready" && echo "" && echo "=== VRG & APPS (DR1) ===" && kubectl --context=kind-ramen-dr1 get vrg,pods,pvc -A 2>/dev/null | head -8'

# Terminal 4: KubeVirt & Storage (if using VMs)
watch -n 5 'kubectl --context=kind-ramen-dr1 get vm,vmi,pods,pvc,vrg,vr -n kubevirt-sample 2>/dev/null | head -10 || echo "No KubeVirt resources"'

# Terminal 5: MinIO Console Access
./examples/access-minio-console.sh
```

**🎯 Monitoring Tips:**
- Start all watch commands before beginning the demo
- Use different refresh intervals: infrastructure (2s), apps (3s), storage (5s)
- Position terminals so audience can see real-time changes
- Have MinIO console ready at http://localhost:9001

### **Technical Variations:**
- **Short Demo (10 min)**: Skip detailed monitoring, focus on automation
- **Technical Deep-Dive (30 min)**: Include architecture explanation and code walkthrough
- **Workshop Format (60 min)**: Let audience run commands themselves
- **KubeVirt Demo (45 min)**: Include VM protection and migration scenarios

---

**🎬 This demo showcases RamenDR as a production-ready, cloud-native disaster recovery solution with comprehensive automation! 🚀**
