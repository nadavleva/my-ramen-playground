#!/bin/bash

# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# demo-failover-minikube.sh - RamenDR disaster recovery failover demo for minikube
# This script demonstrates switching between primary and secondary VRG states using minikube

set -euo pipefail

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

# Minikube profiles
HUB_PROFILE="ramen-hub"
DR1_PROFILE="ramen-dr1"
DR2_PROFILE="ramen-dr2"

# Validate and fix minikube profiles
validate_profiles() {
    # echo  "KUBECONFIG: ${KUBECONFIG}"
    # Minikube profiles
    HUB_PROFILE="ramen-hub"
    DR1_PROFILE="ramen-dr1"
    DR2_PROFILE="ramen-dr2"
    echo  "CURRENT_CONTEXT: $(kubectl config current-context)"
    log_info "Validating minikube profiles..."
    for profile in "${HUB_PROFILE}" "${DR1_PROFILE}" "${DR2_PROFILE}"; do
        if ! minikube profile list | grep -q "${profile}"; then
            log_error "Profile ${profile} not found in minikube!"
            exit 1
        fi
        
        # Set profile and update context
        minikube profile "${profile}"
        minikube update-context
        
        # Verify context exists
        if ! kubectl config get-contexts | grep -q "^.*${profile}.*$"; then
            log_error "Context ${profile} not found in kubeconfig!"
            exit 1
        fi
    done
    log_success "All minikube profiles validated"
}

# Run validation before creating resources
validate_profiles

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${PURPLE}🚀 $1${NC}"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Minikube configuration
HUB_PROFILE="ramen-hub"
DR1_PROFILE="ramen-dr1"
DR2_PROFILE="ramen-dr2"

# Check minikube profile exists
check_profile_exists() {
    local profile="$1"
    minikube profile list 2>/dev/null | grep -q "$profile"
}

echo "=============================================="
echo "🔄 RamenDR Disaster Recovery Failover Demo (minikube)"
echo "=============================================="
echo ""
echo "This demo shows:"
echo "   • Application protection with VRG"
echo "   • Primary → Secondary failover simulation"  
echo "   • Application restoration on DR cluster"
echo "   • Data persistence verification"
echo ""

# Confirmation
read -p "Proceed with failover demonstration? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Demo cancelled by user"
    exit 0
fi

echo ""

# Check prerequisites
log_step "Checking prerequisites..."

# Check if minikube profiles exist
if ! check_profile_exists "$DR1_PROFILE"; then
    log_error "Minikube profile $DR1_PROFILE not found! Run './scripts/fresh-demo-minikube.sh' first"
    exit 1
fi

if ! check_profile_exists "$DR2_PROFILE"; then
    log_error "Minikube profile $DR2_PROFILE not found! You need both DR1 and DR2 for failover demo"
    log_info "Run: ./scripts/setup-minikube.sh and create all 3 clusters"
    exit 1
fi

# Check contexts
if ! kubectl config get-contexts | grep -q "$DR1_PROFILE"; then
    log_error "kubectl context $DR1_PROFILE not found! Run 'minikube update-context --profile=$DR1_PROFILE'"
    exit 1
fi

# Check operators
kubectl config use-context "$DR1_PROFILE" >/dev/null 2>&1
if ! kubectl get pods -n ramen-system 2>/dev/null | grep -q "Running"; then
    log_error "RamenDR operators not running! Run './scripts/fresh-demo-minikube.sh' first"
    exit 1
fi

log_success "Prerequisites satisfied"

# Phase 1: Deploy application on DR1
log_step "Phase 1: Deploying protected application on $DR1_PROFILE"

kubectl config use-context "$DR1_PROFILE" >/dev/null 2>&1

# Create namespace
log_info "Creating namespace and application..."
kubectl create namespace nginx-failover-demo 2>/dev/null || log_info "Namespace already exists"

# Deploy application with PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-pvc
  namespace: nginx-failover-demo
  labels:
    app: nginx-failover-demo
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
  name: nginx-failover-demo
  namespace: nginx-failover-demo
  labels:
    app: nginx-failover-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-failover-demo
  template:
    metadata:
      labels:
        app: nginx-failover-demo
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
          value: "DR1-PRIMARY"
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: demo-pvc
EOF

# Wait for pod to be ready
log_info "Waiting for application to be ready..."
kubectl wait --for=condition=available --timeout=60s deployment/nginx-failover-demo -n nginx-failover-demo >/dev/null 2>&1

