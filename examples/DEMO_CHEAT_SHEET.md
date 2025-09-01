<!--
SPDX-FileCopyrightText: The RamenDR authors
SPDX-License-Identifier: Apache-2.0
-->

# 🎯 RamenDR Demo Cheat Sheet

## 📋 **Quick Command Reference**

### **Setup (3-4 mins)**
```bash
# Complete automated setup
./scripts/fresh-demo.sh

# Monitor in separate terminal
watch -n 2 'kind get clusters && echo "---" && kubectl config current-context'
```

### **Validation (1-2 mins)**
```bash
# Verify clusters
kind get clusters

# Check operators
for ctx in kind-ramen-hub kind-ramen-dr1 kind-ramen-dr2; do
    kubectl config use-context $ctx
    kubectl get pods -n ramen-system
done

# Verify demo app and VRG
kubectl config use-context kind-ramen-hub
kubectl get all,pvc -n nginx-test
kubectl get vrg -n nginx-test
```

### **S3 Demo (2-3 mins)**
```bash
# MinIO console
./examples/access-minio-console.sh
# Open: http://localhost:9001 (minioadmin/minioadmin)

# CLI verification
./examples/monitoring/check-minio-backups.sh
./examples/monitoring/check-ramendr-status.sh
```

### **DR Capabilities (2 mins)**
```bash
# Show DR resources
kubectl get drpolicy,drcluster -o wide

# Switch clusters
kubectl config use-context kind-ramen-dr1
kubectl get nodes && kubectl get storageclass

# Show DRPC concept
cat examples/test-application/nginx-drpc.yaml
```

### **Cleanup**
```bash
./scripts/cleanup-all.sh
```

---

## 🗣️ **Key Talking Points**

### **Introduction**
- "RamenDR = Kubernetes-native disaster recovery"
- "Protects applications across multiple clusters"
- "Automatic metadata backup to S3"

### **Setup Demo**
- "Zero configuration required"
- "One command creates complete environment"
- "Built-in validation at each step"

### **Application Protection**
- "VRG discovers and protects PVCs automatically"
- "Kubernetes metadata stored in S3"
- "Cross-cluster recovery capability"

### **Production Ready**
- "Comprehensive monitoring included"
- "Works with any Kubernetes distribution"
- "Policy-driven governance"

---

## ⚡ **Quick Demo (10 mins)**

1. **Setup** (4 min): `./scripts/fresh-demo.sh`
2. **Show VRG** (2 min): `kubectl describe vrg nginx-test-vrg -n nginx-test`
3. **S3 Browser** (2 min): MinIO console at http://localhost:9001
4. **Status** (1 min): `./examples/monitoring/check-ramendr-status.sh`
5. **Cleanup** (1 min): `./scripts/cleanup-all.sh`

---

## 🎬 **Demo Variations**

### **Technical Deep-Dive (20+ mins)**
- Include architecture explanation
- Show source code walkthrough
- Demonstrate manual VRG creation
- Explain controller reconciliation loops

### **Workshop Format (45+ mins)**
- Let audience run commands
- Hands-on VRG modification
- S3 exploration
- Troubleshooting exercises

---

## 📚 **Resources to Reference**

- **Architecture**: `examples/RAMENDR_ARCHITECTURE_GUIDE.md`
- **Quick Start**: `examples/AUTOMATED_DEMO_QUICKSTART.md`
- **Full Guide**: `examples/DEMO_FLOW_GUIDE.md`
- **Interactive**: `examples/demo-assistant.sh`

---

## 🚨 **Common Questions & Answers**

**Q: "How does this work with real storage?"**
A: "RamenDR integrates with any CSI driver. Show CSI integration in architecture guide."

**Q: "What about production scale?"**
A: "RamenDR handles thousands of PVCs. Show VRG selector patterns and batch operations."

**Q: "Does this work with OpenShift?"**
A: "Yes! RamenDR originated as OpenShift DR solution and works with any Kubernetes."

**Q: "How do you handle secrets and configs?"**
A: "VRG includes kubeObjectProtection that backs up any Kubernetes resource to S3."

---

## ⚠️ **Pre-Demo Checklist**

- [ ] Docker daemon running
- [ ] `kind` and `kubectl` installed
- [ ] Clean environment (run cleanup if needed)
- [ ] Browser bookmark: http://localhost:9001
- [ ] Terminal windows ready (main + monitoring)
- [ ] Architecture diagram ready if needed

---

**🎯 This cheat sheet gets you through a successful RamenDR demo in any time format! 🚀**
