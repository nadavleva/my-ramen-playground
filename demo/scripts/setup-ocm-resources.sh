#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

# Minikube profiles
HUB_PROFILE="ramen-hub"
DR1_PROFILE="ramen-dr1"
DR2_PROFILE="ramen-dr2"

log_info "Creating OCM prerequisites..."


# Verify minikube clusters exist
for cluster in "${HUB_PROFILE}" "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    if ! kubectl config get-contexts | grep -q "${cluster}"; then
        log_error "Context '${cluster}' not found. Please run ./demo/scripts/minikube_setup.sh first"
        exit 1
    fi
done

# Create namespaces for DR clusters
# 1. On HUB:
ensure_namespace "$HUB_PROFILE" "open-cluster-management"    # OCM hub
ensure_namespace "$HUB_PROFILE" "ramen-system"              # RamenDR hub

# 2. On DR CLUSTERS:
for ctx in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    ensure_namespace "$ctx" "open-cluster-management"        # Klusterlet
done

# for cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
#     # kubectl --context=$cluster create namespace ${cluster} --dry-run=client -o yaml | \
#     kubectl --context=$cluster apply -f -
# done

# Add hub IP detection
HUB_IP=$(minikube -p ramen-hub ip)
if [ -z "$HUB_IP" ]; then
    log_error "Could not get Minikube hub IP"
    exit 1
fi
log_info "Hub IP: ${HUB_IP}"

# OCM CRDs to check/apply
declare -A OCM_CRDS
OCM_CRDS["managedclusters.cluster.open-cluster-management.io"]="https://raw.githubusercontent.com/open-cluster-management-io/api/main/cluster/v1/0000_00_clusters.open-cluster-management.io_managedclusters.crd.yaml"
OCM_CRDS["placements.cluster.open-cluster-management.io"]="https://raw.githubusercontent.com/open-cluster-management-io/api/main/cluster/v1beta1/0000_02_clusters.open-cluster-management.io_placements.crd.yaml"
OCM_CRDS["placementdecisions.cluster.open-cluster-management.io"]="https://raw.githubusercontent.com/open-cluster-management-io/api/main/cluster/v1beta1/0000_03_clusters.open-cluster-management.io_placementdecisions.crd.yaml"
# OCM_CRDS["managedclusterviews.view.open-cluster-management.io"]="https://raw.githubusercontent.com/open-cluster-management-io/view/main/config/crd/bases/view.open-cluster-management.io_managedclusterviews.yaml"
OCM_CRDS["manifestworks.work.open-cluster-management.io"]="https://raw.githubusercontent.com/open-cluster-management-io/api/main/work/v1/0000_00_work.open-cluster-management.io_manifestworks.crd.yaml"

# Apply each CRD only if missing
for crd in "${!OCM_CRDS[@]}"; do
    apply_crd_if_missing "$HUB_PROFILE" "$crd" "${OCM_CRDS[$crd]}"
done


# FIRST: Install cluster-manager CRDs and operator on hub
# log_info "Creating open-cluster-management namespace..."
# kubectl --context=ramen-hub create namespace open-cluster-management --dry-run=client -o yaml | kubectl --context=ramen-hub apply -f -
log_info "Installing cluster-manager CRDs and operator on hub..."
kubectl --context=ramen-hub apply -k demo/yaml/ocm/deploy/cluster-manager/config

# Wait for cluster-manager deployment
wait_for_pod "ramen-hub" "open-cluster-management" "cluster-manager"

# SECOND: Create ClusterManager CR to enable placement functionality
log_info "Creating ClusterManager CR with placement enabled..."
cat <<EOF | kubectl --context=${HUB_PROFILE} apply -f -
apiVersion: operator.open-cluster-management.io/v1
kind: ClusterManager
metadata:
  name: cluster-manager
spec:
  registrationImagePullSpec: quay.io/open-cluster-management/registration:latest
  workImagePullSpec: quay.io/open-cluster-management/work:latest
  placementImagePullSpec: quay.io/open-cluster-management/placement:latest
  deployOption:
    mode: Default
