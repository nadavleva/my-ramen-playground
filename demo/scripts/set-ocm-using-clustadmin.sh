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

    # Try multiple methods to get the hub token
    HUB_TOKEN=""
    
    # Method 1: Extract from clusteradm-init.log (most immediate)
    if [ -z "$HUB_TOKEN" ]; then
        log_info "Attempting to extract token from init log..."
        HUB_TOKEN=$(grep -oP '(?<=--hub-token )[^ ]+' clusteradm-init.log 2>/dev/null | head -1 || echo "")
    fi
    
    # Method 2: Use clusteradm get token (reliable but may need secret)
    if [ -z "$HUB_TOKEN" ]; then
        log_info "Attempting to get token using clusteradm..."
        HUB_TOKEN_RAW=$(clusteradm get token --context $HUB_CONTEXT 2>/dev/null || echo "")
        if [[ "$HUB_TOKEN_RAW" == *"--hub-token"* ]]; then
            # Extract token from the join command output
            HUB_TOKEN=$(echo "$HUB_TOKEN_RAW" | grep -oP '(?<=--hub-token )[^\s]+' | head -1 || echo "")
        elif [[ "$HUB_TOKEN_RAW" == token=* ]]; then
            # Remove "token=" prefix if present and clean whitespace/newlines
            HUB_TOKEN=$(echo "$HUB_TOKEN_RAW" | sed 's/^token=//' | tr -d '\n\r\t ' | sed 's/[[:space:]]//g' || echo "")
        fi
    fi
    
    # Method 3: Extract from secret (wait for it if needed)
    if [ -z "$HUB_TOKEN" ]; then
        log_info "Waiting for agent-registration-bootstrap secret to be created..."
        max_wait=60
        count=0
        while [ $count -lt $max_wait ]; do
            if kubectl --context=$HUB_CONTEXT -n open-cluster-management get secret agent-registration-bootstrap >/dev/null 2>&1; then
                log_success "Secret found after ${count}s"
                HUB_TOKEN=$(kubectl --context=$HUB_CONTEXT -n open-cluster-management get secret agent-registration-bootstrap -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null | tr -d '\n\r\t ' | sed 's/[[:space:]]//g' || echo "")
                break
            fi
            sleep 1
            ((count++))
            if [ $((count % 10)) -eq 0 ]; then
                log_info "Still waiting for secret... (${count}s/${max_wait}s)"
            fi
        done
    fi

    rm -f clusteradm-init.log
else
    log_info "OCM hub is already initialized. Skipping 'clusteradm init'."
    
    # Try to retrieve the existing hub token using multiple methods
    HUB_TOKEN=""
    
    # Method 1: Use clusteradm get token (most reliable)
    log_info "Attempting to get existing token using clusteradm..."
    HUB_TOKEN_RAW=$(clusteradm get token --context $HUB_CONTEXT 2>/dev/null || echo "")
    if [[ "$HUB_TOKEN_RAW" == *"--hub-token"* ]]; then
        # Extract token from the join command output
        HUB_TOKEN=$(echo "$HUB_TOKEN_RAW" | grep -oP '(?<=--hub-token )[^\s]+' | head -1 || echo "")
    elif [[ "$HUB_TOKEN_RAW" == token=* ]]; then
        # Remove "token=" prefix if present and clean whitespace/newlines
        HUB_TOKEN=$(echo "$HUB_TOKEN_RAW" | sed 's/^token=//' | tr -d '\n\r\t ' | sed 's/[[:space:]]//g' || echo "")
    fi
    
    # Method 2: Extract from secret
    if [ -z "$HUB_TOKEN" ]; then
        log_info "Attempting to get existing token from secret..."
        HUB_TOKEN=$(kubectl --context=$HUB_CONTEXT -n open-cluster-management get secret agent-registration-bootstrap -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null | tr -d '\n\r\t ' | sed 's/[[:space:]]//g' || echo "")
    fi
fi

# Validate that we have a token
if [ -z "$HUB_TOKEN" ]; then
    log_error "Failed to retrieve hub token using any method!"
    log_info "Debug information:"
    log_info "- Checking if clustermanager exists:"
    kubectl --context=$HUB_CONTEXT get clustermanager 2>/dev/null || log_info "  No clustermanager found"
    log_info "- Checking secrets in open-cluster-management namespace:"
    kubectl --context=$HUB_CONTEXT -n open-cluster-management get secrets 2>/dev/null || log_info "  No secrets found"
    exit 1
fi

log_success "Hub token retrieved successfully"

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
log_info "🔗 Joining DR clusters to OCM hub..."

