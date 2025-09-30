#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils.sh
source "$SCRIPT_DIR/../utils.sh"

set -e

CLUSTERS=("ramen-dr1" "ramen-dr2")
NAMESPACE="rook-ceph"

for CONTEXT in "${CLUSTERS[@]}"; do
    log_info "🚀 Setting up Rook Ceph storage in minikube context: $CONTEXT"

    # 1. Ensure rook-ceph namespace exists
    ensure_namespace "$CONTEXT" "$NAMESPACE"

    # 2. Apply Rook CRDs and common resources
    apply_url_safe "$CONTEXT" "https://raw.githubusercontent.com/rook/rook/v1.13.3/deploy/examples/crds.yaml" "Rook CRDs"
    apply_url_safe "$CONTEXT" "https://raw.githubusercontent.com/rook/rook/v1.13.3/deploy/examples/common.yaml" "Rook common resources"

    # 3. Deploy Rook operator
    apply_url_safe "$CONTEXT" "https://raw.githubusercontent.com/rook/rook/v1.13.3/deploy/examples/operator.yaml" "Rook Ceph operator"

    # 4. Deploy Ceph cluster using useAllDevices: true, but only if not already present and ready
    if kubectl --context="$CONTEXT" -n rook-ceph get cephcluster rook-ceph &>/dev/null; then
        PHASE=$(kubectl --context="$CONTEXT" -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.phase}')
        if [[ "$PHASE" == "Ready" ]]; then
            log_success "Ceph cluster in $CONTEXT is already ready!"
        else
            log_info "Ceph cluster in $CONTEXT exists but is not ready (phase: $PHASE)."
        fi
    else
        log_step "Deploying Ceph cluster using useAllDevices: true..."
        cat <<EOF | kubectl --context="$CONTEXT" apply -f -
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.2
  dataDirHostPath: /var/lib/rook
  mon:
    count: 1
    allowMultiplePerNode: true
  dashboard:
    enabled: true
  storage:
    useAllNodes: true
    useAllDevices: true
  disruptionManagement:
    managePodBudgets: false
EOF
        log_success "Ceph cluster resource applied in $CONTEXT."
    fi

    # 5. Wait for Ceph cluster to be ready if not already
    PHASE=$(kubectl --context="$CONTEXT" -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [[ "$PHASE" != "Ready" ]]; then
        log_step "Waiting for Ceph cluster to be ready in $CONTEXT (this may take a few minutes)..."
        if kubectl --context="$CONTEXT" -n rook-ceph wait --for=condition=Ready cephcluster rook-ceph --timeout=600s; then
            log_success "Ceph cluster is ready in $CONTEXT!"
        else
            log_warning "Timed out waiting for Ceph cluster to be ready in $CONTEXT. Please check the cluster status."
        fi
    else
        log_success "Ceph cluster is ready in $CONTEXT!"
    fi

    # 6. Deploy Ceph toolbox for troubleshooting
    apply_url_safe "$CONTEXT" "https://raw.githubusercontent.com/rook/rook/v1.13.3/deploy/examples/toolbox.yaml" "Ceph toolbox"

    log_info "✅ Rook Ceph storage setup complete in $CONTEXT. You can now use Ceph for SAN/VSAN testing."
    echo "-------------------------------------------------------------"
done