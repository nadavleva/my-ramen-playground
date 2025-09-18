#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Load utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

main() {
    log_step "🚀 Deploying RamenDR S3 Storage..."
    
    # Check prerequisites
    check_required_tools kubectl minikube
    
    # Get hub IP first
    HUB_IP=$(minikube -p ramen-hub ip)
    if [ -z "$HUB_IP" ]; then
        log_error "Could not get hub cluster IP"
        exit 1
    fi
    log_info "📍 Hub cluster IP: $HUB_IP"

    # Check if cross-cluster networking works, if not set up port forwarding
    log_info "🔍 Testing cross-cluster networking..."
    if ! kubectl --context=ramen-dr1 run test-network --image=busybox --rm -i --restart=Never --timeout=30s -- ping -c 1 "$HUB_IP" >/dev/null 2>&1; then
        log_warning "⚠️ Cross-cluster networking not working, setting up port forwarding..."
        
        # Get host IP
        HOST_IP=$(hostname -I | awk '{print $1}')
        log_info "🖥️ Host IP: $HOST_IP"
        
        # Kill any existing port forwards
        pkill -f "kubectl.*port-forward.*minio" || true
        sleep 2
        
        # Start port forward
        log_info "🔗 Starting port forward..."
        kubectl --context=ramen-hub port-forward -n minio-system svc/minio 30900:9000 --address=0.0.0.0 &
        PORT_FORWARD_PID=$!
        log_info "🔗 Port forward started (PID: $PORT_FORWARD_PID)"
        
        # Wait for port forward to establish
        sleep 10
        
        # Test port forward
        if curl -s --connect-timeout 5 "http://$HOST_IP:30900/minio/health/live" >/dev/null; then
            log_success "✅ Port forward working, using host IP endpoint"
            # Update the endpoint to use host IP
            HUB_IP="$HOST_IP"
        else
            log_warning "⚠️ Port forward failed, using original endpoint"
        fi
    else
        log_success "✅ Cross-cluster networking working"
    fi
    
    # 1. Deploy MinIO on hub cluster
    log_info "📦 Step 1: Deploying MinIO on hub cluster..."
    ensure_namespace "ramen-hub" "minio-system" 60
    kubectl --context=ramen-hub apply -f "${SCRIPT_DIR}/../yaml/minio-deployment/minio-s3.yaml"
    
    # Wait for MinIO to be ready
    log_info "⏳ Waiting for MinIO deployment..."
    wait_for_deployment "ramen-hub" "minio" "minio-system" 300
    
    # 2. Create MinIO bucket using direct pod execution
    log_info "🪣 Step 2: Creating ramen-metadata bucket..."
    
    # Wait a bit for MinIO to be fully ready
    sleep 10
    
    # Create bucket using a job instead of port-forward
    kubectl --context=ramen-hub run minio-bucket-creator \
        --image=minio/mc \
        --restart=Never \
        --rm -i \
        --timeout=120s \
        --command -- /bin/sh -c "
        echo 'Configuring MinIO client...'
        mc alias set minio http://${HUB_IP}:30900 minioadmin minioadmin
        echo 'Creating bucket...'
        mc mb minio/ramen-metadata || echo 'Bucket may already exist'
        echo 'Verifying bucket...'
        mc ls minio/
        echo 'Bucket creation completed!'
        " || log_warning "Bucket creation may have failed, continuing..."
    
    # 3. Create S3 secrets on DR clusters
    log_info "🔐 Step 3: Creating S3 secrets on DR clusters..."
    for cluster in ramen-dr1 ramen-dr2; do
        log_info "Creating S3 secret on $cluster..."
        
        # Use the existing s3-secret.yaml but with updated endpoint
        sed "s|MINIO_ENDPOINT|http://${HUB_IP}:30900|g" "${SCRIPT_DIR}/../yaml/s3-config/s3-secret.yaml" | \
        kubectl --context=$cluster apply -f -
    done
    
    # 4. Apply S3 profiles (skip RamenConfig and dr_cluster_config.yaml)
    log_info "🔧 Step 4: Applying S3 profiles on DR clusters..."
    for cluster in ramen-dr1 ramen-dr2; do
        log_info "Applying S3 profiles on $cluster..."
        
        # Apply existing config files with endpoint substitution
        sed "s|MINIO_ENDPOINT|http://${HUB_IP}:30900|g" "${SCRIPT_DIR}/../yaml/s3-config/s3-profiles.yaml" | \
        kubectl --context=$cluster apply -f -
        
        # Skip ramenconfig.yaml and dr_cluster_config.yaml since RamenConfig CRD doesn't exist
        log_info "Skipping RamenConfig resources (CRD not available)"
    done
    
    # 5. Update operator ConfigMaps with S3 configuration
    log_info "🔧 Step 5: Updating operator configurations..."
    for cluster in ramen-dr1 ramen-dr2; do
        log_info "Updating operator config on $cluster..."
        
        # Check if the ConfigMap exists first
        if kubectl --context=$cluster get configmap ramen-dr-cluster-operator-config -n ramen-system >/dev/null 2>&1; then
            # Update the operator ConfigMap with S3 settings
            kubectl --context=$cluster patch configmap ramen-dr-cluster-operator-config -n ramen-system --patch "
data:
  ramen_manager_config.yaml: |
    ramenControllerType: dr-cluster
    maxConcurrentReconciles: 50
    drClusterOperator:
      deploymentAutomationEnabled: true
      s3StoreProfiles:
      - s3ProfileName: minio-s3
        s3Bucket: ramen-metadata
        s3Region: us-east-1
        s3CompatibleEndpoint: http://${HUB_IP}:30900
        s3SecretRef:
          name: ramen-s3-secret
          namespace: ramen-system
    health:
      healthProbeBindAddress: :8081
    metrics:
      bindAddress: 127.0.0.1:9289
    webhook:
      port: 9443
    leaderElection:
      leaderElect: false
      resourceName: dr-cluster.ramendr.openshift.io
" || log_warning "ConfigMap patch may have failed on $cluster"
        else
            # Create the ConfigMap if it doesn't exist
            log_info "Creating operator ConfigMap on $cluster..."
            cat <<EOF | kubectl --context=$cluster apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ramen-dr-cluster-operator-config
  namespace: ramen-system
data:
  ramen_manager_config.yaml: |
    ramenControllerType: dr-cluster
    maxConcurrentReconciles: 50
    drClusterOperator:
      deploymentAutomationEnabled: true
      s3StoreProfiles:
      - s3ProfileName: minio-s3
        s3Bucket: ramen-metadata
        s3Region: us-east-1
        s3CompatibleEndpoint: http://${HUB_IP}:30900
        s3SecretRef:
          name: ramen-s3-secret
          namespace: ramen-system
    health:
      healthProbeBindAddress: :8081
    metrics:
      bindAddress: 127.0.0.1:9289
    webhook:
      port: 9443
    leaderElection:
      leaderElect: false
      resourceName: dr-cluster.ramendr.openshift.io
EOF
        fi
    done
    
    # 6. Restart DR operators to pick up new configuration
    log_info "🔄 Step 6: Restarting DR operators..."
    for cluster in ramen-dr1 ramen-dr2; do
        log_info "Restarting operator on $cluster..."
        kubectl --context=$cluster delete pod -n ramen-system -l control-plane=controller-manager --grace-period=0 || true
        sleep 5
        wait_for_deployment "$cluster" "ramen-dr-cluster-operator" "ramen-system" 300
    done
    
    # 7. Verify setup
    log_info "🔍 Step 7: Verifying S3 setup..."
    
    # Check MinIO is running
    if kubectl --context=ramen-hub get pod -n minio-system -l app=minio | grep -q Running; then
        log_success "✅ MinIO is running on hub"
    else
        log_error "❌ MinIO is not running"
        kubectl --context=ramen-hub get pods -n minio-system
        exit 1
    fi
    
    # Check S3 secrets exist (use correct secret name from the YAML files)
    for cluster in ramen-dr1 ramen-dr2; do
        if kubectl --context=$cluster get secret ramen-s3-secret -n ramen-system >/dev/null 2>&1; then
            log_success "✅ S3 secret exists on $cluster"
        else
            log_error "❌ S3 secret missing on $cluster"
            exit 1
        fi
    done
    
    # Check ConfigMap was updated
    for cluster in ramen-dr1 ramen-dr2; do
        if kubectl --context=$cluster get configmap ramen-dr-cluster-operator-config -n ramen-system >/dev/null 2>&1; then
            log_success "✅ Operator ConfigMap exists on $cluster"
        else
            log_warning "⚠️ Operator ConfigMap missing on $cluster"
        fi
    done
    
    # Check operator logs for S3 connection
    log_info "🔍 Checking operator logs for S3 connectivity..."
    for cluster in ramen-dr1 ramen-dr2; do
        log_info "Checking $cluster operator logs..."
        kubectl --context=$cluster logs -n ramen-system deployment/ramen-dr-cluster-operator --tail=10 | grep -i "s3\|minio\|config\|error" || true
        echo ""
    done
    
    log_success "🎉 S3 storage deployment completed successfully!"
    
    # Show connection info
    # Show connection info
    log_info "📋 Connection Information:"
    echo "  MinIO Console: http://${HUB_IP}:30901"
    echo "  MinIO API: http://${HUB_IP}:30900"
    echo "  Username: minioadmin"
    echo "  Password: minioadmin"
    echo "  Bucket: ramen-metadata"
    echo "  Secret name: ramen-s3-secret"
    echo ""
    echo "To access MinIO console:"
    echo "  minikube -p ramen-hub service minio -n minio-system"
    echo "  or open http://${HUB_IP}:30901 in browser"
    echo ""
    echo "To test S3 connectivity:"
    echo "  kubectl --context=ramen-dr1 run test-s3 --image=minio/mc --rm -i --restart=Never -- /bin/sh -c \"mc alias set test http://${HUB_IP}:30900 minioadmin minioadmin\""
    echo ""
    echo "To check operator configuration:"
    echo "  kubectl --context=ramen-dr1 get configmap ramen-dr-cluster-operator-config -n ramen-system -o yaml"
    echo ""
    echo "To verify bucket access:"
    echo "  kubectl --context=ramen-dr1 run verify-bucket --image=minio/mc --rm -i --restart=Never -- /bin/sh -c \"mc alias set minio http://${HUB_IP}:30900 minioadmin minioadmin && mc ls minio/ramen-metadata/\""
}

# Run main function
main "$@"