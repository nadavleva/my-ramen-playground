#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# complete-minikube-demo.sh - Complete end-to-end minikube RamenDR demo
# This script addresses all common issues and provides a working demo

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

# Demo configuration
HUB_PROFILE="ramen-hub"
DR1_PROFILE="ramen-dr1"
DR2_PROFILE="ramen-dr2"  # Optional - will skip if creation fails

# Track what we have available
AVAILABLE_CLUSTERS=()

echo "🚀 RamenDR Complete minikube Demo"
echo "================================="
echo ""
echo "This demo will:"
echo "  ✅ Set up minikube clusters with CSI support"
echo "  ✅ Deploy RamenDR operators with all dependencies"  
echo "  ✅ Deploy MinIO S3 for metadata backup"
echo "  ✅ Create and protect an application with VRG"
echo "  ✅ Set up monitoring and browser access"
echo "  ✅ Handle all common dependency issues"
echo ""

# Function to check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check minikube
    if ! command -v minikube >/dev/null 2>&1; then
        log_error "minikube not found. Please install minikube first."
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    
    # Check docker/podman
    if ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
        log_error "Neither docker nor podman found. Please install a container runtime."
        exit 1
    fi
    
    # Check helm
    if ! command -v helm >/dev/null 2>&1; then
        log_warning "helm not found. Will install it if needed."
        # Install helm
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
    
    log_success "Prerequisites checked"
}

# Function to setup minikube clusters
setup_clusters() {
    log_step "Setting up minikube clusters..."
    
    # Clean up existing clusters first
    log_info "Cleaning up existing minikube profiles..."
    for profile in "$HUB_PROFILE" "$DR1_PROFILE" "$DR2_PROFILE"; do
        if minikube profile list 2>/dev/null | grep -q "^$profile"; then
            log_info "Deleting existing profile: $profile"
            minikube delete --profile="$profile" || true
        fi
    done
    
    # Create hub cluster
    log_info "Creating hub cluster ($HUB_PROFILE)..."
    minikube start \
        --profile="$HUB_PROFILE" \
        --driver=docker \
        --memory=4096 \
        --cpus=2 \
        --kubernetes-version=v1.27.3 \
        --addons=storage-provisioner,default-storageclass \
        --wait=true
    
    if [ $? -eq 0 ]; then
        AVAILABLE_CLUSTERS+=("$HUB_PROFILE")
        log_success "Hub cluster ready"
    else
        log_error "Failed to create hub cluster"
        exit 1
    fi
    
    # Create DR1 cluster
    log_info "Creating DR1 cluster ($DR1_PROFILE)..."
    minikube start \
        --profile="$DR1_PROFILE" \
        --driver=docker \
        --memory=4096 \
        --cpus=2 \
        --kubernetes-version=v1.27.3 \
        --addons=storage-provisioner,default-storageclass,volumesnapshots,csi-hostpath-driver \
        --wait=true
    
    if [ $? -eq 0 ]; then
        AVAILABLE_CLUSTERS+=("$DR1_PROFILE")
        log_success "DR1 cluster ready"
    else
        log_error "Failed to create DR1 cluster"
        exit 1
    fi
    
    # Try to create DR2 cluster (optional)
    log_info "Attempting to create DR2 cluster ($DR2_PROFILE) - optional..."
    if minikube start \
        --profile="$DR2_PROFILE" \
        --driver=docker \
        --memory=3072 \
        --cpus=2 \
        --kubernetes-version=v1.27.3 \
        --addons=storage-provisioner,default-storageclass,volumesnapshots,csi-hostpath-driver \
        --wait=true; then
        AVAILABLE_CLUSTERS+=("$DR2_PROFILE")
        log_success "DR2 cluster ready"
    else
        log_warning "DR2 cluster creation failed (common issue) - continuing with 2 clusters"
    fi
    
    # Setup kubeconfig contexts
    log_info "Setting up kubeconfig contexts..."
    mkdir -p ~/.kube
    for profile in "${AVAILABLE_CLUSTERS[@]}"; do
        minikube update-context --profile="$profile"
        log_info "Context updated for: $profile"
    done
    
    export KUBECONFIG=~/.kube/config
    log_success "Clusters setup completed - Available: ${AVAILABLE_CLUSTERS[*]}"
}

