#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Cross-Cluster S3 Setup for RamenDR Demo
# This script configures MinIO for cross-cluster access.
# It should be run AFTER RamenDR operators are installed on DR clusters.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

log_info "🌐 Setting up cross-cluster S3 access for RamenDR demo"
echo "============================================================"
echo ""

# Check if this script should run now or be deferred
check_prerequisites() {
    log_info "🔍 Checking prerequisites..."
    
    # Check if DR operators are installed
    local dr1_ready=false
    local dr2_ready=false
    
    if kubectl config get-contexts | grep -q "kind-ramen-dr1"; then
        kubectl config use-context kind-ramen-dr1 >/dev/null 2>&1
        if kubectl get namespace ramen-system >/dev/null 2>&1; then
            dr1_ready=true
        fi
    fi
    
    if kubectl config get-contexts | grep -q "kind-ramen-dr2"; then
        kubectl config use-context kind-ramen-dr2 >/dev/null 2>&1
        if kubectl get namespace ramen-system >/dev/null 2>&1; then
            dr2_ready=true
        fi
    fi
    
    if [[ "$dr1_ready" == false ]] || [[ "$dr2_ready" == false ]]; then
        log_warning "RamenDR operators not installed on DR clusters yet"
        log_info "This script will only expose MinIO via NodePort for now"
        log_info "Run this script again after installing RamenDR operators"
        return 1
    fi
    
    log_success "Prerequisites met - DR operators found on both clusters"
    return 0
}

# Function to expose MinIO via NodePort
expose_minio_nodeport() {
    log_info "🔧 Exposing MinIO via NodePort for cross-cluster access..."
    
    # Switch to hub cluster where MinIO is running
    kubectl config use-context kind-ramen-hub >/dev/null 2>&1 || {
        log_error "Failed to switch to hub cluster context"
        return 1
    }
    
    # Check if MinIO service exists
    if ! kubectl get svc minio -n minio-system >/dev/null 2>&1; then
        log_error "MinIO service not found. Please run deploy-ramendr-s3.sh first."
        return 1
    fi
    
    # Patch MinIO service to use NodePort
    kubectl patch svc minio -n minio-system --patch='{
        "spec": {
            "type": "NodePort",
            "ports": [
                {
                    "name": "minio",
                    "port": 9000,
                    "targetPort": 9000,
                    "nodePort": 30900
                },
                {
                    "name": "console", 
                    "port": 9001,
                    "targetPort": 9001,
                    "nodePort": 30901
                }
            ]
        }
    }'
    
    log_success "MinIO exposed via NodePort 30900 (API) and 30901 (Console)"
}

# Function to get hub cluster external IP
get_hub_cluster_ip() {
    kubectl config use-context kind-ramen-hub >/dev/null 2>&1
    
    # Get the hub cluster node IP
    local hub_ip
    hub_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    
    if [[ -z "$hub_ip" ]]; then
        return 1
    fi
    
    echo "$hub_ip"
}

# Function to update S3 endpoint for cross-cluster access
update_s3_endpoint_for_cluster() {
    local cluster_context="$1"
    local hub_ip="$2"
    
    log_info "📝 Updating S3 endpoint for cluster: $cluster_context"
    
    kubectl config use-context "$cluster_context" >/dev/null 2>&1 || {
        log_warning "Could not switch to $cluster_context - skipping"
        return 0
    }
    
    # Check if ramen-dr-cluster-operator-config exists
    if ! kubectl get configmap ramen-dr-cluster-operator-config -n ramen-system >/dev/null 2>&1; then
        log_warning "RamenDR operator config not found on $cluster_context - skipping"
        return 0
    fi
    
    # Update the ConfigMap with external S3 endpoint
    kubectl patch configmap ramen-dr-cluster-operator-config -n ramen-system --patch="
data:
  ramen_manager_config.yaml: |
    apiVersion: ramendr.openshift.io/v1alpha1
    kind: RamenConfig
    health:
      healthProbeBindAddress: :8081
    metrics:
      bindAddress: 127.0.0.1:9289
    webhook:
      port: 9443
    leaderElection:
      leaderElect: true
      resourceName: dr-cluster.ramendr.openshift.io
    ramenControllerType: dr-cluster
    maxConcurrentReconciles: 50
    volSync:
      destinationCopyMethod: Direct
    volumeUnprotectionEnabled: true
    ramenOpsNamespace: ramen-ops
    multiNamespace:
      FeatureEnabled: true
      volsyncSupported: true
    kubeObjectProtection:
      veleroNamespaceName: velero
    s3StoreProfiles:
    - s3ProfileName: minio-s3
      s3Bucket: ramen-metadata
      s3Region: us-east-1
      s3CompatibleEndpoint: http://${hub_ip}:30900
      s3SecretRef:
        name: ramen-s3-secret
        namespace: ramen-system
    drClusterOperator:
      deploymentAutomationEnabled: true"
    
    log_success "Updated S3 endpoint to http://${hub_ip}:30900 for $cluster_context"
}

