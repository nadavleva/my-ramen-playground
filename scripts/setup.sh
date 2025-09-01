#!/bin/bash
# setup.sh - Main RamenDR development environment setup script
# Automatically detects platform and runs appropriate setup

# set -e  # Exit on errors, but allow more flexibility

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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect platform
detect_platform() {
    case "$(uname -s)" in
        Linux*)
            echo "linux"
            ;;
        Darwin*)
            echo "macos"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Show help
show_help() {
    echo "=============================================="
    echo "🚀 RamenDR Development Environment Setup"
    echo "=============================================="
    echo ""
    echo "Enhanced automation scripts with Docker support, networking fixes,"
    echo "and comprehensive error handling."
    echo ""
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  env           Setup development environment (default)"
    echo "                • Installs Docker, kubectl, helm, kind, etc."
    echo "                • Handles podman conflicts automatically"
    echo "                • Platform-specific optimizations"
    echo ""
    echo "  kind          Setup kind clusters"
    echo "                • Creates optimized Docker-based clusters"
    echo "                • Fixes networking issues"
    echo "                • Verifies cluster health"
    echo ""
    echo "  install       Install RamenDR operators"
    echo "                • Hub and DR cluster operators"
    echo "                • Automatic image building/loading"
    echo "                • Configuration verification"
    echo ""
    echo "  all           Complete setup (recommended)"
    echo "                • Runs all steps with user prompts"
    echo "                • Comprehensive environment setup"
    echo "                • Ready for RamenDR testing"
    echo ""
    echo "Options:"
    echo "  --platform    Force platform (linux|macos)"
    echo "  --help, -h    Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 all                     # 🎯 Complete setup (recommended)"
    echo "  $0 env                     # Environment prerequisites only"
    echo "  $0 kind                    # kind clusters with Docker"
    echo "  $0 install                 # RamenDR operators only"
    echo "  $0 --platform linux all   # Force Linux platform"
    echo ""
    echo "💡 Pro tip: Start with '$0 all' for first-time setup!"
    echo ""
}

# Setup development environment
setup_environment() {
    local platform=$1
    
    echo "=========================================="
    log_info "🔧 Setting up development environment for $platform"
    echo "=========================================="
    echo ""
    log_info "This will install all prerequisites including Docker, Kubernetes tools, and RamenDR components"
    echo ""
    
    case $platform in
        linux)
            if [[ -f "$SCRIPT_DIR/setup-linux.sh" ]]; then
                log_info "📋 Running enhanced Linux setup script..."
                bash "$SCRIPT_DIR/setup-linux.sh"
            else
                log_error "setup-linux.sh not found in $SCRIPT_DIR"
                exit 1
            fi
            ;;
        macos)
            if [[ -f "$SCRIPT_DIR/setup-macos.sh" ]]; then
                log_info "📋 Running enhanced macOS setup script..."
                bash "$SCRIPT_DIR/setup-macos.sh"
            else
                log_error "setup-macos.sh not found in $SCRIPT_DIR"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported platform: $platform"
            log_info "Supported platforms: linux, macos"
            exit 1
            ;;
    esac
    
    echo ""
    log_success "✅ Development environment setup complete!"
    echo ""
}

# Install RamenDR operators
install_operators() {
    log_info "Installing RamenDR operators..."
    
    if [[ -f "$SCRIPT_DIR/quick-install.sh" ]]; then
        bash "$SCRIPT_DIR/quick-install.sh"
    else
        log_error "quick-install.sh not found"
        exit 1
    fi
}

