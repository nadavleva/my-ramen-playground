#!/bin/bash

set -e

unset KUBECONFIG

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Minikube profiles
HUB_PROFILE="ramen-hub"
DR1_PROFILE="ramen-dr1"
DR2_PROFILE="ramen-dr2"

echo -e "${GREEN}Setting up cross-cluster S3 access...${NC}"

# Get MinIO endpoint from hub cluster
MINIO_HUB_IP=$(minikube --profile ${HUB_PROFILE} ip)
MINIO_ENDPOINT="http://${MINIO_HUB_IP}:30900"
MINIO_CONSOLE_URL="http://${MINIO_HUB_IP}:30901"

echo "MinIO endpoint: ${MINIO_ENDPOINT}"
echo "MinIO console: ${MINIO_CONSOLE_URL}"

# Function to create S3 credentials secret
create_s3_secret() {
    local context=$1
    local namespace=$2
    echo "Creating S3 credentials secret in ${context}/${namespace}..."
    
    cat <<EOF | kubectl --context=${context} apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ramen-s3-credentials
  namespace: ${namespace}
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: minioadmin
  AWS_SECRET_ACCESS_KEY: minioadmin
EOF
}

# Create/update S3 credentials in hub cluster
create_s3_secret "${HUB_PROFILE}" "ramen-system"

# Create DRClusterConfig in all clusters
# Create DRClusterConfig in all clusters
# echo -e "${GREEN}Creating DRClusterConfig resources...${NC}"
# for profile in "${DR1_PROFILE}" "${DR2_PROFILE}" "${HUB_PROFILE}" ; do
#     echo "Creating DRClusterConfig in ${profile}..."
#     cat <<EOF | kubectl --context=${profile} apply -f -
# apiVersion: ramendr.openshift.io/v1alpha1
# kind: DRClusterConfig
# metadata:
#   name: ${profile}-config
#   namespace: ramen-system
# spec:
#   clusterID: ${profile}
# EOF
# done

# ...existing code...

# Create DRClusterConfig on hub cluster
echo -e "${GREEN}Creating DRClusterConfig resources on hub...${NC}"
cat <<EOF | kubectl --context=${HUB_PROFILE} apply -f -
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRClusterConfig
metadata:
  name: ${DR1_PROFILE}-config
  namespace: ramen-system
spec:
  drClusterOperatorDeploymentConfig:
    replicas: 1
---
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRClusterConfig
metadata:
  name: ${DR2_PROFILE}-config
  namespace: ramen-system
spec:
  drClusterOperatorDeploymentConfig:
    replicas: 1
EOF

# Copy secrets and update ConfigMap in DR clusters
for profile in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    echo -e "${GREEN}Configuring ${profile}...${NC}"
    
    # Create ramen-system namespace if it doesn't exist
    kubectl --context=${profile} create namespace ramen-system --dry-run=client -o yaml | \
        kubectl --context=${profile} apply -f -
    
    # Create S3 credentials in DR cluster
    create_s3_secret "${profile}" "ramen-system"
    
    # Update ConfigMap with correct MinIO endpoint
    cat <<EOF | kubectl --context=${profile} apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ramen-operator-config
  namespace: ramen-system
data:
  s3-endpoint: "${MINIO_ENDPOINT}"
  s3-region: "us-east-1"
  s3-bucket: "ramen-bucket"
EOF
done

# # Create DRClusterConfig in all clusters
# echo -e "${GREEN}Creating DRClusterConfig resources...${NC}"
# for profile in "${HUB_PROFILE}" "${DR1_PROFILE}" "${DR2_PROFILE}"; do
#     echo "Creating DRClusterConfig in ${profile}..."
#     cat <<EOF | kubectl --context=${profile} apply -f -
# apiVersion: ramendr.openshift.io/v1alpha1
# kind: DRClusterConfig
# metadata:
#   name: ${profile}-config
#   namespace: ramen-system
# spec:
#   clusterID: ${profile}
# EOF
# done

# Delete existing DRClusters with finalizer handling
echo -e "${GREEN}Deleting existing DRClusters...${NC}"

# Function to remove finalizers from DRCluster
remove_drcluster_finalizers() {
    local cluster=$1
    echo "Removing finalizers from DRCluster ${cluster}..."
    kubectl --context=${HUB_PROFILE} patch drcluster ${cluster} -n ramen-system \
        --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' || true
}

# Delete DRClusters with finalizer handling
for dr_cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    if kubectl --context=${HUB_PROFILE} get drcluster ${dr_cluster} -n ramen-system &>/dev/null; then
        echo "Found existing DRCluster ${dr_cluster}, removing..."
        remove_drcluster_finalizers ${dr_cluster}
        kubectl --context=${HUB_PROFILE} delete drcluster -n ramen-system ${dr_cluster} --timeout=30s || true
    fi
