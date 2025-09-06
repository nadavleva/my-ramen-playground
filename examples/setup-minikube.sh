#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Minikube Setup for RamenDR
# Creates 3 minikube clusters optimized for RamenDR testing

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

# Configuration
CLUSTERS=("ramen-hub" "ramen-dr1" "ramen-dr2")
DRIVER="${MINIKUBE_DRIVER:-docker}"

# Resource allocation
declare -A CLUSTER_RESOURCES
CLUSTER_RESOURCES[ramen-hub]="--cpus=1 --memory=1536 --disk-size=10g"
CLUSTER_RESOURCES[ramen-dr1]="--cpus=2 --memory=2560 --disk-size=20g"  
CLUSTER_RESOURCES[ramen-dr2]="--cpus=2 --memory=2560 --disk-size=20g"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v minikube >/dev/null 2>&1; then
        log_error "minikube not found. Please install minikube first."
        echo "  macOS: brew install minikube"
        echo "  Linux: curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && sudo install minikube-linux-amd64 /usr/local/bin/minikube"
        exit 1
    fi
    
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    
    # Check Docker if using docker driver
    if [[ "$DRIVER" == "docker" ]] && ! docker ps >/dev/null 2>&1; then
        log_error "Docker not running or accessible. Please start Docker."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Clean up existing clusters
cleanup_existing() {
    log_info "Checking for existing RamenDR minikube clusters..."
    
    local existing_clusters
    existing_clusters=$(minikube profile list -o json 2>/dev/null | jq -r '.valid[]?.Name' | grep -E "ramen-" || echo "")
    
    if [[ -n "$existing_clusters" ]]; then
        log_warning "Found existing RamenDR clusters:"
        echo "$existing_clusters"
        echo ""
        read -p "Delete existing clusters? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$existing_clusters" | while read -r cluster; do
                if [[ -n "$cluster" ]]; then
                    log_info "Deleting cluster: $cluster"
                    minikube delete -p "$cluster"
                fi
            done
        else
            log_warning "Keeping existing clusters - this may cause conflicts"
        fi
    fi
}

# Create minikube cluster
create_cluster() {
    local cluster_name=$1
    local resources=${CLUSTER_RESOURCES[$cluster_name]}
    
    log_info "Creating minikube cluster: $cluster_name"
    echo "  Resources: $resources"
    echo "  Driver: $DRIVER"
    
    # Start cluster with retry logic
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt/$max_attempts for $cluster_name"
        
        if minikube start -p "$cluster_name" \
            --driver="$DRIVER" \
            --container-runtime=containerd \
            $resources \
            --kubernetes-version=stable \
            --extra-config=apiserver.service-account-signing-key-file=/var/lib/minikube/certs/sa.key \
            --extra-config=apiserver.service-account-key-file=/var/lib/minikube/certs/sa.pub \
            --extra-config=apiserver.service-account-issuer=api \
            --extra-config=apiserver.service-account-api-audiences=api,spire-server; then
            log_success "Created cluster: $cluster_name"
            return 0
        else
            log_warning "Attempt $attempt failed for $cluster_name"
            ((attempt++))
            if [[ $attempt -le $max_attempts ]]; then
                log_info "Retrying in 10 seconds..."
                sleep 10
            fi
        fi
    done
    
    log_error "Failed to create cluster: $cluster_name after $max_attempts attempts"
    return 1
}

# Enable required addons
enable_addons() {
    local cluster_name=$1
    
    log_info "Enabling addons for $cluster_name"
    
    # Enable basic addons
    minikube addons enable default-storageclass -p "$cluster_name"
    minikube addons enable storage-provisioner -p "$cluster_name"
    
    # Enable CSI addons for DR clusters (needed for storage replication)
    if [[ "$cluster_name" =~ dr[12] ]]; then
        log_info "Enabling storage addons for DR cluster: $cluster_name"
        minikube addons enable volumesnapshots -p "$cluster_name" || log_warning "volumesnapshots addon failed - may not be available"
        minikube addons enable csi-hostpath-driver -p "$cluster_name" || log_warning "csi-hostpath-driver addon failed - may not be available"
    fi
    
    # Wait for cluster to be ready
    log_info "Waiting for $cluster_name to be ready..."
    kubectl config use-context "$cluster_name"
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    log_success "Addons enabled for $cluster_name"
}