# Install all required dependencies and operators
install_ramendr() {
    log_step "Installing RamenDR operators and dependencies..."
    
    # Switch to hub cluster
    kubectl config use-context "$HUB_PROFILE"
    
    # Install all storage dependencies on hub
    log_info "Installing storage dependencies on hub cluster..."
    install_storage_dependencies_hub
    
    # Install missing resource classes on hub
    log_info "Installing missing resource classes on hub..."
    install_missing_resource_classes_hub
    
    # Install hub operator
    log_info "Installing RamenDR hub operator..."
    make install-hub
    make docker-build
    minikube image load quay.io/ramendr/ramen-operator:latest --profile="$HUB_PROFILE"
    make deploy-hub
    
    # Wait for hub operator
    kubectl wait --for=condition=available --timeout=180s deployment/ramen-hub-operator -n ramen-system
    log_success "Hub operator ready"
    
    # Install on DR clusters
    for profile in "${AVAILABLE_CLUSTERS[@]}"; do
        if [ "$profile" != "$HUB_PROFILE" ]; then
            log_info "Installing RamenDR cluster operator on $profile..."
            kubectl config use-context "$profile"
            
            # Install dependencies
            install_storage_dependencies_dr "$profile"
            install_missing_resource_classes_dr "$profile"
            
            # Install operator
            make install-dr-cluster
            minikube image load quay.io/ramendr/ramen-operator:latest --profile="$profile"
            make deploy-dr-cluster
            
            # Wait for operator
            kubectl wait --for=condition=available --timeout=180s deployment/ramen-dr-cluster-operator -n ramen-system
            log_success "DR operator ready on $profile"
        fi
    done
    
    kubectl config use-context "$HUB_PROFILE"
    log_success "RamenDR operators installed successfully"
}

# Storage dependencies for hub
install_storage_dependencies_hub() {
    # VolSync installation
    log_info "Installing VolSync on hub..."
    helm repo add backube https://backube.github.io/helm-charts/ || true
    helm repo update
    kubectl create namespace volsync-system --dry-run=client -o yaml | kubectl apply -f -
    
    if ! helm list -n volsync-system | grep -q volsync; then
        helm install volsync backube/volsync --namespace volsync-system --wait --timeout=3m || log_warning "VolSync installation may have timed out"
    fi
    
    # Install missing VolSync CRDs
    kubectl apply -f https://raw.githubusercontent.com/backube/volsync/main/config/crd/bases/volsync.backube_replicationsources.yaml || true
    kubectl apply -f https://raw.githubusercontent.com/backube/volsync/main/config/crd/bases/volsync.backube_replicationdestinations.yaml || true
}

# Storage dependencies for DR clusters
install_storage_dependencies_dr() {
    local profile=$1
    log_info "Installing storage dependencies on $profile..."
    
    # External Snapshotter CRDs
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml || true
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml || true
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml || true
    
    # Snapshot Controller
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml || true
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.3.0/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml || true
    
    # VolumeReplication CRDs
    kubectl apply -f https://raw.githubusercontent.com/csi-addons/volume-replication-operator/main/config/crd/bases/replication.storage.openshift.io_volumereplications.yaml || true
    kubectl apply -f https://raw.githubusercontent.com/csi-addons/volume-replication-operator/main/config/crd/bases/replication.storage.openshift.io_volumereplicationclasses.yaml || true
    
    # VolSync CRDs (critical for RamenDR)
    kubectl apply -f https://raw.githubusercontent.com/backube/volsync/main/config/crd/bases/volsync.backube_replicationsources.yaml || true
    kubectl apply -f https://raw.githubusercontent.com/backube/volsync/main/config/crd/bases/volsync.backube_replicationdestinations.yaml || true
}

# Missing resource classes for hub
install_missing_resource_classes_hub() {
    # S3 secret and config
    kubectl apply -f - <<EOF || true
apiVersion: v1
kind: Secret
metadata:
  name: ramen-s3-secret
  namespace: ramen-system
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: minioadmin
  AWS_SECRET_ACCESS_KEY: minioadmin
EOF
    
    kubectl apply -f - <<EOF || true
apiVersion: v1
kind: ConfigMap
metadata:
  name: ramen-dr-cluster-config
  namespace: ramen-system
data:
  ramen_manager_config.yaml: |
    ramenControllerType: dr-hub
    maxConcurrentReconciles: 1
    s3StoreProfiles:
      minio-s3:
        s3ProfileName: minio-s3
        s3Bucket: ramen-metadata
        s3Region: us-east-1
        s3Endpoint: http://minio.minio-system.svc.cluster.local:9000
        s3SecretRef:
          name: ramen-s3-secret
          namespace: ramen-system
EOF
}

