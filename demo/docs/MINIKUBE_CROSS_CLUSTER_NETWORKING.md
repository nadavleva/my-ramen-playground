# Minikube Cross-Cluster Networking for RamenDR

## The Challenge

By design, **each minikube profile creates an isolated cluster** with its own network range:

```bash
# Example cluster IPs
Hub cluster (ramen-hub): 192.168.49.2
DR1 cluster (ramen-dr1): 192.168.58.2
DR2 cluster (ramen-dr2): 192.168.39.2
```

**Result**: Clusters cannot communicate directly, breaking RamenDR's cross-cluster S3 access.

## Why Standard Solutions Don't Work

### ❌ `minikube tunnel`
- Requires sudo privileges
- Often hangs/fails with docker driver
- Complex setup for multiple clusters
- Not reliable for demos

### ❌ Ingress Controllers
- Need ingress setup on each cluster
- Complex DNS configuration
- Overkill for demo environments

### ❌ CNI/Network Plugins
- Complex setup for local development
- Not suitable for quick demos

## ✅ Recommended Solution: Shared Infrastructure

Deploy shared services (like MinIO S3) on the **host network**, accessible to all minikube clusters.

### Implementation Steps

1. **Stop in-cluster MinIO:**
```bash
kubectl --context=ramen-hub scale deployment minio -n minio-system --replicas=0
```

2. **Start host-network MinIO:**
```bash
docker run -d \
  --name ramen-minio-shared \
  --network host \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  -v /tmp/minio-data:/data \
  minio/minio server /data --console-address ":9001"
```

3. **Update RamenDR S3 configuration:**
```yaml
# In ramen-dr-cluster-operator-config ConfigMap
s3StoreProfiles:
- s3ProfileName: minio-s3
  s3Bucket: ramen-metadata
  s3Region: us-east-1
  s3CompatibleEndpoint: http://HOST_IP:9000  # Use actual host IP
  s3SecretRef:
    name: ramen-s3-secret
    namespace: ramen-system
```

### Benefits

✅ **Simple**: One shared MinIO for all clusters  
✅ **Reliable**: No complex networking or tunneling  
✅ **Demo-friendly**: Easy to set up and tear down  
✅ **Universal access**: All clusters can reach the same S3 endpoint  
✅ **Troubleshooting**: Easy to test connectivity  

### Testing Connectivity

```bash
# From host
curl -I http://localhost:9000/

# From any minikube cluster
kubectl run test --image=curlimages/curl --rm -i --restart=Never \
  -- curl -I http://HOST_IP:9000/
```

Both should return `HTTP/1.1 400 Bad Request` (confirming connectivity).

## Access Points

- **MinIO Console**: `http://HOST_IP:9001`
- **S3 API**: `http://HOST_IP:9000`
- **Login**: `minioadmin` / `minioadmin`

## Alternative Solutions

### For Production-Like Demos
- Use external cloud S3 (AWS, MinIO cloud)
- Set up ingress with proper DNS
- Use kind clusters with shared networks

### For Development
- Single minikube cluster (no cross-cluster)
- External services (cloud S3, external MinIO)
- Docker Compose for shared infrastructure

## Key Takeaway

**Minikube's isolation is by design and expected.** For multi-cluster demos like RamenDR, shared infrastructure on the host network is the most practical solution.
