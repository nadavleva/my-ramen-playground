#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Common utilities and logging functions for RamenDR scripts

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${BLUE}🔧 $1${NC}"; }

# KUBECONFIG check for kind demo
check_kubeconfig_for_kind() {
    if [ -z "$KUBECONFIG" ]; then
        log_info "KUBECONFIG not set, setting to default: ~/.kube/config"
        export KUBECONFIG=~/.kube/config
    fi
    
    # Check for kind contexts
    if ! kubectl config get-contexts 2>/dev/null | grep -q "kind-"; then
        log_error "No kind contexts found"
        echo ""
        echo "🔧 To fix this:"
        echo "   export KUBECONFIG=~/.kube/config"
        echo "   kubectl config get-contexts"
        echo ""
        echo "Or run: ./scripts/fix-kubeconfig.sh"
        exit 1
    fi
    log_success "Kind contexts available"
}

# Check kubectl availability
check_kubectl() {
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "kubectl is not connected to a cluster"
        log_info "Please configure kubectl to connect to your Kubernetes cluster"
        exit 1
    fi
    
    local cluster_info=$(kubectl cluster-info | head -n1)
    log_success "Connected to: $cluster_info"
}

# Add new helper functions
wait_for_pod() {
    local context=$1
    local namespace=$2
    local label=$3
    local retries=30

    while [ $retries -gt 0 ]; do
        if kubectl --context=$context -n $namespace get pod -l app=$label | grep -q Running; then
            return 0
        fi
        sleep 10
        retries=$((retries-1))
    done
    return 1
}

verify_minikube_contexts() {
    for ctx in ramen-hub ramen-dr1 ramen-dr2; do
        if ! kubectl config get-contexts $ctx &>/dev/null; then
            log_error "Minikube context $ctx not found"
            exit 1
        fi
    done
}

check_cluster_manager_placement() {
    # Ensure cluster-manager only exists on hub
    for ctx in ramen-dr1 ramen-dr2; do
        if kubectl --context=$ctx -n open-cluster-management get deployment cluster-manager &>/dev/null; then
            log_error "cluster-manager found on $ctx - should only be on hub"
            exit 1
        fi
    done
}

# ========================================
# NEW UTILITY FUNCTIONS FOR RAMEN SCRIPTS
# ========================================