# Function to copy S3 secret to DR clusters
copy_s3_secret_to_clusters() {
    local hub_ip="$1"
    
    log_info "🔑 Copying S3 secret to DR clusters..."
    
    # Export secret from hub cluster
    kubectl config use-context kind-ramen-hub >/dev/null 2>&1
    
    if ! kubectl get secret ramen-s3-secret -n ramen-system >/dev/null 2>&1; then
        log_error "S3 secret not found on hub cluster"
        return 1
    fi
    
    # Export the secret
    kubectl get secret ramen-s3-secret -n ramen-system -o yaml > /tmp/s3-secret.yaml
    
    # Apply to DR clusters
    for cluster in kind-ramen-dr1 kind-ramen-dr2; do
        if kubectl config get-contexts | grep -q "$cluster"; then
            log_info "Copying S3 secret to $cluster..."
            kubectl config use-context "$cluster" >/dev/null 2>&1
            kubectl apply -f /tmp/s3-secret.yaml || log_warning "Failed to copy secret to $cluster"
        else
            log_warning "Cluster $cluster not found - skipping"
        fi
    done
    
    # Clean up temp file
    rm -f /tmp/s3-secret.yaml
    
    log_success "S3 secret copied to DR clusters"
}

# Function to restart operators to pick up new config
restart_operators() {
    log_info "🔄 Restarting DR cluster operators to pick up new S3 configuration..."
    
    for cluster in kind-ramen-dr1 kind-ramen-dr2; do
        if kubectl config get-contexts | grep -q "$cluster"; then
            log_info "Restarting operator on $cluster..."
            kubectl config use-context "$cluster" >/dev/null 2>&1
            kubectl rollout restart deployment/ramen-dr-cluster-operator -n ramen-system 2>/dev/null || \
                log_warning "Failed to restart operator on $cluster (might not be installed)"
        fi
    done
    
    log_success "Operator restarts initiated"
}

# Function to verify cross-cluster connectivity
verify_connectivity() {
    local hub_ip="$1"
    
    log_info "🧪 Verifying cross-cluster S3 connectivity..."
    
    for cluster in kind-ramen-dr1 kind-ramen-dr2; do
        if kubectl config get-contexts | grep -q "$cluster"; then
            log_info "Testing connectivity from $cluster to MinIO..."
            kubectl config use-context "$cluster" >/dev/null 2>&1
            
            # Test HTTP connectivity
            if kubectl run test-minio-connectivity-$$ --image=busybox --rm -i --restart=Never \
                -- wget -qO- --timeout=5 "http://${hub_ip}:30900" >/dev/null 2>&1; then
                log_success "✅ $cluster can reach MinIO at http://${hub_ip}:30900"
            else
                log_warning "⚠️  $cluster cannot reach MinIO (expected for new clusters)"
            fi
        fi
    done
}

# Main execution
main() {
    log_info "Configuring cross-cluster S3 access for kind clusters..."
    
    # Check prerequisites first
    local full_setup=true
    if ! check_prerequisites; then
        full_setup=false
    fi
    
    # Step 1: Always expose MinIO via NodePort (this is safe to do early)
    expose_minio_nodeport
    
    # Step 2: Get hub cluster IP
    log_info "🔍 Getting hub cluster external IP..."
    local hub_ip
    hub_ip=$(get_hub_cluster_ip)
    
    if [[ -z "$hub_ip" ]]; then
        log_error "Could not determine hub cluster IP"
        exit 1
    fi
    log_success "Hub cluster IP: $hub_ip"
    
    if [[ "$full_setup" == true ]]; then
        # Step 3: Update S3 endpoints on DR clusters
        update_s3_endpoint_for_cluster "kind-ramen-dr1" "$hub_ip"
        update_s3_endpoint_for_cluster "kind-ramen-dr2" "$hub_ip"
        
        # Step 4: Copy S3 secret to DR clusters
        copy_s3_secret_to_clusters "$hub_ip"
        
        # Step 5: Restart operators
        restart_operators
        
        # Step 6: Verify connectivity
        verify_connectivity "$hub_ip"
        
        log_success "✅ Full cross-cluster S3 setup completed!"
        echo ""
        echo "📝 Next steps:"
        echo "   1. Wait ~30 seconds for operators to restart"
        echo "   2. Create VRGs on DR clusters for cross-cluster replication"
        echo "   3. Monitor S3 bucket for backup data"
    else
        log_success "✅ MinIO NodePort exposure completed!"
        echo ""
        echo "📝 Partial setup complete:"
        echo "   • MinIO is now accessible from DR clusters via NodePort"
        echo "   • Run this script again after installing RamenDR operators"
    fi
    
    # Final summary
    kubectl config use-context kind-ramen-hub >/dev/null 2>&1
    echo ""
    echo "📝 Configuration Summary:"
    echo "   • MinIO Hub Cluster: kind-ramen-hub"
    echo "   • MinIO External Access: http://${hub_ip}:30900 (API)"
    echo "   • MinIO Console: http://${hub_ip}:30901 (Web UI)"
    echo "   • S3 Bucket: ramen-metadata"
    echo ""
}

# Check if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
