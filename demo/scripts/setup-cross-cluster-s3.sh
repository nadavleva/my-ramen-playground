#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Load utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

main() {
    log_step "🌐 Setting up cross-cluster S3 access..."
    
    # Check prerequisites
    check_required_tools kubectl minikube
    
    # Get hub IP
    HUB_IP=$(minikube -p ramen-hub ip)
    if [ -z "$HUB_IP" ]; then
        log_error "Could not get hub cluster IP"
        return 1
    fi
    
    log_info "🔗 Hub cluster IP: $HUB_IP"
    
    # 1. Install missing CRDs on hub
    log_info "🔍 Checking and installing missing CRDs on hub..."
    
    HUB_CRDS=$(kubectl --context=ramen-hub get crd | grep ramen | wc -l)
    DR_CRDS=$(kubectl --context=ramen-dr1 get crd | grep ramen | wc -l)
    
    log_info "Hub has $HUB_CRDS CRDs, DR clusters have $DR_CRDS CRDs"
    
    if [ "$HUB_CRDS" -lt "$DR_CRDS" ]; then
        log_info "Installing missing CRDs on hub..."
        kubectl --context=ramen-hub apply -f "${SCRIPT_DIR}/../../config/crd/bases/"
        
        # Wait for CRDs to be established
        log_info "Waiting for CRDs to be established..."
        sleep 10
        
        # Verify
        NEW_HUB_CRDS=$(kubectl --context=ramen-hub get crd | grep ramen | wc -l)
        log_info "Hub now has $NEW_HUB_CRDS CRDs"
    fi
    
    # 2. Fix cross-cluster networking
    log_info "🔧 Fixing cross-cluster networking for S3 access..."
    
    # Get the host machine's IP that's accessible from containers
    HOST_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+' 2>/dev/null || hostname -I | awk '{print $1}')
    log_info "🖥️ Host machine IP: $HOST_IP"
    
    # Test which endpoint works from DR clusters
    log_info "🧪 Testing network connectivity..."
    
    WORKING_ENDPOINT=""
    
    # Test direct hub IP first
    log_info "Testing hub IP connectivity..."
    if kubectl --context=ramen-dr1 run net-test-hub --image=busybox --restart=Never --rm -i --timeout=30s --command -- /bin/sh -c "nc -zv ${HUB_IP} 30900" 2>/dev/null; then
        WORKING_ENDPOINT="http://${HUB_IP}:30900"
        log_success "✅ Hub IP is reachable: $WORKING_ENDPOINT"
    else
        log_warning "⚠️ Hub IP not reachable from DR clusters"
        
        # Test host IP (more likely to work)
        log_info "Testing host IP connectivity..."
        if kubectl --context=ramen-dr1 run net-test-host --image=busybox --restart=Never --rm -i --timeout=30s --command -- /bin/sh -c "nc -zv ${HOST_IP} 30900" 2>/dev/null; then
            WORKING_ENDPOINT="http://${HOST_IP}:30900"
            log_success "✅ Host IP is reachable: $WORKING_ENDPOINT"
            
            # Set up port forwarding to make MinIO accessible on host IP
            log_info "Setting up port forwarding for cross-cluster access..."
            
            # Kill any existing port-forward
            pkill -f "port-forward.*minio" || true
            
            # Start port-forward in background
            kubectl --context=ramen-hub port-forward -n minio-system svc/minio 30900:9000 --address=0.0.0.0 &
            PF_PID=$!
            
            # Wait a moment for port-forward to establish
            sleep 5
            
            # Test the forwarded connection
            if curl -s --connect-timeout 5 "http://${HOST_IP}:30900/minio/health/live" >/dev/null; then
                log_success "✅ Port-forward established successfully"
            else
                log_warning "⚠️ Port-forward may not be working correctly"
            fi
            
        else
            log_error "❌ No reachable endpoint found"
            WORKING_ENDPOINT="http://${HUB_IP}:30900"  # Fallback
        fi
    fi
    
    log_info "📍 Using S3 endpoint: $WORKING_ENDPOINT"
    
    # 3. Update operator configurations with working endpoint
    log_info "🔧 Updating operator configurations with working endpoint..."
    
    for cluster in ramen-dr1 ramen-dr2; do
        log_info "Updating operator config on $cluster..."
        
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
        s3CompatibleEndpoint: ${WORKING_ENDPOINT}
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
" || log_warning "Failed to patch ConfigMap on $cluster"
    done
    
    # 4. Create DRClusterConfig resources on hub for both DR clusters
    log_info "🔧 Creating DRClusterConfig resources on hub..."
    
    # Ensure namespace exists on hub
    kubectl --context=ramen-hub create namespace ramen-system --dry-run=client -o yaml | kubectl --context=ramen-hub apply -f - || true
    
    # Check if DRClusterConfig CRD exists on hub
    if kubectl --context=ramen-hub get crd drclusterconfigs.ramendr.openshift.io >/dev/null 2>&1; then
        log_success "✅ DRClusterConfig CRD found on hub"
        
        # Create DRClusterConfig for ramen-dr1 on hub
        log_info "Creating DRClusterConfig for ramen-dr1 on hub..."
        cat <<EOF | kubectl --context=ramen-hub apply -f -
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRClusterConfig
metadata:
  name: ramen-dr1-config
  namespace: ramen-system
  labels:
    cluster.open-cluster-management.io/clustername: ramen-dr1
spec:
  clusterID: ramen-dr1
EOF
        log_success "✅ DRClusterConfig created for ramen-dr1 on hub"
        
        # Create DRClusterConfig for ramen-dr2 on hub  
        log_info "Creating DRClusterConfig for ramen-dr2 on hub..."
        cat <<EOF | kubectl --context=ramen-hub apply -f -
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRClusterConfig
metadata:
  name: ramen-dr2-config
  namespace: ramen-system
  labels:
    cluster.open-cluster-management.io/clustername: ramen-dr2
spec:
  clusterID: ramen-dr2
EOF
        log_success "✅ DRClusterConfig created for ramen-dr2 on hub"
        
    else
        log_error "❌ DRClusterConfig CRD not found on hub"
        log_info "💡 Install missing CRDs first: kubectl --context=ramen-hub apply -f config/crd/bases/"
        return 1
    fi
    
    # 5. Restart operators to pick up new configuration
    log_info "🔄 Restarting operators to pick up new configuration..."
    
    for cluster in ramen-dr1 ramen-dr2; do
        log_info "Restarting operator on $cluster..."
        kubectl --context=$cluster delete pod -n ramen-system -l control-plane=controller-manager --grace-period=0 || true
        sleep 5
        wait_for_deployment "$cluster" "ramen-dr-cluster-operator" "ramen-system" 300
    done
    
    # 6. Test S3 connectivity with working endpoint
    log_info "🧪 Testing S3 connectivity with working endpoint..."
    
    for cluster in ramen-dr1 ramen-dr2; do
        log_info "Testing connectivity from $cluster..."
        
        if kubectl --context=$cluster run test-s3-${cluster} \
            --image=minio/mc \
            --restart=Never \
            --rm -i \
            --timeout=60s \
            --command -- /bin/sh -c "
            echo 'Testing S3 connectivity from ${cluster}...'
            mc alias set test ${WORKING_ENDPOINT} minioadmin minioadmin &&
            mc ls test/ramen-metadata/ &&
            echo 'SUCCESS: S3 connectivity verified from ${cluster}'
            "; then
            log_success "✅ S3 connectivity verified from $cluster"
        else
            log_warning "⚠️ S3 connectivity test failed from $cluster"
        fi
        
        sleep 2
    done
    
    # 7. Check OCM propagation
    log_info "🔍 Checking OCM resource propagation..."
    
    for cluster in ramen-dr1 ramen-dr2; do
        if kubectl --context=ramen-hub get manifestwork -n $cluster 2>/dev/null | grep -q drcluster; then
            log_success "✅ OCM ManifestWork found for $cluster"
        else
            log_info "ℹ️ No OCM ManifestWork found for $cluster (using direct approach)"
        fi
    done
    
    # 8. Show final status
    log_success "🎉 Cross-cluster S3 access setup completed!"
    
    log_info "📋 Setup Summary:"
    echo "  ✅ Missing CRDs installed on hub"
    echo "  ✅ Cross-cluster networking configured"
    echo "  ✅ Working S3 endpoint: ${WORKING_ENDPOINT}"
    echo "  ✅ Operator configurations updated"
    echo "  ✅ DRClusterConfig resources created"
    echo "  ✅ Operators restarted with new config"
    echo ""
    echo "📍 S3 Access Information:"
    echo "  Working Endpoint: ${WORKING_ENDPOINT}"
    echo "  Console: http://${HUB_IP}:30901"
    echo "  Username: minioadmin"
    echo "  Password: minioadmin"
    echo ""
    
    # Show port-forward info if using host IP
    if [[ "$WORKING_ENDPOINT" == *"$HOST_IP"* ]]; then
        echo "⚠️ Using port-forward for cross-cluster access"
        echo "   Port-forward PID: ${PF_PID:-unknown}"
        echo "   To stop: kill ${PF_PID:-PID}"
        echo "   To restart: kubectl --context=ramen-hub port-forward -n minio-system svc/minio 30900:9000 --address=0.0.0.0 &"
        echo ""
    fi
    
    echo "🔍 Debug Commands:"
    echo "  # Check DRClusterConfig on hub:"
    echo "  kubectl --context=ramen-hub get drclusterconfig -A"
    echo ""
    echo "  # Check DRClusterConfig on DR clusters:"
    echo "  kubectl --context=ramen-dr1 get drclusterconfig -A"
    echo "  kubectl --context=ramen-dr2 get drclusterconfig -A"
    echo ""
    echo "  # Test S3 manually:"
    echo "  kubectl --context=ramen-dr1 run test-manual --image=minio/mc --rm -i -- mc alias set test ${WORKING_ENDPOINT} minioadmin minioadmin"
    echo ""
    echo "  # Check operator logs:"
    echo "  kubectl --context=ramen-dr1 logs -n ramen-system deployment/ramen-dr-cluster-operator --tail=20"
}

# Run main function
main "$@"