# Utility function to ensure namespace exists and is ready
ensure_namespace() {
    local context="$1"
    local namespace="$2"
    local timeout="${3:-60}"
    
    log_info "Ensuring namespace '$namespace' exists on context '$context'..."
    
    # Create namespace (idempotent)
    kubectl --context="$context" create namespace "$namespace" --dry-run=client -o yaml | kubectl --context="$context" apply -f - >/dev/null
    
    # Check status directly instead of using problematic wait
    local max_attempts=$((timeout / 5))
    local attempts=0
    
    while [ $attempts -lt $max_attempts ]; do
        local status=$(kubectl --context="$context" get namespace "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
        
        if [ "$status" = "Active" ]; then
            log_success "Namespace '$namespace' is ready on '$context'"
            return 0
        fi
        
        if [ $attempts -eq 0 ]; then
            log_info "Waiting for namespace '$namespace' to become active..."
        fi
        
        sleep 5
        ((attempts++))
    done
    
    log_error "Namespace '$namespace' failed to become Active within ${timeout}s on '$context'"
    return 1
}

# Utility function to ensure resource exists with retry
ensure_resource() {
    local context="$1"
    local resource_type="$2"
    local resource_name="$3"
    local namespace="${4:-}"
    local timeout="${5:-60}"
    
    local ns_flag=""
    if [ -n "$namespace" ]; then
        ns_flag="-n $namespace"
    fi
    
    log_info "Checking resource '$resource_type/$resource_name' on context '$context'..."
    
    local max_attempts=$((timeout / 5))
    local attempts=0
    
    while [ $attempts -lt $max_attempts ]; do
        if kubectl --context="$context" get "$resource_type" "$resource_name" $ns_flag >/dev/null 2>&1; then
            log_success "Resource '$resource_type/$resource_name' exists on '$context'"
            return 0
        fi
        
        if [ $attempts -eq 0 ]; then
            log_info "Waiting for resource '$resource_type/$resource_name'..."
        fi
        
        sleep 5
        ((attempts++))
    done
    
    log_error "Resource '$resource_type/$resource_name' not found within ${timeout}s on '$context'"
    return 1
}

# Utility function to wait for deployment to be ready
wait_for_deployment() {
    local context="$1"
    local deployment="$2"
    local namespace="$3"
    local timeout="${4:-300}"
    
    log_info "Waiting for deployment '$deployment' to be ready on '$context'..."
    
    # First check if deployment exists
    if ! kubectl --context="$context" get deployment "$deployment" -n "$namespace" >/dev/null 2>&1; then
        log_error "Deployment '$deployment' not found in namespace '$namespace' on '$context'"
        return 1
    fi
    
    # Use kubectl wait for deployments (more reliable than custom wait)
    if kubectl --context="$context" wait --for=condition=available --timeout="${timeout}s" deployment/"$deployment" -n "$namespace" >/dev/null 2>&1; then
        log_success "Deployment '$deployment' is ready on '$context'"
        return 0
    else
        log_error "Deployment '$deployment' failed to become ready within ${timeout}s on '$context'"
        
        # Show debug info
        log_info "Debug information for '$deployment':"
        kubectl --context="$context" describe deployment "$deployment" -n "$namespace" | tail -10
        kubectl --context="$context" get pods -n "$namespace" -l app="$deployment" --no-headers 2>/dev/null | head -3
        return 1
    fi
}

# Utility function to apply CRD with error handling
apply_crd_safe() {
    local context="$1"
    local crd_name="$2"
    local crd_yaml="$3"
    
    log_info "Applying CRD '$crd_name' on context '$context'..."
    
    if echo "$crd_yaml" | kubectl --context="$context" apply -f - >/dev/null 2>&1; then
        log_success "CRD '$crd_name' applied successfully"
        return 0
    else
        # Check if it already exists
        if kubectl --context="$context" get crd "$crd_name" >/dev/null 2>&1; then
            log_info "CRD '$crd_name' already exists, continuing..."
            return 0
        else
            log_error "CRD '$crd_name' application failed"
            return 1
        fi
    fi
}

# Utility function to apply YAML from URL with retry
apply_url_safe() {
    local context="$1"
    local url="$2"
    local description="${3:-resource}"
    local retries="${4:-3}"
    
    log_info "Applying $description from URL..."
    
    local attempt=1
    while [ $attempt -le $retries ]; do
        if kubectl --context="$context" apply -f "$url" >/dev/null 2>&1; then
            log_success "$description applied successfully"
            return 0
        else
            if [ $attempt -lt $retries ]; then
                log_warning "$description application failed (attempt $attempt/$retries), retrying..."
                sleep 2
            else
                log_warning "$description application failed after $retries attempts (may already exist)"
                return 0  # Don't fail the script for this
            fi
        fi
        ((attempt++))
    done
}

# Utility function to build and load image for minikube
build_and_load_image() {
    local profile="$1"
    local image_name="${2:-quay.io/ramendr/ramen-operator:latest}"
    
    log_info "Building and loading operator image for profile: $profile..."
    
    # Build image (prefer podman, fallback to docker)
    if command -v podman >/dev/null 2>&1 && make podman-build >/dev/null 2>&1; then
        log_info "Podman build succeeded, copying to docker..."
        if command -v docker >/dev/null 2>&1; then
            podman save "$image_name" | docker load >/dev/null 2>&1 || log_warning "Failed to copy to docker registry"
        fi
    else
        log_info "Using docker build..."
        make docker-build >/dev/null 2>&1 || {
            log_error "Image build failed"
            return 1
        }
    fi
    
    # Load into minikube
    log_info "Loading image into minikube profile: $profile..."
    if command -v minikube >/dev/null 2>&1; then
        env KUBECONFIG="" minikube -p "$profile" image load "$image_name" >/dev/null 2>&1 || {
            log_warning "Failed to load image into $profile"
            return 1
        }
        log_success "Image loaded into $profile"
    else
        log_warning "minikube command not found, skipping image load"
        return 1
    fi
    
    return 0
}

# Utility function to check required tools
check_required_tools() {
    local tools=("$@")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again"
        return 1
    fi
    
    log_success "All required tools are available"
    return 0
}

# Utility function to get available contexts matching pattern
get_contexts_matching() {
    local pattern="$1"
    kubectl config get-contexts -o name 2>/dev/null | grep "^${pattern}" || true
}

# Utility function to check if context exists
context_exists() {
    local context="$1"
    kubectl config get-contexts "$context" >/dev/null 2>&1
}

# Utility function to switch context safely
switch_context() {
    local context="$1"
    
    if context_exists "$context"; then
        kubectl config use-context "$context" >/dev/null
        log_info "Switched to context: $context"
        return 0
    else
        log_error "Context '$context' not found"
        return 1
    fi
}

# Utility function to create resource from inline YAML
create_resource() {
    local context="$1"
    local namespace="$2"
    local yaml_content="$3"
    local description="${4:-resource}"
    
    log_info "Creating $description in namespace '$namespace'..."
    
    local ns_flag=""
    if [ -n "$namespace" ] && [ "$namespace" != "cluster-scoped" ]; then
        ns_flag="--namespace=$namespace"
    fi
    
    if echo "$yaml_content" | kubectl --context="$context" apply $ns_flag -f - >/dev/null 2>&1; then
        log_success "$description created successfully"
        return 0
    else
        log_warning "$description creation failed (may already exist)"
        return 0  # Don't fail script for existing resources
    fi
}

# Utility function to wait for condition with custom check
wait_for_condition() {
    local context="$1"
    local check_command="$2"
    local description="$3"
    local timeout="${4:-60}"
    local interval="${5:-5}"
    
    log_info "Waiting for $description..."
    
    local max_attempts=$((timeout / interval))
    local attempts=0
    
    while [ $attempts -lt $max_attempts ]; do
        if eval "kubectl --context='$context' $check_command" >/dev/null 2>&1; then
            log_success "$description is ready"
            return 0
        fi
        
        sleep $interval
        ((attempts++))
        
        if [ $((attempts % 6)) -eq 0 ]; then  # Log every 30 seconds
            log_info "Still waiting for $description... (${attempts}/${max_attempts})"
        fi
    done
    
    log_error "$description not ready within ${timeout}s"
    return 1
}

# Utility function to verify installation
verify_deployment() {
    local context="$1"
    local deployment="$2"
    local namespace="$3"
    local description="${4:-deployment}"
    
    if kubectl --context="$context" get deployment "$deployment" -n "$namespace" >/dev/null 2>&1; then
        local ready=$(kubectl --context="$context" get deployment "$deployment" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired=$(kubectl --context="$context" get deployment "$deployment" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
            log_success "✅ $description deployed and ready ($ready/$desired)"
            return 0
        else
            log_warning "⚠️  $description deployed but not ready ($ready/$desired)"
            return 1
        fi
    else
        log_error "❌ $description not found"
        return 1
    fi
}