EOF

# Wait for cluster-manager to be ready with placement
log_info "Waiting for cluster-manager deployment with placement..."
kubectl --context=${HUB_PROFILE} rollout status deployment/cluster-manager -n open-cluster-management --timeout=300s

# Wait for ClusterManager to create OCM CRDs
log_info "Waiting for OCM CRDs to be available..."
required_crds=(
    "managedclusters.cluster.open-cluster-management.io"
    "placements.cluster.open-cluster-management.io"        # NEW API
    "placementdecisions.cluster.open-cluster-management.io" # NEW API  
    # "clusterclaims.cluster.open-cluster-management.io" # <-- Removed this line
)

for crd in "${required_crds[@]}"; do
    ensure_resource "$HUB_PROFILE" "crd" "$crd" "" 60
done


# Ensure ManagedClusterView CRD is present if needed by operator
MCV_CRD_NAME="managedclusterviews.view.open-cluster-management.io"
MCV_CRD_FILE="$SCRIPT_DIR/../../hack/test/view.open-cluster-management.io_managedclusterviews.yaml"

log_info "Ensuring ManagedClusterView CRD is present..."
if [ -f "$MCV_CRD_FILE" ]; then
    if ! kubectl --context="$HUB_PROFILE" get crd "$MCV_CRD_NAME" >/dev/null 2>&1; then
        log_info "Applying ManagedClusterView CRD for compatibility..."
        apply_yaml_file_safe "$HUB_PROFILE" "$MCV_CRD_FILE" "ManagedClusterView CRD"
    else
        log_info "ManagedClusterView CRD already exists on $HUB_PROFILE"
    fi
else
    log_warning "ManagedClusterView CRD file not found at $MCV_CRD_FILE; skipping ManagedClusterView CRD install"
fi

# Ensure legacy PlacementRule CRD is present if needed by operator
PLACEMENTRULE_CRD_NAME="placementrules.apps.open-cluster-management.io"
PLACEMENTRULE_CRD_FILE="$SCRIPT_DIR/../../hack/test/apps.open-cluster-management.io_placementrules_crd.yaml"

if [ -f "$PLACEMENTRULE_CRD_FILE" ]; then
    if ! kubectl --context="$HUB_PROFILE" get crd "$PLACEMENTRULE_CRD_NAME" >/dev/null 2>&1; then
        log_info "Applying legacy PlacementRule CRD for compatibility..."
        apply_yaml_file_safe "$HUB_PROFILE" "$PLACEMENTRULE_CRD_FILE" "PlacementRule CRD"
    else
        log_info "PlacementRule CRD already exists on $HUB_PROFILE"
    fi
else
    log_warning "PlacementRule CRD file not found at $PLACEMENTRULE_CRD_FILE; skipping legacy CRD install"
fi


# TODO: Remove this old waiting loop once confirmed working
# for crd in "${required_crds[@]}"; do
#     log_info "⏳ Waiting for CRD: ${crd}"
#     timeout=60
#     while [ $timeout -gt 0 ]; do
#         if kubectl --context="${HUB_PROFILE}" get crd "${crd}" >/dev/null 2>&1; then
#             log_success "✅ CRD ${crd} is available"
#             break
#         fi
#         echo -n "."
#         sleep 5
#         timeout=$((timeout-5))
#     done
    
#     if [ $timeout -le 0 ]; then
#         log_error "❌ Timeout waiting for CRD ${crd}"
#         kubectl --context="${HUB_PROFILE}" get crd | grep -E "(cluster|placement)"
#         exit 1
#     fi
# done

# Check for placement controllers
wait_for_condition "$HUB_PROFILE" "get pods -n open-cluster-management-hub | grep placement" "placement controller pod" 60 5
# sleep 30
# log_info "Checking for placement controllers..."
# kubectl --context=${HUB_PROFILE} get pods -n open-cluster-management-hub | grep placement || log_warning "No placement controller found"