done

# Wait for deletion to complete
for dr_cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    while kubectl --context=${HUB_PROFILE} get drcluster ${dr_cluster} -n ramen-system &>/dev/null; do
        echo "Waiting for DRCluster ${dr_cluster} to be deleted..."
        sleep 2
    done
done

# Create DRClusters in hub cluster
# Create DRClusters in hub cluster
echo -e "${GREEN}Creating DRCluster resources...${NC}"
for dr_cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    cat <<EOF | kubectl --context=${HUB_PROFILE} apply -f -
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRCluster
metadata:
  name: ${dr_cluster}
  namespace: ramen-system
  labels:
    app.kubernetes.io/name: ramen
    app.kubernetes.io/component: dr-cluster
    cluster.ramendr.openshift.io/name: dr1
spec:
  s3ProfileName: minio-s3
  region: us-east-1
EOF
done

# Create DRPolicy in hub cluster
echo -e "${GREEN}Creating DRPolicy...${NC}"
cat <<EOF | kubectl --context=${HUB_PROFILE} apply -f -
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRPolicy
metadata:
  name: ramen-dr-policy
  namespace: ramen-system
  labels:
    app.kubernetes.io/name: ramen
    app.kubernetes.io/component: dr-policy
spec:
  drClusters:
  - ${DR1_PROFILE}
  - ${DR2_PROFILE}
  schedulingInterval: 5m
  replicationClassSelector:
    matchLabels:
      ramendr.openshift.io/replicationID: ramen-volsync
EOF

# Create OCM resources first
echo -e "${GREEN}Creating OCM resources...${NC}"
for dr_cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    # Create ManagedCluster
    cat <<EOF | kubectl --context=${HUB_PROFILE} apply -f -
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: ${dr_cluster}
  labels:
    cluster.open-cluster-management.io/clusterset: default
spec:
  hubAcceptsClient: true
EOF
done

# Create placement rule for nginx demo
cat <<EOF | kubectl --context=${HUB_PROFILE} apply -f -
apiVersion: apps.open-cluster-management.io/v1
kind: PlacementRule
metadata:
  name: nginx-test-placement
  namespace: nginx-demo
spec:
  clusterConditions:
    - type: ManagedClusterConditionAvailable
      status: "True"
  clusterSelector:
    matchLabels:
      cluster.open-cluster-management.io/clusterset: default
EOF

# Update RamenConfig with correct S3 profile
cat <<EOF | kubectl --context=${HUB_PROFILE} apply -f -
apiVersion: ramendr.openshift.io/v1alpha1
kind: RamenConfig
metadata:
  name: ramen-operator-config
  namespace: ramen-system
spec:
  s3StoreProfiles:
  - s3ProfileName: minio-s3
    s3Bucket: ramen-bucket
    s3CompatibleEndpoint: ${MINIO_ENDPOINT}
    s3Region: us-east-1
    s3SecretRef:
      name: ramen-s3-credentials
      namespace: ramen-system
EOF

# Add these lines before restarting operators
echo -e "${GREEN}Waiting for clusters to join hub...${NC}"
for dr_cluster in "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    kubectl --context=${HUB_PROFILE} wait --for=condition=ManagedClusterJoined \
        managedcluster/${dr_cluster} --timeout=60s
done


# Restart RamenDR operators to pick up new configuration
echo -e "${GREEN}Restarting RamenDR operators...${NC}"
for ctx in "${HUB_PROFILE}" "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    echo "Restarting operator in ${ctx}..."
    kubectl --context=${ctx} delete pod -n ramen-system -l control-plane=controller-manager
    
    # Wait for pod to be ready
    echo "Waiting for operator to be ready..."
    kubectl --context=${ctx} wait --for=condition=ready pod \
        -n ramen-system -l control-plane=controller-manager \
        --timeout=60s
done


# Verify MinIO accessibility
echo -e "${GREEN}Verifying S3 connectivity...${NC}"

for profile in "${HUB_PROFILE}" "${DR1_PROFILE}" "${DR2_PROFILE}"; do
    echo "Testing ${profile}..."
    if kubectl --context=${profile} run s3-test-${profile} \
        --image=curlimages/curl \
        --restart=Never \
        --rm -i --quiet -- \
        curl -s -o /dev/null -w "%{http_code}\n" ${MINIO_ENDPOINT}/minio/health/live | grep -q "200"; then
        echo -e "${GREEN}✓ ${profile} can access MinIO${NC}"
    else
        echo -e "${RED}✗ ${profile} cannot access MinIO${NC}"
        exit 1
    fi
done

echo -e "${GREEN}Setup complete - all operators restarted and ready!${NC}"