# Missing resource classes for DR clusters
install_missing_resource_classes_dr() {
    # VolumeSnapshotClass for minikube CSI
    kubectl apply -f - <<EOF || true
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: demo-snapclass
  labels:
    velero.io/csi-volumesnapshot-class: "true"
driver: hostpath.csi.k8s.io
deletionPolicy: Delete
EOF
    
    # VolumeReplicationClass  
    kubectl apply -f - <<EOF || true
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplicationClass
metadata:
  name: demo-replication-class
  labels:
    ramendr.openshift.io/replicationID: ramen-volsync
spec:
  provisioner: hostpath.csi.k8s.io
  parameters:
    copyMethod: Snapshot
EOF
}

# Deploy MinIO S3 storage
deploy_minio() {
    log_step "Deploying MinIO S3 storage..."
    
    kubectl config use-context "$HUB_PROFILE"
    kubectl create namespace minio-system --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: minio-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: quay.io/minio/minio:latest
        command:
        - /bin/bash
        - -c
        args:
        - minio server /data --console-address :9001
        volumeMounts:
        - name: storage
          mountPath: /data
        ports:
        - containerPort: 9000
        - containerPort: 9001
        env:
        - name: MINIO_ROOT_USER
          value: minioadmin
        - name: MINIO_ROOT_PASSWORD
          value: minioadmin
      volumes:
      - name: storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: minio-system
spec:
  selector:
    app: minio
  ports:
  - name: api
    port: 9000
    targetPort: 9000
  - name: console
    port: 9001
    targetPort: 9001
  type: ClusterIP
EOF

    kubectl wait --for=condition=available --timeout=60s deployment/minio -n minio-system
    log_success "MinIO deployed successfully"
}