# Setup kind clusters
setup_kind() {
    echo "=========================================="
    log_info "🐋 Setting up kind clusters for RamenDR"
    echo "=========================================="
    echo ""
    log_info "This will create optimized kind clusters using Docker with networking fixes"
    echo ""
    
    # Check if enhanced kind script exists
    if [[ -f "$SCRIPT_DIR/setup-kind-enhanced.sh" ]]; then
        log_info "📋 Running enhanced kind cluster setup..."
        bash "$SCRIPT_DIR/setup-kind-enhanced.sh"
    else
        log_error "setup-kind-enhanced.sh not found in $SCRIPT_DIR"
        log_info "Falling back to manual kind setup instructions..."
        echo ""
        log_info "Please refer to the kind setup section in:"
        echo "   docs/LIGHTWEIGHT_K8S_GUIDE.md"
        log_info "Look for '🐋 Option 3: kind Ultra-Lightweight'"
    fi
    
    echo ""
    log_success "✅ kind cluster setup complete!"
    echo ""
}

# Run all setup steps
setup_all() {
    local platform=$1
    
    echo "=============================================="
    log_info "🚀 Complete RamenDR Development Environment Setup"
    echo "=============================================="
    echo ""
    log_info "This comprehensive setup will:"
    echo "   1. 🔧 Install all development prerequisites"
    echo "   2. 🐋 Create optimized kind clusters"
    echo "   3. ⚙️  Install and configure RamenDR operators"
    echo "   4. 🧪 Prepare environment for testing"
    echo ""
    
    # Step 1: Environment setup
    log_info "📋 Step 1/3: Development Environment Setup"
    echo "----------------------------------------------"
    setup_environment "$platform"
    
    # Step 2: Prompt for cluster setup
    echo ""
    log_info "📋 Step 2/3: Kubernetes Cluster Setup"
    echo "----------------------------------------------"
    read -p "❓ Setup kind clusters now? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        setup_kind
    else
        log_info "⏭️  Skipping cluster setup (you can run: ./scripts/setup.sh kind later)"
    fi
    
    # Step 3: Prompt for operator installation
    echo ""
    log_info "📋 Step 3/3: RamenDR Operator Installation"
    echo "----------------------------------------------"
    read -p "❓ Install RamenDR operators now? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        install_operators
    else
        log_info "⏭️  Skipping operator installation (you can run: ./scripts/setup.sh install later)"
    fi
    
    echo ""
    echo "=============================================="
    log_success "🎉 Complete RamenDR Setup Finished!"
    echo "=============================================="
    echo ""
    log_info "📝 What's been set up:"
    echo "   ✅ Development tools (Docker, kubectl, helm, etc.)"
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "   ✅ kind clusters ready for RamenDR"
        echo "   ✅ RamenDR operators installed"
    fi
    echo ""
    log_info "🚀 Next steps:"
    echo "   1. 🧪 Test the setup: kubectl get nodes"
    echo "   2. 📚 Follow RamenDR user guide for applications"
    echo "   3. 🔍 Check logs: kubectl logs -n ramen-system -l app=ramen-hub"
    echo ""
}

# Make scripts executable
make_executable() {
    log_info "🔧 Making automation scripts executable..."
    
    local scripts=(
        "$SCRIPT_DIR/setup-linux.sh"
        "$SCRIPT_DIR/setup-macos.sh"
        "$SCRIPT_DIR/quick-install.sh"
        "$SCRIPT_DIR/setup-kind-enhanced.sh"
    )
    
    local fixed=0
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            chmod +x "$script" 2>/dev/null || true
            ((fixed++))
        fi
    done
    
    log_success "✅ Made $fixed automation scripts executable"
}

# Main function
main() {
    local platform=""
    local command="env"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --platform)
                platform="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            env|install|kind|all)
                command="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Auto-detect platform if not specified
    if [[ -z "$platform" ]]; then
        platform=$(detect_platform)
        if [[ "$platform" == "unknown" ]]; then
            log_error "Cannot detect platform. Use --platform to specify."
            exit 1
        fi
        log_info "Detected platform: $platform"
    fi
    
    # Make scripts executable
    make_executable
    
    # Execute command
    case $command in
        env)
            setup_environment "$platform"
            ;;
        install)
            install_operators
            ;;
        kind)
            setup_kind
            ;;
        all)
            setup_all "$platform"
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
