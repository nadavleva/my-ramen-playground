# RamenDR Demo

Welcome to the organized RamenDR demo structure with **bulletproof automation**!

## 🛡️ **BULLETPROOF AUTOMATION (v2.0+)**

### ✅ **ALL KNOWN ISSUES AUTOMATICALLY PREVENTED:**

Our enhanced scripts now **automatically handle** every issue we've encountered during development:

| Issue Category | Problem | Auto-Fix | Script |
|----------------|---------|----------|---------|
| **Environment** | KUBECONFIG conflicts → permission denied | ✅ Auto-detect & unset | `minikube_setup.sh` |
| **System** | inotify limits → kubelet failures | ✅ Increase limits persistently | `minikube_setup.sh` |
| **Operators** | Missing OCM CRDs → hub operator crashes | ✅ Install 5 required CRDs | `minikube_quick-install.sh` |
| **Networking** | Cluster isolation → empty S3 buckets | ✅ Host network + dynamic endpoints | `deploy-ramendr-s3.sh` |
| **Images** | Podman/Docker mismatch → ImagePullBackOff | ✅ Auto-copy between registries | `minikube_quick-install.sh` |
| **Resources** | Insufficient RAM/CPU → startup failures | ✅ Pre-flight validation | `minikube_setup.sh` |
| **Timing** | Parallel creation → certificate issues | ✅ Sequential with proper waits | `minikube_setup.sh` |

**Result: Zero repeated troubleshooting needed!** 🎯

For complete issue details: 📋 **[MINIKUBE_COMPLETE_TROUBLESHOOTING.md](docs/MINIKUBE_COMPLETE_TROUBLESHOOTING.md)**

---

## Folder Structure

- **docs/**: All documentation and guides
- **scripts/**: Executable scripts for setup and demos  
- **yaml/**: YAML configuration files and templates
- **monitoring/**: Real-time monitoring and status scripts

## Quick Start

### For MINIKUBE (Recommended for laptops):
```bash
# FIRST: Clean environment
unset KUBECONFIG

cd scripts/
./minikube_comprehensive-demo.sh --auto
```

### For KIND (Docker-based):
```bash
cd scripts/  
./kind_ramendr-demo.sh
```

## Monitoring Your Demo
```bash
cd monitoring/
./minikube_monitoring.sh    # For MINIKUBE
./kind_monitoring.sh        # For KIND
```

## Documentation

- **MINIKUBE_README.md** - MINIKUBE setup guide
- **KIND_README.md** - KIND setup guide  
- **DEMO_FLOW_GUIDE.md** - Step-by-step demo walkthrough
- **RAMENDR_ARCHITECTURE_GUIDE.md** - Technical architecture overview
- **MINIKUBE_TROUBLESHOOTING_GUIDE.md** - 🔧 Legacy troubleshooting guide 
- **MINIKUBE_COMPLETE_TROUBLESHOOTING.md** - 🛡️ **COMPLETE issue catalog with bulletproof prevention**

## File Naming Convention

- **minikube_**: Scripts and docs specific to MINIKUBE
- **kind_**: Scripts and docs specific to KIND
- **Generic files**: Work with both platforms

