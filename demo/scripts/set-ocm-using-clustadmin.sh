#!/bin/bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

HUB_CONTEXT="ramen-hub"
DR_CONTEXTS=("ramen-dr1" "ramen-dr2")

OCM_REPO_DIR="/tmp/ocm-repo"
LOCAL_HUB_CRD_DIR="$SCRIPT_DIR/../yaml/ocm/hub-crds"
LOCAL_KLUSTERLET_CRD_DIR="$SCRIPT_DIR/../yaml/ocm/klusterlet-crds"

# Clone OCM repo if not present
if [ ! -d "$OCM_REPO_DIR" ]; then
    log_info "Cloning OCM repo to $OCM_REPO_DIR..."
    git clone https://github.com/open-cluster-management-io/ocm.git "$OCM_REPO_DIR"
fi

# Copy hub CRDs if not present
if [ ! -f "$LOCAL_HUB_CRD_DIR/0000_01_operator.open-cluster-management.io_clustermanagers.crd.yaml" ]; then
    mkdir -p "$LOCAL_HUB_CRD_DIR"
    cp "$OCM_REPO_DIR/deploy/cluster-manager/config/crds/"*.yaml "$LOCAL_HUB_CRD_DIR/"
fi

# Copy klusterlet CRDs if not present
if [ ! -f "$LOCAL_KLUSTERLET_CRD_DIR/0000_00_operator.open-cluster-management.io_klusterlets.crd.yaml" ]; then
    mkdir -p "$LOCAL_KLUSTERLET_CRD_DIR"
    cp "$OCM_REPO_DIR/deploy/klusterlet/config/crds/"*.yaml "$LOCAL_KLUSTERLET_CRD_DIR/"
fi

# Check if the hub is already initialized
if ! kubectl --context=$HUB_CONTEXT get clustermanager > /dev/null 2>&1; then
    log_step "Initializing OCM hub..."
    clusteradm init --context=$HUB_CONTEXT --resource-qos-class ResourceRequirement \
        --resource-limits cpu=1000m,memory=1Gi \
        --resource-requests cpu=500m,memory=512Mi --wait | tee clusteradm-init.log

    # Extract the hub token and hub IP from the log
    HUB_TOKEN=$(kubectl --context=$HUB_CONTEXT -n open-cluster-management get secret agent-registration-bootstrap -o jsonpath='{.data.token}' | base64 -d)
    # HUB_TOKEN=$(grep -oP '(?<=--hub-token )[^ ]+' clusteradm-init.log | head -1)
    log_info "Hub token: $HUB_TOKEN"
    rm -f clusteradm-init.log
else
    log_info "OCM hub is already initialized. Skipping 'clusteradm init'."
    # Retrieve the existing hub token using clusteradm
    HUB_TOKEN=$(clusteradm get token --context $HUB_CONTEXT)
    if [ -z "$HUB_TOKEN" ]; then
        log_error "Failed to retrieve the hub token using clusteradm get token."
        exit 1
    fi
    log_info "Retrieved existing hub token."
fi

# Get the hub IP from minikube
HUB_IP=$(minikube -p ramen-hub ip)
log_info "Hub cluster IP: $HUB_IP"
HUB_SERVER=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$HUB_CONTEXT\")].cluster.server}")
log_info "Hub server URL: $HUB_SERVER"

# Install core OCM hub CRDs early
log_info "🔧 Installing core OCM hub and Klusterlet CRDs..."
OCM_REPO_DIR="/tmp/ocm-repo"
LOCAL_HUB_CRD_DIR="$SCRIPT_DIR/../yaml/ocm/hub-crds"
LOCAL_KLUSTERLET_CRD_DIR="$SCRIPT_DIR/../yaml/ocm/klusterlet-crds"
CLONED_REPO=false

# Clone the OCM repo if needed
if [ ! -d "$OCM_REPO_DIR" ]; then
    log_info "Cloning OCM repo to $OCM_REPO_DIR..."
    git clone https://github.com/open-cluster-management-io/ocm.git "$OCM_REPO_DIR" || log_error "Failed to clone OCM repo"
    CLONED_REPO=true
fi