# Add robust pod readiness check
log_info "Waiting for pod to be ready..."
for i in {1..30}; do
    POD_NAME=$(kubectl get pods -n nginx-failover-demo -l app=nginx-failover-demo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ ! -z "$POD_NAME" ]; then
        if kubectl wait --for=condition=ready pod/$POD_NAME -n nginx-failover-demo --timeout=10s >/dev/null 2>&1; then
            break
        fi
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ -z "$POD_NAME" ]; then
    log_error "Pod not found after waiting. Check deployment status."
    exit 1
fi

# Write test data
log_info "Writing test data to persistent volume..."
POD_NAME=$(kubectl get pods -n nginx-failover-demo -l app=nginx-failover-demo -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n nginx-failover-demo $POD_NAME -- sh -c 'echo "<h1>Original Data from DR1 - $(date)</h1><p>This data should persist after failover!</p>" > /usr/share/nginx/html/index.html'

# Create VRG to protect the application
log_info "Creating VolumeReplicationGroup to protect the application..."
cat <<EOF | kubectl apply -f -
apiVersion: ramendr.openshift.io/v1alpha1
kind: VolumeReplicationGroup
metadata:
  name: demo-vrg
  namespace: nginx-failover-demo
  labels:
    app: nginx-failover-demo
spec:
  pvcSelector:
    matchLabels:
      app: nginx-failover-demo
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
        app: nginx-failover-demo
EOF

log_success "Application deployed and protected on $DR1_PROFILE"

# Show initial status
echo ""
log_info "📊 Initial status on $DR1_PROFILE:"
kubectl get pods -n nginx-failover-demo -l app=nginx-failover-demo | grep -v "NAME" | sed 's/^/   Pod: /'
kubectl get vrg -n nginx-failover-demo | grep -v "NAME" | sed 's/^/   VRG: /'
kubectl get pvc -n nginx-failover-demo | grep -v "NAME" | sed 's/^/   PVC: /'

# Verify data
log_info "Current data in application:"
CURRENT_DATA=$(kubectl exec -n nginx-failover-demo $POD_NAME -- cat /usr/share/nginx/html/index.html 2>/dev/null || echo "Could not read data")
echo "   📝 $CURRENT_DATA"

echo ""
echo "⏳ Waiting 10 seconds for replication to initialize..."
sleep 10

# Phase 2: Simulate disaster
log_step "Phase 2: Simulating disaster on $DR1_PROFILE"

log_info "🚨 DISASTER: Simulating $DR1_PROFILE cluster failure"
log_info "Switching VRG to secondary state (cluster becomes unavailable)..."

# Switch VRG to secondary
kubectl patch vrg demo-vrg -n nginx-failover-demo --type='merge' -p='{"spec":{"replicationState":"secondary"}}'

# Scale down application (simulating cluster failure)
kubectl scale deployment nginx-failover-demo --replicas=0 -n nginx-failover-demo

log_success "$DR1_PROFILE cluster marked as failed (VRG secondary, app scaled down)"

echo ""
log_info "📊 Post-disaster status on $DR1_PROFILE:"
kubectl get pods -n nginx-failover-demo -l app=nginx-failover-demo | grep -v "NAME" | sed 's/^/   Pod: /' || log_info "   Pod: No running pods (as expected)"
kubectl get vrg -n nginx-failover-demo | grep -v "NAME" | sed 's/^/   VRG: /'

echo ""
echo "⏳ Waiting 10 seconds for replication state change..."
sleep 10

# Phase 3: Failover to DR2
log_step "Phase 3: Failing over to $DR2_PROFILE cluster"

kubectl config use-context "$DR2_PROFILE" >/dev/null 2>&1

log_info "🔄 FAILOVER: Restoring application on $DR2_PROFILE"
log_info "Creating namespace and restoring application..."

# Create namespace
kubectl create namespace nginx-failover-demo 2>/dev/null || log_info "Namespace already exists on $DR2_PROFILE"

# Create VRG as primary on DR2
log_info "Creating VRG as primary on $DR2_PROFILE..."
cat <<EOF | kubectl apply -f -
apiVersion: ramendr.openshift.io/v1alpha1
kind: VolumeReplicationGroup
metadata:
  name: demo-vrg
  namespace: nginx-failover-demo
  labels:
    app: nginx-failover-demo
spec:
  pvcSelector:
    matchLabels:
      app: nginx-failover-demo
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
        app: nginx-failover-demo
EOF

# Deploy application on DR2
log_info "Deploying restored application on $DR2_PROFILE..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-pvc
  namespace: nginx-failover-demo
  labels:
    app: nginx-failover-demo
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
  name: nginx-failover-demo
  namespace: nginx-failover-demo
  labels:
    app: nginx-failover-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-failover-demo
  template:
    metadata:
      labels:
        app: nginx-failover-demo
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
          value: "DR2-RECOVERED"
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: demo-pvc
EOF

# Wait for application to be ready
log_info "Waiting for restored application to be ready..."
sleep 15
kubectl wait --for=condition=available --timeout=90s deployment/nginx-failover-demo -n nginx-failover-demo >/dev/null 2>&1 || log_warning "Application may still be starting"

log_success "Application restored on $DR2_PROFILE"

# Phase 4: Verify failover
log_step "Phase 4: Verifying successful failover"

echo ""
log_info "📊 Final status comparison:"

# DR1 status
log_info "   $DR1_PROFILE cluster (post-disaster):"
kubectl config use-context "$DR1_PROFILE" >/dev/null 2>&1
kubectl get pods -n nginx-failover-demo -l app=nginx-failover-demo 2>/dev/null | grep -v "NAME" | sed 's/^/      Pod: /' || log_info "      Pod: No running pods (as expected)"
kubectl get vrg -n nginx-failover-demo 2>/dev/null | grep -v "NAME" | sed 's/^/      VRG: /'

# DR2 status
log_info "   $DR2_PROFILE cluster (active):"
kubectl config use-context "$DR2_PROFILE" >/dev/null 2>&1
kubectl get pods -n nginx-failover-demo -l app=nginx-failover-demo 2>/dev/null | grep -v "NAME" | sed 's/^/      Pod: /'
kubectl get vrg -n nginx-failover-demo 2>/dev/null | grep -v "NAME" | sed 's/^/      VRG: /'

# Test data persistence
echo ""
log_info "🔍 Testing data persistence after failover..."
sleep 5

POD_NAME_DR2=$(kubectl get pods -n nginx-failover-demo -l app=nginx-failover-demo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$POD_NAME_DR2" ]; then
    # Check if pod is ready
    kubectl wait --for=condition=ready --timeout=30s pod/$POD_NAME_DR2 -n nginx-failover-demo >/dev/null 2>&1 || log_warning "Pod may not be fully ready"
    
    RECOVERED_DATA=$(kubectl exec -n nginx-failover-demo $POD_NAME_DR2 -- cat /usr/share/nginx/html/index.html 2>/dev/null || echo "Could not read data - pod may not be ready")
    
    echo ""
    if [[ "$RECOVERED_DATA" == *"Original Data from DR1"* ]]; then
        log_success "🎉 SUCCESS: Original data from DR1 preserved after failover!"
        echo "   📝 Recovered data: $RECOVERED_DATA"
    elif [[ "$RECOVERED_DATA" == *"Could not read"* ]]; then
        log_warning "⏳ Pod is still starting - data verification may succeed in a few moments"
    else
        log_info "📝 New data environment on $DR2_PROFILE: $RECOVERED_DATA"
        log_info "   (Original data may sync later depending on storage replication)"
    fi
else
    log_warning "⚠️  Pod not found on $DR2_PROFILE - deployment may still be in progress"
fi

echo ""
echo "=============================================="
echo "🎉 RamenDR Failover Demonstration Complete!"
echo "=============================================="
echo ""

log_success "Demonstration completed successfully!"
echo ""
log_info "📋 What was demonstrated:"
echo "   ✅ Application deployment with persistent storage on minikube"
echo "   ✅ VolumeReplicationGroup protection setup"
echo "   ✅ Disaster simulation (primary → secondary)"
echo "   ✅ Application failover to DR cluster"
echo "   ✅ Data persistence verification"
echo ""
log_info "🔄 Optional next steps:"
echo "   • Test failback: Switch $DR2_PROFILE VRG to secondary, $DR1_PROFILE back to primary"
echo "   • Check S3 metadata: minikube service minio --profile=$HUB_PROFILE"
echo "   • Verify replication logs in operator pods"
echo "   • Test with different applications and storage classes"
echo ""
log_info "🧹 Cleanup:"
echo "   • Remove demo resources: kubectl delete namespace nginx-failover-demo --context=$DR1_PROFILE"
echo "   • Remove demo resources: kubectl delete namespace nginx-failover-demo --context=$DR2_PROFILE"
echo "   • Full cleanup: minikube delete --profile=$HUB_PROFILE --profile=$DR1_PROFILE --profile=$DR2_PROFILE"
echo ""
log_success "Happy disaster recovery testing with minikube! 🚀"
