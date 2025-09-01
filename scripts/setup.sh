#!/bin/bash
# setup.sh - Main RamenDR development environment setup script
# Automatically detects platform and runs appropriate setup

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
    echo "RamenDR Development Environment Setup"
    echo ""
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  env           Setup development environment (default)"
    echo "  install       Install RamenDR operators"
    echo "  kind          Setup kind clusters"
    echo "  all           Setup environment + install operators"
    echo ""
    echo "Options:"
    echo "  --platform    Force platform (linux|macos)"
    echo "  --help, -h    Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                    # Auto-detect platform and setup environment"
    echo "  $0 env                # Setup development environment only"
    echo "  $0 install            # Install RamenDR operators only"
    echo "  $0 kind               # Setup kind clusters"
    echo "  $0 all                # Complete setup"
    echo "  $0 --platform linux   # Force Linux setup"
}

# Setup development environment
setup_environment() {
    local platform=$1
    
    log_info "Setting up development environment for $platform..."
    
    case $platform in
        linux)
            if [[ -f "$SCRIPT_DIR/setup-linux.sh" ]]; then
                bash "$SCRIPT_DIR/setup-linux.sh"
            else
                log_error "setup-linux.sh not found"
                exit 1
            fi
            ;;
        macos)
            if [[ -f "$SCRIPT_DIR/setup-macos.sh" ]]; then
                bash "$SCRIPT_DIR/setup-macos.sh"
            else
                log_error "setup-macos.sh not found"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported platform: $platform"
            log_info "Supported platforms: linux, macos"
            exit 1
            ;;
    esac
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
    log_info "Setting up kind clusters..."
    
    # Check if kind install script exists
    local kind_script="$SCRIPT_DIR/../docs/LIGHTWEIGHT_K8S_GUIDE.md"
    
    if [[ -f "$kind_script" ]]; then
        log_info "Please refer to the kind setup section in:"
        echo "   $kind_script"
        log_info "Look for '🐋 Option 3: kind Ultra-Lightweight'"
    else
        log_warning "Kind setup guide not found"
        log_info "Please see docs/LIGHTWEIGHT_K8S_GUIDE.md for kind setup"
    fi
}

# Run all setup steps
setup_all() {
    local platform=$1
    
    log_info "🚀 Complete RamenDR setup starting..."
    
    # Step 1: Environment setup
    setup_environment "$platform"
    
    # Step 2: Prompt for cluster setup
    echo ""
    read -p "Setup Kubernetes clusters now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_kind
    fi
    
    # Step 3: Prompt for operator installation
    echo ""
    read -p "Install RamenDR operators now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_operators
    fi
    
    log_success "🎉 Complete RamenDR setup finished!"
}

# Make scripts executable
make_executable() {
    local scripts=(
        "$SCRIPT_DIR/setup-linux.sh"
        "$SCRIPT_DIR/setup-macos.sh"
        "$SCRIPT_DIR/quick-install.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            chmod +x "$script"
        fi
    done
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