# Install OCM klusterlet on DR clusters
log_info "Creating OCM prerequisites install klusterlet on DR clusters..."
for ctx in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    log_info "Installing klusterlet on ${ctx}..."
    # kubectl --context=$ctx create namespace open-cluster-management --dry-run=client -o yaml | kubectl --context=$ctx apply -f -
    log_info "Applying klusterlet manifests on ${ctx}..."
    kubectl --context=$ctx -n open-cluster-management apply -k demo/yaml/ocm/deploy/klusterlet/config/
done

# Wait for klusterlet deployments
for cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    wait_for_deployment "$cluster" "klusterlet" "open-cluster-management"
    
    # log_info "Waiting for klusterlet deployment on ${cluster}..."
    # kubectl --context=${cluster} wait --for=condition=available deployment/klusterlet -n open-cluster-management --timeout=300s
done

# Create ManagedCluster resources
log_info "Creating ManagedCluster resources..."
for cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    log_info "Creating ManagedCluster for ${cluster}..."
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

# Create ramen-system namespace before PlacementRule
log_info "Creating ramen-system namespace..."
ensure_namespace "$HUB_PROFILE" "ramen-system"
# kubectl --context=${HUB_PROFILE} create namespace ramen-system --dry-run=client -o yaml | \
# kubectl --context=${HUB_PROFILE} apply -f -

# Create PlacementRule with clusterSelector
log_info "Creating demo Placement..."
placement_yaml="apiVersion: cluster.open-cluster-management.io/v1beta1
kind: Placement
metadata:
  name: ramen-demo-placement
  namespace: ramen-system
spec:
  predicates:
  - requiredClusterSelector:
      labelSelector: {}"
create_resource "$HUB_PROFILE" "ramen-system" "$placement_yaml" "Placement"


# TODO: Remove this old PlacementRule creation once confirmed working
# cat <<EOF | kubectl --context=${HUB_PROFILE} apply -f -
# apiVersion: cluster.open-cluster-management.io/v1beta1
# kind: Placement
# metadata:
#   name: ramen-demo-placement
#   namespace: ramen-system
# spec:
#   predicates:
#   - requiredClusterSelector:
#       labelSelector: {}
# EOF

# Create Klusterlet CRs for proper registration
log_info "Creating Klusterlet CRs for cluster registration..."
for cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    log_info "Creating Klusterlet CR on ${cluster}..."
    cat <<EOF | kubectl --context=${cluster} apply -f -
apiVersion: operator.open-cluster-management.io/v1
kind: Klusterlet
metadata:
  name: klusterlet
spec:
  registrationImagePullSpec: quay.io/open-cluster-management/registration:latest
  workImagePullSpec: quay.io/open-cluster-management/work:latest
  clusterName: ${cluster}
  namespace: open-cluster-management-agent
  externalServerURLs:
  - url: https://${HUB_IP}:8443
EOF
done

# Create ClusterClaims in DR clusters (these should be created automatically by klusterlet, but ensuring they exist)
log_info "Creating ClusterClaims in DR clusters..."
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

# Wait for ManagedClusters to be accepted
log_info "Waiting for ManagedClusters to be accepted..."
for cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
   wait_for_deployment "$cluster" "klusterlet" "open-cluster-management"
    # log_info "Waiting for ManagedCluster ${cluster} to be available..."
    # timeout=180
    # while [ $timeout -gt 0 ]; do
    #     status=$(kubectl --context="${HUB_PROFILE}" get managedcluster "${cluster}" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}' 2>/dev/null || echo "")
    #     if [ "$status" = "True" ]; then
    #         log_success "✅ ManagedCluster ${cluster} is available"
    #         break
    #     elif [ "$status" = "False" ]; then
    #         log_info "ManagedCluster ${cluster} is connecting..."
    #     fi
    #     echo -n "."
    #     sleep 10
    #     timeout=$((timeout-10))
    # done
    
    # if [ $timeout -le 0 ]; then
    #     log_warning "⚠️ ManagedCluster ${cluster} not available yet"
    # fi
done