# Deploy sample application with PVC
deploy_sample_app() {
    log_step "Deploying sample application with PVC..."
    
    # Use the first available DR cluster
    local dr_cluster=""
    for cluster in "${AVAILABLE_CLUSTERS[@]}"; do
        if [ "$cluster" != "$HUB_PROFILE" ]; then
            dr_cluster="$cluster"
            break
        fi
    done
    
    if [ -z "$dr_cluster" ]; then
        log_error "No DR cluster available"
        return 1
    fi
    
    kubectl config use-context "$dr_cluster"
    kubectl create namespace nginx-demo --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-pvc
  namespace: nginx-demo
  labels:
    app: nginx-demo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
  namespace: nginx-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
        env:
        - name: CLUSTER_NAME
          value: "$dr_cluster"
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: nginx-pvc
EOF

    kubectl wait --for=condition=available --timeout=60s deployment/nginx-demo -n nginx-demo
    
    # Write test data
    local pod_name=$(kubectl get pods -n nginx-demo -l app=nginx-demo -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n nginx-demo "$pod_name" -- sh -c 'echo "<h1>RamenDR minikube Demo - $(date)</h1><p>Persistent data with CSI hostpath driver!</p>" > /usr/share/nginx/html/index.html'
    
    log_success "Sample application deployed on $dr_cluster"
    APP_CLUSTER="$dr_cluster"
}

# Create VRG to protect the application
create_vrg() {
    log_step "Creating VolumeReplicationGroup to protect application..."
    
    kubectl config use-context "$APP_CLUSTER"
    
    kubectl apply -f - <<EOF
apiVersion: ramendr.openshift.io/v1alpha1
kind: VolumeReplicationGroup
metadata:
  name: nginx-demo-vrg
  namespace: nginx-demo
  labels:
    app: nginx-demo
spec:
  pvcSelector:
    matchLabels:
      app: nginx-demo
  replicationState: primary
  s3Profiles:
  - minio-s3
  async:
    schedulingInterval: 5m
    replicationClassSelector:
      matchLabels:
        ramendr.openshift.io/replicationID: ramen-volsync
    volumeSnapshotClassSelector:
      matchLabels:
        velero.io/csi-volumesnapshot-class: "true"
  kubeObjectProtection:
    captureInterval: 10m
    kubeObjectSelector:
      matchLabels:
        app: nginx-demo
EOF

    # Wait a bit for VRG to initialize
    sleep 10
    kubectl get vrg nginx-demo-vrg -n nginx-demo
    
    log_success "VolumeReplicationGroup created successfully"
}

# Setup MinIO console access
setup_minio_console() {
    log_step "Setting up MinIO console access..."
    
    # Kill existing port-forwards
    pkill -f "kubectl port-forward.*minio" >/dev/null 2>&1 || true
    
    kubectl config use-context "$HUB_PROFILE"
    kubectl port-forward -n minio-system service/minio 9001:9001 > /dev/null 2>&1 &
    sleep 3
    
    log_success "MinIO console ready at http://localhost:9001"
    log_info "Login: minioadmin / minioadmin"
}

# Create DR resources (if we have enough clusters)
create_dr_resources() {
    log_step "Creating DR resources..."
    
    kubectl config use-context "$HUB_PROFILE"
    
    # Create DRCluster for each available DR cluster
    for cluster in "${AVAILABLE_CLUSTERS[@]}"; do
        if [ "$cluster" != "$HUB_PROFILE" ]; then
            kubectl apply -f - <<EOF || true
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRCluster
metadata:
  name: $cluster
  namespace: ramen-system
spec:
  s3ProfileName: minio-s3
EOF
            log_info "DRCluster created for: $cluster"
        fi
    done
    
    # Create DRPolicy if we have enough clusters (need 2+)
    local dr_clusters=()
    for cluster in "${AVAILABLE_CLUSTERS[@]}"; do
        if [ "$cluster" != "$HUB_PROFILE" ]; then
            dr_clusters+=("$cluster")
        fi
    done
    
    if [ ${#dr_clusters[@]} -ge 2 ]; then
        kubectl apply -f - <<EOF || true
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRPolicy
metadata:
  name: minikube-dr-policy
  namespace: ramen-system
spec:
  drClusters:
$(printf "  - %s\n" "${dr_clusters[@]}")
  schedulingInterval: 5m
EOF
        log_success "DRPolicy created for clusters: ${dr_clusters[*]}"
    else
        log_warning "DRPolicy skipped (requires 2+ DR clusters, have ${#dr_clusters[@]})"
    fi
}

# Show final demo status and next steps
show_demo_status() {
    log_step "🎉 Demo Setup Complete!"
    echo ""
    
    echo "📊 Cluster Status:"
    echo "  Available clusters: ${#AVAILABLE_CLUSTERS[@]}"
    for cluster in "${AVAILABLE_CLUSTERS[@]}"; do
        echo "    • $cluster ($([ "$cluster" = "$HUB_PROFILE" ] && echo "Hub" || echo "DR"))"
    done
    echo ""
    
    echo "🌐 Access URLs:"
    echo "  • MinIO Console: http://localhost:9001 (minioadmin/minioadmin)"
    echo "  • Expected S3 bucket: ramen-metadata"
    echo ""
    
    echo "📋 Verification Commands:"
    echo "  • Check operators: kubectl get pods -n ramen-system --context=ramen-hub"
    echo "  • Check application: kubectl get pods,pvc,vrg -n nginx-demo --context=$APP_CLUSTER"
    echo "  • Check DR resources: kubectl get drclusters,drpolicies -n ramen-system --context=ramen-hub"
    echo ""
    
    echo "📊 Monitoring:"
    echo "  • Run: ./examples/demo-monitoring-minikube.sh"
    echo "  • Or use comprehensive monitoring (option 5)"
    echo ""
    
    echo "🔄 Next Steps:"
    echo "  • Open MinIO console to see S3 buckets"
    echo "  • Run monitoring to see real-time status"
    echo "  • Try failover demo: ./examples/demo-failover-minikube.sh"
    echo ""
    
    # Show current VRG status
    kubectl config use-context "$APP_CLUSTER"
    echo "📦 Current VRG Status:"
    kubectl get vrg nginx-demo-vrg -n nginx-demo -o custom-columns="NAME:.metadata.name,DESIRED:.spec.replicationState,CURRENT:.status.state" || echo "VRG initializing..."
    echo ""
    
    log_success "Complete minikube demo ready!"
}

# Main execution
main() {
    check_prerequisites
    setup_clusters
    install_ramendr
    deploy_minio
    deploy_sample_app
    create_vrg
    setup_minio_console
    create_dr_resources
    show_demo_status
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "RamenDR Complete minikube Demo"
        echo ""
        echo "Usage: $0"
        echo ""
        echo "This script sets up a complete RamenDR demo environment with:"
        echo "  • minikube clusters (2-3) with CSI support"
        echo "  • RamenDR operators with all dependencies" 
        echo "  • MinIO S3 storage"
        echo "  • Protected sample application"
        echo "  • Monitoring setup"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
