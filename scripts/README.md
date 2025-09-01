# RamenDR Automation Scripts

This directory contains automation scripts that eliminate manual copy-pasting from documentation. These scripts automate the installation steps from various README files.

## ⚠️ Production Deployment Notes

**For Production Use**: These scripts are optimized for **kind development environments**. For better stability and performance, consider:

- **🏆 Recommended**: **k3s + Longhorn** (lightweight, production-ready)
- **🥈 Alternative**: **minikube** (officially tested)  
- **🥉 Real clusters**: AWS EKS, GKE, AKS, or on-premises Kubernetes

**Current limitations with kind**:
- API server timeout issues with DR cluster operators
- VolSync deployment challenges  
- Networking quirks due to containerized nodes

**k3s Issues Discovered**:
- **RBAC bootstrap failures**: Persistent failures in `poststarthook/rbac/bootstrap-roles` and `poststarthook/scheduling/bootstrap-system-priority-classes`
- **Service restart loops**: k3s keeps restarting due to bootstrap failures
- **Log spam**: k3s dumps debug logs to terminal during failures (use log redirection workaround)

**k3s Workarounds**:
```bash
# Install with log redirection to avoid terminal spam
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--docker --disable=traefik" sh - >/tmp/k3s-install.log 2>&1

# Set up log rotation
sudo mkdir -p /var/log/k3s
sudo tee /etc/logrotate.d/k3s > /dev/null << 'EOF'
/var/log/k3s/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    maxsize 100M
}
EOF

# Alternative: Try disabling RBAC components
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--docker --disable-network-policy --disable=traefik --write-kubeconfig-mode=644" sh -
```

See `docs/LIGHTWEIGHT_K8S_GUIDE.md` for k3s setup instructions.

## 🚀 Quick Start

**One-command setup:**
```bash
# Auto-detect platform and setup everything
./setup.sh all
```

## 📋 Available Scripts

### 🎯 `setup.sh` - Main Entry Point
**Universal setup script with platform detection**

```bash
# Setup development environment only
./setup.sh env

# Install RamenDR operators only  
./setup.sh install

# Setup kind clusters
./setup.sh kind

# Complete setup (environment + operators)
./setup.sh all

# Force specific platform
./setup.sh --platform linux all
```

### 🐧 `setup-linux.sh` - Linux Development Environment
**Automates all Linux setup steps from `test/README.md`**

**Installs:**
- libvirt + virtualization tools
- Docker with user permissions
- minikube, kubectl, helm, kustomize
- clusteradm, subctl, velero, argocd
- kubectl-gather with architecture detection
- Go development environment
- Python tools

**Supports:**
- Ubuntu/Debian (apt)
- RHEL/CentOS/Fedora (dnf)

### 🍎 `setup-macos.sh` - macOS Development Environment  
**Automates all macOS setup steps from `test/README.md`**

**Installs:**
- Homebrew (if needed)
- Development tools: go, kubectl, helm, etc.
- Virtualization: qemu, lima, virtctl
- RamenDR tools: clusteradm, subctl, velero
- kubectl-gather with Intel/ARM detection
- Lima VM configuration for RamenDR

### ⚡ `quick-install.sh` - RamenDR Operator Installation
**Automates operator installation from main `README.md`**

**Features:**
- Interactive mode for installation type selection
- Hub operator, cluster operator, or both
- Automatic waiting for deployment readiness
- Installation verification
- Sample DRPolicy creation
- Command-line options for automation

```bash
# Interactive mode
./quick-install.sh

# Command line options
./quick-install.sh --hub     # Hub operator only
./quick-install.sh --cluster # Cluster operator only  
./quick-install.sh --both    # Both operators
```

## 🎯 Use Cases

### **Developer Onboarding**
```bash
# New developer setup - everything automated
git clone https://github.com/RamenDR/ramen.git
cd ramen/scripts
./setup.sh all
```

### **CI/CD Integration**
```bash
# Automated testing environment
./setup.sh env
./setup.sh kind
./setup.sh install --both
```

### **Production Deployment**
```bash
# Hub cluster
./quick-install.sh --hub

# Each managed cluster  
./quick-install.sh --cluster
```

### **Multi-Platform Development**
```bash
# Force platform for containers/VMs
./setup.sh --platform linux env
```

## 🛡️ Safety Features

### **Idempotent Operations**
- Scripts detect existing installations
- Skip already installed tools
- Safe to run multiple times

### **Error Handling**
- Comprehensive error checking
- Clear error messages with solutions
- Graceful failure handling

### **User Interaction**
- Confirmation prompts for destructive operations
- Progress indicators and status messages
- Clear next steps after completion

## 🔧 Requirements

### **All Platforms**
- `curl` and `bash`
- Internet connection
- Administrator/sudo privileges

### **Linux Specific**
- Package manager: `apt` or `dnf`
- Systemd (for Docker service)

### **macOS Specific**  
- Xcode Command Line Tools
- Homebrew (auto-installed if missing)

## 📝 Customization

### **Environment Variables**
```bash
# Skip specific installations
export SKIP_DOCKER=true
export SKIP_MINIKUBE=true
./setup-linux.sh
```

### **Manual Tool Selection**
Edit the `tools` array in respective scripts to customize what gets installed.

## 🐛 Troubleshooting

### **Permission Issues**
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Docker group membership (Linux)
sudo usermod -aG docker $USER
# Then logout/login
```

### **Network Issues**
```bash
# Check connectivity
curl -I https://github.com

# Use alternative package sources if needed
export HOMEBREW_BOTTLE_DOMAIN=https://mirrors.ustc.edu.cn/homebrew-bottles
```

### **Platform Detection Issues**
```bash
# Force platform
./setup.sh --platform linux env
```

## 🤝 Contributing

### **Adding New Tools**
1. Add to appropriate script's tools array
2. Create install function
3. Add to verification section
4. Test on target platform

### **Supporting New Platforms**
1. Create `setup-{platform}.sh`
2. Add platform detection to `setup.sh`
3. Update this README

### **Script Testing**
```bash
# Test in clean container
docker run -it ubuntu:22.04 bash
# Copy scripts and test

# Test on multiple distributions
```

## 📚 Related Documentation

- **Main README**: `../README.md` - Project overview and manual installation
- **Test README**: `../test/README.md` - Detailed platform setup instructions  
- **Deployment Guides**: `../docs/` - Various deployment scenarios
- **Contributing**: `../CONTRIBUTING.md` - Development guidelines

---

**💡 Pro Tip**: Bookmark `./setup.sh all` - it's your one-stop command for complete RamenDR development environment setup!