# Wait for PlacementRule to get placement decisions
# Replace lines 188-194 with:
log_info "Waiting for Placement to get placement decisions..."
sleep 30
ensure_resource "$HUB_PROFILE" "placement" "ramen-demo-placement" "ramen-system" 60
placement_decisions=$(kubectl --context=${HUB_PROFILE} get placement ramen-demo-placement -n ramen-system -o jsonpath='{.status.numberOfSelectedClusters}' 2>/dev/null || echo "0")
if [ "$placement_decisions" != "0" ]; then
    log_success "✅ Placement has selected $placement_decisions clusters"
else
    log_warning "⚠️ Placement has no selected clusters yet"
fi

log_success "OCM prerequisites created successfully"

# ===============================================
# 🔍 VERIFICATION COMMANDS
# ===============================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    🔍 OCM SETUP VERIFICATION                    "
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "📋 1. Check Hub OCM Components:"
echo "   kubectl --context=ramen-hub get pods -n open-cluster-management-hub"
kubectl --context=ramen-hub get pods -n open-cluster-management-hub 2>/dev/null || echo "   ❌ No pods found in open-cluster-management-hub namespace"

echo ""
echo "📋 2. Check ManagedClusters:"
echo "   kubectl --context=ramen-hub get managedcluster"
kubectl --context=ramen-hub get managedcluster

echo ""
echo "📋 3. Check ManagedCluster Status Details:"
for cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    echo "   🔍 ${cluster} status:"
    echo "   kubectl --context=ramen-hub describe managedcluster ${cluster}"
    kubectl --context=ramen-hub get managedcluster ${cluster} -o jsonpath='{"   Status: "}{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}{"\n"}' 2>/dev/null || echo "   Status: Unknown"
done

echo ""
echo "📋 4. Check Placement Status:"
echo "   kubectl --context=ramen-hub describe placement ramen-demo-placement -n ramen-system | head -20"
kubectl --context=ramen-hub describe placement ramen-demo-placement -n ramen-system | head -20
echo ""
echo "📋 5. Check DR Cluster Agents:"
for cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    echo "   🔍 ${cluster} agents:"
    echo "   kubectl --context=${cluster} get pods -n open-cluster-management-agent"
    kubectl --context=${cluster} get pods -n open-cluster-management-agent 2>/dev/null || \
    kubectl --context=${cluster} get pods -n open-cluster-management 2>/dev/null || \
    echo "   ❌ No agent pods found"
done

echo ""
echo "📋 6. Check ClusterClaims:"
for cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    echo "   🔍 ${cluster} clusterclaims:"
    echo "   kubectl --context=${cluster} get clusterclaim"
    kubectl --context=${cluster} get clusterclaim 2>/dev/null || echo "   ❌ No clusterclaims found"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    🎯 NEXT STEPS                    "
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "🚀 1. Install RamenDR Operators:"
echo "   echo \"3\" | ./demo/scripts/minikube_quick-install.sh"

echo ""
echo "🚀 2. Setup DR Policy:"
echo "   ./demo/scripts/setup-dr-policy.sh"

echo ""
echo "🚀 3. Deploy S3 Storage:"
echo "   ./demo/scripts/deploy-ramendr-s3.sh"

echo ""
echo "🚀 4. Setup Cross-Cluster S3 Access:"
echo "   ./demo/scripts/setup-cross-cluster-s3.sh"

echo ""
echo "🔧 Troubleshooting Commands:"
echo "   # Check OCM CRDs:"
echo "   kubectl --context=ramen-hub get crd | grep cluster.open-cluster-management"
echo ""
echo "   # Check placement functionality:"
echo "   kubectl --context=ramen-hub logs -n open-cluster-management-hub deployment/cluster-manager-placement-controller"
echo ""
echo "   # Force ManagedCluster reconciliation:"
echo "   kubectl --context=ramen-hub patch managedcluster ramen-dr1 --type='merge' -p='{\"metadata\":{\"labels\":{\"reconcile\":\"'$(date +%s)'\"}}}}'"

echo ""
echo "✅ OCM Setup Complete! Ready for RamenDR installation."