# Join all DR clusters first
JOINED_CLUSTERS=()
for ctx in "${DR_CONTEXTS[@]}"; do
    log_info "Joining cluster $ctx to hub..."
    kubectl config use-context $ctx

    # Check if cluster is already joined (has klusterlet resources)
    if kubectl get klusterlet --no-headers 2>/dev/null | grep -q .; then
        log_info "Cluster $ctx already has klusterlet, checking status..."
        # Check if it's properly connected
        if kubectl --context=$HUB_CONTEXT get managedcluster $ctx >/dev/null 2>&1; then
            log_success "✅ Cluster $ctx already joined and registered"
            JOINED_CLUSTERS+=("$ctx")
            continue
        else
            log_info "Cluster $ctx has klusterlet but no ManagedCluster on hub - will process in acceptance phase"
            JOINED_CLUSTERS+=("$ctx")
            continue
        fi
    fi

    # Validate required variables before attempting join
    if [ -z "$HUB_TOKEN" ]; then
        log_error "Hub token is empty, cannot join cluster $ctx"
        continue
    fi
    
    if [ -z "$HUB_SERVER" ]; then
        log_error "Hub server URL is empty, cannot join cluster $ctx"
        continue
    fi

    log_info "Using hub server URL: $HUB_SERVER"
    log_info "Using hub token: ${HUB_TOKEN:0:20}..." # Show only first 20 chars for security

    # Attempt to join the cluster with error handling
    log_long_operation "Joining cluster $ctx to hub" "1-2 minutes"
    if clusteradm join --hub-token "$HUB_TOKEN" --hub-apiserver "$HUB_SERVER" --wait --cluster-name "$ctx"; then
        log_success "✅ Joined cluster $ctx to hub"
        JOINED_CLUSTERS+=("$ctx")
    else
        log_error "❌ Failed to join cluster $ctx to hub"
        log_info "Manual recovery commands:"
        log_info "  kubectl config use-context $ctx"
        log_info "  clusteradm join --hub-token '$HUB_TOKEN' --hub-apiserver '$HUB_SERVER' --wait --cluster-name '$ctx'"
    fi
done

echo ""
log_info "🤝 Accepting joined clusters on the hub..."
kubectl config use-context $HUB_CONTEXT

# First, approve any pending CSRs for the joined clusters
log_info "Checking and approving pending CSRs..."
for ctx in "${JOINED_CLUSTERS[@]}"; do
    log_info "Approving CSRs for cluster $ctx..."
    # Get all pending CSRs for this cluster and approve them
    PENDING_CSRS=$(kubectl --context=$HUB_CONTEXT get csr --no-headers 2>/dev/null | awk '$6=="Pending" && $1 ~ /'"$ctx"'/ {print $1}' || echo "")
    if [ -n "$PENDING_CSRS" ]; then
        for csr in $PENDING_CSRS; do
            log_info "Approving CSR: $csr"
            kubectl --context=$HUB_CONTEXT certificate approve "$csr" || log_warning "Failed to approve CSR $csr"
        done
        log_success "Approved CSRs for $ctx"
    else
        log_info "No pending CSRs found for $ctx"
    fi
done

# Wait for ManagedClusters to be created after CSR approval
log_info "Waiting for ManagedClusters to be created..."
sleep 10

# Accept all successfully joined clusters
for ctx in "${JOINED_CLUSTERS[@]}"; do
    log_info "Accepting cluster $ctx on hub..."
    
    # Check if ManagedCluster exists first
    if ! kubectl --context=$HUB_CONTEXT get managedcluster "$ctx" >/dev/null 2>&1; then
        log_warning "ManagedCluster $ctx not found, waiting a bit longer..."
        sleep 5
        if ! kubectl --context=$HUB_CONTEXT get managedcluster "$ctx" >/dev/null 2>&1; then
            log_error "ManagedCluster $ctx still not found after waiting - may need manual intervention"
            continue
        fi
    fi
    
    if clusteradm accept --clusters "$ctx" --context $HUB_CONTEXT; then
        log_success "✅ Hub accepted cluster $ctx"
    else
        log_warning "Failed to accept cluster $ctx on hub, trying manual patch..."
        if kubectl --context=$HUB_CONTEXT patch managedcluster $ctx --type='merge' -p '{"spec":{"hubAcceptsClient":true}}'; then
            log_success "✅ Manually accepted cluster $ctx"
        else
            log_error "❌ Failed to accept cluster $ctx"
        fi
    fi
done

echo ""
log_info "🔍 Final verification of OCM setup..."

# Wait a moment for everything to stabilize
sleep 5

log_info "Managed clusters status:"
kubectl --context=$HUB_CONTEXT get managedcluster -o wide

echo ""
log_info "Klusterlet status on DR clusters:"
for ctx in "${DR_CONTEXTS[@]}"; do
    echo "  $ctx:"
    kubectl --context=$ctx get klusterlet -o wide 2>/dev/null | grep -v "NAME" | sed 's/^/    /' || echo "    No klusterlet found"
done

echo ""
log_info "Creating required namespaces..."
kubectl --context=ramen-hub create namespace nginx-test --dry-run=client -o yaml | kubectl --context=ramen-hub apply -f - || log_warning "nginx-test namespace already exists or failed to create"
kubectl --context=ramen-hub create namespace ramen-system --dry-run=client -o yaml | kubectl --context=ramen-hub apply -f - || log_warning "ramen-system namespace already exists or failed to create"

log_info "Applying ManagedClusterSetBinding..."
kubectl --context=ramen-hub apply -f "$SCRIPT_DIR/../yaml/ocm/managedclustersetbindings.yaml"

log_info "Checking placement decisions..."
kubectl --context=$HUB_CONTEXT get placementdecision --all-namespaces -A -o wide 2>/dev/null | grep -v "No resources" || echo "  No placement decisions found yet"

log_success "✅ OCM hub and managed clusters setup completed!"

# Show summary
echo ""
log_info "📋 Setup Summary:"
TOTAL_CLUSTERS=$(echo "${DR_CONTEXTS[@]}" | wc -w)
JOINED_COUNT=${#JOINED_CLUSTERS[@]}
log_info "  Total DR clusters: $TOTAL_CLUSTERS"
log_info "  Successfully joined: $JOINED_COUNT"
if [ $JOINED_COUNT -eq $TOTAL_CLUSTERS ]; then
    log_success "  All clusters joined successfully! 🎉"
else
    log_warning "  Some clusters failed to join. Check the logs above for manual recovery commands."
fi