# Create storage classes optimized for RamenDR
create_storage_classes() {
    local cluster_name=$1
    
    log_info "Creating RamenDR storage classes for $cluster_name"
    
    kubectl config use-context "$cluster_name"
    
    # Create RamenDR-compatible storage class
    kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ramendr-csi-hostpath
  labels:
    ramendr.openshift.io/storageID: "minikube-${cluster_name}"
    ramendr.openshift.io/replicationID: "minikube-replication"
provisioner: k8s.io/minikube-hostpath
parameters:
  type: hostPath
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF

    # Create additional storage class for testing
    kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1  
kind: StorageClass
metadata:
  name: ramendr-standard
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
  labels:
    ramendr.openshift.io/storageID: "minikube-standard"
provisioner: k8s.io/minikube-hostpath
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF

    log_success "Storage classes created for $cluster_name"
}

# Verify cluster health
verify_cluster() {
    local cluster_name=$1
    
    log_info "Verifying cluster health: $cluster_name"
    
    kubectl config use-context "$cluster_name"
    
    # Check nodes
    if ! kubectl get nodes | grep -q Ready; then
        log_error "Cluster $cluster_name nodes not ready"
        return 1
    fi
    
    # Check system pods
    local pending_pods
    pending_pods=$(kubectl get pods -n kube-system --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
    if [[ $pending_pods -gt 0 ]]; then
        log_warning "Cluster $cluster_name has $pending_pods non-running system pods"
        kubectl get pods -n kube-system --field-selector=status.phase!=Running
    fi
    
    log_success "Cluster $cluster_name verification passed"
}

# Main setup function
setup_minikube_clusters() {
    echo "🎯 Minikube RamenDR Cluster Setup"
    echo "================================="
    echo ""
    echo "This will create 3 minikube clusters:"
    echo "  • ramen-hub  (1 CPU, 1.5GB RAM) - RamenDR hub"
    echo "  • ramen-dr1  (2 CPU, 2.5GB RAM) - DR cluster 1"  
    echo "  • ramen-dr2  (2 CPU, 2.5GB RAM) - DR cluster 2"
    echo ""
    echo "Total resources: 5 CPU, 6.5GB RAM, 50GB disk"
    echo ""
    
    read -p "Continue with setup? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled"
        exit 0
    fi
    
    check_prerequisites
    cleanup_existing
    
    # Create clusters
    for cluster in "${CLUSTERS[@]}"; do
        create_cluster "$cluster"
        enable_addons "$cluster"
        create_storage_classes "$cluster"
        verify_cluster "$cluster"
        echo ""
    done
    
    # Final verification
    log_info "Final verification of all clusters..."
    for cluster in "${CLUSTERS[@]}"; do
        kubectl config use-context "$cluster"
        log_info "$cluster: $(kubectl get nodes --no-headers | wc -l) nodes, $(kubectl get pods -A --field-selector=status.phase=Running --no-headers | wc -l) running pods"
    done
    
    echo ""
    log_success "🎉 Minikube cluster setup complete!"
    echo ""
    log_info "Next steps:"
    echo "  1. Install RamenDR operators: ./scripts/quick-install.sh"
    echo "  2. Run the demo: ./examples/ramendr-demo.sh"
    echo ""
    log_info "Cluster contexts:"
    echo "  Hub: ramen-hub"
    echo "  DR1: ramen-dr1"
    echo "  DR2: ramen-dr2"
    echo ""
    log_info "To delete clusters later:"
    echo "  minikube delete -p ramen-hub -p ramen-dr1 -p ramen-dr2"
}

# Service access helpers
show_service_access() {
    echo ""
    log_info "🌐 Service access with minikube:"
    echo ""
    echo "Option 1 - minikube service (opens browser):"
    echo "  minikube service minio -n minio-system -p ramen-hub"
    echo ""
    echo "Option 2 - minikube service URL only:"
    echo "  minikube service minio -n minio-system -p ramen-hub --url"
    echo ""
    echo "Option 3 - kubectl port-forward (works same as kind):"
    echo "  kubectl port-forward -n minio-system service/minio 9001:9001"
    echo ""
}

# Run setup if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_minikube_clusters
    show_service_access
fi
