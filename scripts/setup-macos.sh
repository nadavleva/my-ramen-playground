#!/bin/bash
# setup-macos.sh - Automated macOS development environment setup for RamenDR
# Based on test/README.md macOS setup instructions

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Homebrew is installed
check_homebrew() {
    if ! command_exists brew; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add Homebrew to PATH for Apple Silicon Macs
        if [[ $(uname -m) == "arm64" ]]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        
        log_success "Homebrew installed"
    else
        log_success "Homebrew already installed: $(brew --version | head -n1)"
    fi
}

# Install Homebrew packages
install_homebrew_packages() {
    log_info "Installing development tools via Homebrew..."
    
    local packages=(
        "argocd"
        "go"
        "helm"
        "kubectl"
        "kustomize"
        "qemu"
        "lima"
        "minio/stable/mc"
        "velero"
        "kubevirt/kubevirt/virtctl"
    )
    
    for package in "${packages[@]}"; do
        if brew list "${package##*/}" &>/dev/null; then
            log_success "$package already installed"
        else
            log_info "Installing $package..."
            brew install "$package"
        fi
    done
}

# Install clusteradm
install_clusteradm() {
    if command_exists clusteradm; then
        log_success "clusteradm already installed: $(clusteradm version)"
        return
    fi
    
    log_info "Installing clusteradm..."
    curl -L https://raw.githubusercontent.com/open-cluster-management-io/clusteradm/main/install.sh | bash -s 0.11.2
    log_success "clusteradm installed"
}

# Install subctl
install_subctl() {
    if command_exists subctl; then
        log_success "subctl already installed: $(subctl version)"
        return
    fi
    
    log_info "Installing subctl..."
    curl -Ls https://get.submariner.io | bash
    sudo install ~/.local/bin/subctl /usr/local/bin/
    rm -f ~/.local/bin/subctl
    log_success "subctl installed: $(subctl version)"
}

# Install kubectl-gather with architecture detection
install_kubectl_gather() {
    if command_exists kubectl-gather; then
        log_success "kubectl-gather already installed: $(kubectl-gather version)"
        return
    fi
    
    log_info "Installing kubectl-gather..."
    tag="$(curl -fsSL https://api.github.com/repos/nirs/kubectl-gather/releases/latest | jq -r .tag_name)"
    arch="$(uname -m)"
    [[ "$arch" == "x86_64" ]] && arch="amd64"
    [[ "$arch" == "arm64" ]] && arch="arm64"
    
    curl -L -o kubectl-gather "https://github.com/nirs/kubectl-gather/releases/download/$tag/kubectl-gather-$tag-darwin-$arch"
    chmod +x kubectl-gather
    sudo mv kubectl-gather /usr/local/bin/
    log_success "kubectl-gather installed: $(kubectl-gather version)"
}

# Install socket_vmnet (required for Lima)
install_socket_vmnet() {
    if brew list socket_vmnet &>/dev/null; then
        log_success "socket_vmnet already installed"
        return
    fi
    
    log_info "Installing socket_vmnet for Lima networking..."
    brew install socket_vmnet
    
    # Install the launchd service
    log_info "Setting up socket_vmnet launchd service..."
    sudo brew services start socket_vmnet
    
    log_success "socket_vmnet installed and configured"
    log_warning "You may need to restart your system for networking changes to take effect"
}

# Setup Lima environment  
setup_lima() {
    log_info "Setting up Lima for RamenDR development..."
    
    # Create Lima configuration directory
    mkdir -p ~/.lima
    
    # Create a RamenDR-optimized Lima configuration
    cat > ~/.lima/ramen-dev.yaml <<EOF
# RamenDR development Lima configuration
arch: null
images:
- location: "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
  arch: "x86_64"
- location: "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-arm64.qcow2"
  arch: "aarch64"

cpus: 4
memory: "8GiB"
disk: "60GiB"

mounts:
- location: "~"
  writable: true
- location: "/tmp/lima"
  writable: true

networks:
- socket_vmnet

provision:
- mode: system
  script: |
    #!/bin/bash
    apt-get update
    apt-get install -y curl wget git jq

# Enable Docker and Kubernetes tools
containerd:
  system: true
  user: false

kubernetes:
  version: "v1.29.1"
EOF
    
    log_success "Lima configuration created: ~/.lima/ramen-dev.yaml"
    log_info "To start Lima VM: limactl start ramen-dev"
}

# Install Docker Desktop (if not using Lima)
install_docker_desktop() {
    if command_exists docker; then
        log_success "Docker already installed: $(docker --version)"
        return
    fi
    
    log_warning "Docker not found. Please install Docker Desktop:"
    log_info "Option 1: Download from https://docs.docker.com/desktop/mac/install/"
    log_info "Option 2: Install via Homebrew: brew install --cask docker"
    
    read -p "Install Docker Desktop via Homebrew now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        brew install --cask docker
        log_success "Docker Desktop installed. Please start it from Applications."
    fi
}

# Verify all installations
verify_installation() {
    log_info "Verifying installations..."
    
    local tools=(
        "kubectl" "helm" "kustomize" "argocd" "go"
        "qemu-system-x86_64" "lima" "mc" "velero" "virtctl"
        "clusteradm" "subctl" "kubectl-gather"
    )
    
    local failed=0
    for tool in "${tools[@]}"; do
        if command_exists "$tool"; then
            log_success "$tool: installed"
        else
            log_error "$tool: not found"
            ((failed++))
        fi
    done
    
    # Check Docker separately (might be Docker Desktop)
    if command_exists docker; then
        log_success "docker: installed"
    else
        log_warning "docker: not found (install Docker Desktop)"
        ((failed++))
    fi
    
    if [ $failed -eq 0 ]; then
        log_success "All tools installed successfully!"
    else
        log_warning "$failed tools failed to install or need manual setup"
    fi
}

# Main installation function
main() {
    log_info "🚀 Starting automated RamenDR macOS development environment setup..."
    
    # Check for required tools
    if ! command_exists curl; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    # Install Homebrew first
    check_homebrew
    
    # Install jq (required for kubectl-gather)
    if ! command_exists jq; then
        log_info "Installing jq..."
        brew install jq
    fi
    
    # Install core development tools
    install_homebrew_packages
    
    # Install additional RamenDR tools
    install_clusteradm
    install_subctl
    install_kubectl_gather
    
    # Container and virtualization
    install_socket_vmnet
    setup_lima
    install_docker_desktop
    
    verify_installation
    
    echo ""
    log_success "🎉 Installation complete!"
    echo ""
    log_info "📝 Next steps:"
    echo "   1. Start Docker Desktop (if installed)"
    echo "   2. Optional: Start Lima VM: limactl start ramen-dev"
    echo "   3. Test kubectl: kubectl version --client"
    echo "   4. Follow the RamenDR quick start guide"
    echo ""
    log_info "💡 Lima setup:"
    echo "   - Configuration saved to ~/.lima/ramen-dev.yaml"
    echo "   - Start VM: limactl start ramen-dev"
    echo "   - SSH into VM: limactl shell ramen-dev"
}

# Run main function
main "$@"
