#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

# Minikube profiles
HUB_PROFILE="ramen-hub"
DR1_PROFILE="ramen-dr1"
DR2_PROFILE="ramen-dr2"

log_info "Creating OCM prerequisites..."

# Create namespaces for DR clusters
for cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    kubectl --context=${HUB_PROFILE} create namespace ${cluster} --dry-run=client -o yaml | \
    kubectl --context=${HUB_PROFILE} apply -f -
done

# Create ManagedCluster resources
for cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    cat <<EOF | kubectl --context=${HUB_PROFILE} apply -f -
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: ${cluster}
  labels:
    app.kubernetes.io/name: ramen
    app.kubernetes.io/component: dr-cluster
spec:
  hubAcceptsClient: true
EOF
done

# Create PlacementRule

# Create PlacementRule with clusterSelector
cat <<EOF | kubectl --context=${HUB_PROFILE} apply -f -
apiVersion: apps.open-cluster-management.io/v1
kind: PlacementRule
metadata:
  name: ramen-demo-placement
  namespace: ramen-system
spec:
  clusterSelector: {}
EOFkubectl --context=ramen-hub -n ramen-system logs ramen-hub-operator-776f79764-kphck

# Function to create ClusterClaim CRD
create_clusterclaim_crd() {
    local context=$1
    log_info "Creating ClusterClaim CRD in ${context}..."
    cat <<EOF | kubectl --context=${context} apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: clusterclaims.cluster.open-cluster-management.io
spec:
  group: cluster.open-cluster-management.io
  names:
    kind: ClusterClaim
    listKind: ClusterClaimList
    plural: clusterclaims
    singular: clusterclaim
  scope: Cluster
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              value:
                type: string
EOF
}

# Create ClusterClaim CRD in all clusters
for cluster in "${HUB_PROFILE}" "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    create_clusterclaim_crd "${cluster}"
done

# Create ClusterClaims in DR clusters
for cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    log_info "Creating ClusterClaim in ${cluster}..."
    cat <<EOF | kubectl --context=${cluster} apply -f -
apiVersion: cluster.open-cluster-management.io/v1alpha1
kind: ClusterClaim
metadata:
  name: id.k8s.io
spec:
  value: "${cluster}"
EOF
done

# Restart operators to pick up new CRDs
log_info "Restarting operators to pick up new CRDs..."
for cluster in "${HUB_PROFILE}" "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    kubectl --context=${cluster} delete pod -n ramen-system -l control-plane=controller-manager --grace-period=0 || true
done



log_success "OCM prerequisites created successfully"

