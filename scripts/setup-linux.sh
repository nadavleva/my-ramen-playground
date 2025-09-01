#!/bin/bash
# setup-linux.sh - Automated Linux development environment setup for RamenDR
# Based on test/README.md Linux setup instructions

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

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    else
        log_error "Cannot detect Linux distribution"
        exit 1
    fi
    log_info "Detected: $PRETTY_NAME"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install package based on distribution
install_package() {
    local package=$1
    case $DISTRO in
        ubuntu|debian)
            sudo apt update && sudo apt install -y "$package"
            ;;
        fedora)
            sudo dnf install -y "$package"
            ;;
        rhel|centos|rocky|almalinux)
            sudo dnf install -y "$package"
            ;;
        *)
            log_error "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

# Install libvirt and virtualization tools
install_libvirt() {
    log_info "Installing libvirt and virtualization support..."
    
    case $DISTRO in
        ubuntu|debian)
            install_package "qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            install_package "@virtualization"
            ;;
    esac
    
    # Add user to libvirt group
    sudo usermod -a -G libvirt "$(whoami)"
    log_success "libvirt installed and user added to libvirt group"
    log_warning "Please logout and login again for group membership to take effect"
}

# Install minikube
install_minikube() {
    if command_exists minikube; then
        log_success "minikube already installed: $(minikube version --short)"
        return
    fi
    
    log_info "Installing minikube..."
    case $DISTRO in
        ubuntu|debian)
            curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
            sudo install minikube-linux-amd64 /usr/local/bin/minikube
            rm minikube-linux-amd64
            ;;
        fedora|rhel|centos|rocky|almalinux)
            sudo dnf install -y https://storage.googleapis.com/minikube/releases/latest/minikube-latest.x86_64.rpm
            ;;
    esac
    log_success "minikube installed: $(minikube version --short)"
}

# Install kubectl
install_kubectl() {
    if command_exists kubectl; then
        log_success "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
        return
    fi
    
    log_info "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    log_success "kubectl installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
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

# Install velero
install_velero() {
    if command_exists velero; then
        log_success "velero already installed: $(velero version --client-only)"
        return
    fi
    
    log_info "Installing velero..."
    curl -L -o velero.tar.gz https://github.com/vmware-tanzu/velero/releases/download/v1.16.1/velero-v1.16.1-linux-amd64.tar.gz
    tar xf velero.tar.gz --strip 1 velero-v1.16.1-linux-amd64/velero
    sudo install velero /usr/local/bin
    rm velero.tar.gz velero
    log_success "velero installed: $(velero version --client-only)"
}

# Install helm
install_helm() {
    if command_exists helm; then
        log_success "helm already installed: $(helm version --short)"
        return
    fi
    
    log_info "Installing helm..."
    case $DISTRO in
        ubuntu|debian)
            curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
            sudo apt update && sudo apt install -y helm
            ;;
        fedora|rhel|centos|rocky|almalinux)
            install_package "helm"
            ;;
    esac
    log_success "helm installed: $(helm version --short)"
}

# Install kustomize
install_kustomize() {
    if command_exists kustomize; then
        log_success "kustomize already installed: $(kustomize version --short)"
        return
    fi
    
    log_info "Installing kustomize..."
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
    log_success "kustomize installed: $(kustomize version --short)"
}

# Install argocd CLI
install_argocd() {
    if command_exists argocd; then
        log_success "argocd already installed: $(argocd version --client --short)"
        return
    fi
    
    log_info "Installing argocd CLI..."
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x argocd-linux-amd64
    sudo mv argocd-linux-amd64 /usr/local/bin/argocd
    log_success "argocd installed: $(argocd version --client --short)"
}

# Install kubectl-gather
install_kubectl_gather() {
    if command_exists kubectl-gather; then
        log_success "kubectl-gather already installed: $(kubectl-gather version)"
        return
    fi
    
    log_info "Installing kubectl-gather..."
    tag="$(curl -fsSL https://api.github.com/repos/nirs/kubectl-gather/releases/latest | jq -r .tag_name)"
    curl -L -o kubectl-gather "https://github.com/nirs/kubectl-gather/releases/download/$tag/kubectl-gather-$tag-linux-amd64"
    chmod +x kubectl-gather
    sudo mv kubectl-gather /usr/local/bin/
    log_success "kubectl-gather installed: $(kubectl-gather version)"
}

# Install Go
install_go() {
    if command_exists go; then
        log_success "Go already installed: $(go version)"
        return
    fi
    
    log_info "Installing Go..."
    GO_VERSION=$(curl -s https://go.dev/VERSION?m=text)
    curl -L -o go.tar.gz "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go.tar.gz
    rm go.tar.gz
    
    # Add Go to PATH if not already there
    if ! echo "$PATH" | grep -q "/usr/local/go/bin"; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        export PATH=$PATH:/usr/local/go/bin
    fi
    
    log_success "Go installed: $(go version)"
    log_warning "Please run 'source ~/.bashrc' or logout/login to update PATH"
}

# Install Python development tools
install_python_tools() {
    log_info "Installing Python development tools..."
    case $DISTRO in
        ubuntu|debian)
            install_package "python3 python3-pip python3-venv"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            install_package "python3 python3-pip python3-virtualenv"
            ;;
    esac
    log_success "Python tools installed"
}

# Install Docker
install_docker() {
    if command_exists docker; then
        log_success "Docker already installed: $(docker --version)"
        return
    fi
    
    log_info "Installing Docker..."
    case $DISTRO in
        ubuntu|debian)
            install_package "docker.io"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            install_package "docker"
            ;;
    esac
    
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker "$(whoami)"
    log_success "Docker installed and configured"
    log_warning "Please logout and login again for Docker group membership to take effect"
}

# Verify all installations
verify_installation() {
    log_info "Verifying installations..."
    
    local tools=(
        "minikube" "kubectl" "clusteradm" "subctl" "velero"
        "helm" "kustomize" "argocd" "kubectl-gather" "go" "docker"
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
    
    if [ $failed -eq 0 ]; then
        log_success "All tools installed successfully!"
    else
        log_warning "$failed tools failed to install"
    fi
}

# Main installation function
main() {
    log_info "🚀 Starting automated RamenDR Linux development environment setup..."
    
    # Check for jq (required for some installations)
    if ! command_exists jq; then
        log_info "Installing jq (required for some tools)..."
        install_package "jq"
    fi
    
    detect_distro
    
    # Core virtualization and container tools
    install_libvirt
    install_docker
    
    # Kubernetes tools
    install_minikube
    install_kubectl
    install_helm
    install_kustomize
    
    # RamenDR specific tools
    install_clusteradm
    install_subctl
    install_velero
    install_argocd
    install_kubectl_gather
    
    # Development tools
    install_go
    install_python_tools
    
    verify_installation
    
    echo ""
    log_success "🎉 Installation complete!"
    echo ""
    log_info "📝 Next steps:"
    echo "   1. Logout and login again (for group memberships)"
    echo "   2. Run: source ~/.bashrc (if Go was installed)"
    echo "   3. Test Docker: docker run hello-world"
    echo "   4. Test minikube: minikube start"
    echo "   5. Follow the RamenDR quick start guide"
}

# Run main function
main "$@"
