#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Cluster Configuration Detection and Setup
# This script detects whether you're using kind or minikube and sets appropriate context names

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Detect cluster type and set context names
detect_cluster_type() {
    local kind_clusters minikube_clusters
    
    # Check for kind clusters
    if command -v kind >/dev/null 2>&1; then
        kind_clusters=$(kind get clusters 2>/dev/null | grep -E "(ramen-hub|ramen-dr)" | wc -l)
    else
        kind_clusters=0
    fi
    
    # Check for minikube clusters  
    if command -v minikube >/dev/null 2>&1; then
        minikube_clusters=$(minikube profile list -o json 2>/dev/null | jq -r '.valid[]?.Name' | grep -E "(ramen-hub|ramen-dr)" | wc -l || echo "0")
    else
        minikube_clusters=0
    fi
    
    # Determine primary cluster type
    if [[ $kind_clusters -ge 3 ]]; then
        export CLUSTER_TYPE="kind"
        export HUB_CONTEXT="kind-ramen-hub"
        export DR1_CONTEXT="kind-ramen-dr1" 
        export DR2_CONTEXT="kind-ramen-dr2"
        log_success "Detected kind clusters"
    elif [[ $minikube_clusters -ge 3 ]]; then
        export CLUSTER_TYPE="minikube"
        export HUB_CONTEXT="ramen-hub"
        export DR1_CONTEXT="ramen-dr1"
        export DR2_CONTEXT="ramen-dr2"
        log_success "Detected minikube clusters"
    else
        log_warning "No complete RamenDR cluster setup detected"
        log_info "Available contexts:"
        kubectl config get-contexts | grep -E "(ramen|kind)" || echo "  No ramen-related contexts found"
        
        # Let user choose
        echo ""
        echo "Please select your cluster type:"
        echo "  1) kind (contexts: kind-ramen-hub, kind-ramen-dr1, kind-ramen-dr2)"
        echo "  2) minikube (contexts: ramen-hub, ramen-dr1, ramen-dr2)" 
        echo "  3) custom (specify your own context names)"
        read -p "Enter choice (1-3): " choice
        
        case $choice in
            1)
                export CLUSTER_TYPE="kind"
                export HUB_CONTEXT="kind-ramen-hub"
                export DR1_CONTEXT="kind-ramen-dr1"
                export DR2_CONTEXT="kind-ramen-dr2"
                ;;
            2)
                export CLUSTER_TYPE="minikube" 
                export HUB_CONTEXT="ramen-hub"
                export DR1_CONTEXT="ramen-dr1"
                export DR2_CONTEXT="ramen-dr2"
                ;;
            3)
                read -p "Hub cluster context: " HUB_CONTEXT
                read -p "DR1 cluster context: " DR1_CONTEXT
                read -p "DR2 cluster context: " DR2_CONTEXT
                export CLUSTER_TYPE="custom"
                ;;
            *)
                log_error "Invalid choice"
                return 1
                ;;
        esac
    fi
    
    # Export contexts for other scripts
    export HUB_CONTEXT DR1_CONTEXT DR2_CONTEXT CLUSTER_TYPE
    
    log_info "Cluster configuration:"
    echo "  Type: $CLUSTER_TYPE"
    echo "  Hub: $HUB_CONTEXT"
    echo "  DR1: $DR1_CONTEXT" 
    echo "  DR2: $DR2_CONTEXT"
}

# Verify contexts exist
verify_contexts() {
    local contexts=("$HUB_CONTEXT" "$DR1_CONTEXT" "$DR2_CONTEXT")
    local missing_contexts=()
    
    for context in "${contexts[@]}"; do
        if ! kubectl config get-contexts "$context" >/dev/null 2>&1; then
            missing_contexts+=("$context")
        fi
    done
    
    if [[ ${#missing_contexts[@]} -gt 0 ]]; then
        log_error "Missing contexts: ${missing_contexts[*]}"
        log_info "Available contexts:"
        kubectl config get-contexts
        log_info "Run cluster setup first:"
        echo "  For kind: ./scripts/setup.sh kind"
        echo "  For minikube: ./examples/setup-minikube.sh"
        return 1
    fi
    
    log_success "All required contexts found"
}

# Get service access method based on cluster type
get_service_access() {
    local service_name=$1
    local namespace=${2:-default}
    local port=${3:-80}
    
    case $CLUSTER_TYPE in
        kind)
            echo "kubectl port-forward -n $namespace service/$service_name $port:$port"
            ;;
        minikube)
            # Minikube can use service command or port-forward
            echo "minikube service $service_name -n $namespace --url"
            echo "# Or use: kubectl port-forward -n $namespace service/$service_name $port:$port"
            ;;
        *)
            echo "kubectl port-forward -n $namespace service/$service_name $port:$port"
            ;;
    esac
}

# Export configuration if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    detect_cluster_type
    verify_contexts
    log_success "Cluster configuration loaded. Use \$HUB_CONTEXT, \$DR1_CONTEXT, \$DR2_CONTEXT"
else
    # If run directly, show configuration
    detect_cluster_type
    verify_contexts
    
    echo ""
    log_info "To use this configuration in other scripts:"
    echo "  source examples/cluster-config.sh"
    echo "  kubectl config use-context \$HUB_CONTEXT"
    echo ""
    log_info "Service access examples:"
    echo "  MinIO: $(get_service_access minio minio-system 9001)"
fi