# Copy hub CRDs
if [ ! -d "$LOCAL_HUB_CRD_DIR" ]; then
    mkdir -p "$LOCAL_HUB_CRD_DIR"
    if [ -d "$OCM_REPO_DIR/deploy/cluster-manager/config/crds/" ] && [ "$(ls -A "$OCM_REPO_DIR/deploy/cluster-manager/config/crds/")" ]; then
        log_info "Copying hub CRDs from $OCM_REPO_DIR/deploy/cluster-manager/config/crds/"
        cp "$OCM_REPO_DIR/deploy/cluster-manager/config/crds/"*.yaml "$LOCAL_HUB_CRD_DIR/" || log_warning "Failed to copy hub CRDs"
    else
        log_error "Hub CRDs not found in $OCM_REPO_DIR/deploy/cluster-manager/config/crds/"
        exit 1
    fi
fi

# Apply hub CRDs using kustomize if kustomization.yaml exists
if [ -f "$LOCAL_HUB_CRD_DIR/kustomization.yaml" ]; then
    log_info "Applying hub CRDs using kustomize..."
    kubectl --context=$HUB_CONTEXT apply -k "$LOCAL_HUB_CRD_DIR/" || log_error "Failed to apply hub CRDs using kustomize"
else
    log_info "Applying hub CRDs individually..."
    for crd_file in "$LOCAL_HUB_CRD_DIR"/*.yaml; do
        if [[ "$crd_file" != *"kustomization.yaml" ]]; then
            apply_yaml_file_safe "$HUB_CONTEXT" "$crd_file" "OCM hub CRD"
        fi
    done
fi

# Apply klusterlet CRDs to each DR cluster (prefer kustomize if kustomization.yaml exists)
for ctx in "${DR_CONTEXTS[@]}"; do
    if [ -f "$LOCAL_KLUSTERLET_CRD_DIR/kustomization.yaml" ]; then
        log_info "Applying klusterlet CRDs using kustomize on $ctx..."
        kubectl --context=$ctx apply -k "$LOCAL_KLUSTERLET_CRD_DIR" || log_warning "Kustomize apply failed on $ctx, falling back to individual CRDs"
    fi
    for crd in "$LOCAL_KLUSTERLET_CRD_DIR"/*.yaml; do
        [[ "$crd" == *kustomization.yaml ]] && continue
        apply_yaml_file_safe "$ctx" "$crd" "Klusterlet CRD"
    done
done

# Cleanup temp repo only if cloned in this run
if [ "$CLONED_REPO" = true ] && [ -d "$OCM_REPO_DIR" ]; then
    log_info "Cleaning up temporary OCM repo at $OCM_REPO_DIR"
    # rm -rf "$OCM_REPO_DIR"
fi

echo ""
log_info "Run the following join command on each managed cluster:"
for ctx in "${DR_CONTEXTS[@]}"; do
    kubectl config use-context $ctx

    log_info "Joining cluster $ctx to hub..."
    # echo "clusteradm join --hub-token $HUB_TOKEN --hub-apiserver https://$HUB_IP:8443 --wait --cluster-name $ctx"
    # clusteradm join --hub-token $HUB_TOKEN --hub-apiserver https://$HUB_IP:8443 --resource-qos-class ResourceRequirement \
    #     --resource-limits cpu=1000m,memory=1Gi \
    #     --resource-requests cpu=500m,memory=512Mi --wait --cluster-name $ctx

    log_info "Using hub server URL: $HUB_SERVER"

    clusteradm join --hub-token $HUB_TOKEN --hub-apiserver $HUB_SERVER --wait --cluster-name $ctx

    log_success "✅ Joined cluster $ctx to hub"
    log_info "Allowing hub to accept the cluster..."
    kubectl config use-context $HUB_CONTEXT
    clusteradm accept --clusters $ctx
done

echo ""
echo "After joining, accept the clusters on the hub:"
for ctx in "${DR_CONTEXTS[@]}"; do
    echo "On context: $ctx"
    echo "kubectl --context=$HUB_CONTEXT patch managedcluster $ctx --type='merge' -p '{\"spec\":{\"hubAcceptsClient\":true}}'"
    log_info "ManagedCluster $ctx accepted."
done

echo ""
echo "Check managed clusters:"
kubectl --context=$HUB_CONTEXT get managedcluster --all-namespaces -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No managedclusters found"

log_info "Add ManagedClusterSetBinding to allow DR clusters to join default cluster set"
kubectl --context=ramen-hub apply -f "$SCRIPT_DIR/../yaml/ocm/managedclustersetbindings.yaml"

log_info "Verifying Placementdecision..."
kubectl --context=$HUB_CONTEXT get placementdecision --all-namespaces -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No managedclusters found"
log_success "✅ OCM hub and managed clusters setup completed!"