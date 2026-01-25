<!--
SPDX-FileCopyrightText: The RamenDR authors
SPDX-License-Identifier: Apache-2.0
-->

# Setting Up Local Environment for CSI Replication API Testing

This guide provides step-by-step instructions for setting up a local multi-cluster environment to test CSI Replication APIs with Ceph RBD mirroring between primary and secondary clusters.

## Overview

The RamenDR testing environment uses two minikube clusters with:
- **Primary cluster (dr1)**: Active cluster where applications run initially
- **Secondary cluster (dr2)**: Standby cluster for failover/relocation
- **Hub cluster**: Manages multi-cluster operations via OCM (Open Cluster Management)
- **Ceph Storage**: RBD block storage with mirroring enabled between clusters
- **CSI Addons**: Provides replication APIs for volume management

## Prerequisites

### System Requirements

- Linux system with virtualization support
- At least 16GB RAM, 8 CPU cores recommended
- 100GB free disk space
- Network connectivity for downloading images

### Required Tools

Install the tools listed in the [test README](../README.md#setup-on-linux):

- `libvirt` virtualization
- `minikube` (v1.37.0+)
- `kubectl` (v1.34.1+)
- `clusteradm` (v0.11.2)
- `subctl` (v0.22.0+)
- `velero` (v1.16.1+)
- `helm` (v4.0.1+)
- `virtctl` (v1.6.0+)
- `mc` (MinIO client)
- `kustomize`
- `argocd` (v2.11.3+)
- `kubectl-gather` (v0.8.0+)

## Environment Setup

### 1. Activate Virtual Environment

```bash
cd test
source venv  # Activates the (ramen) virtual environment
```

### 2. Setup Host for Testing

Run this once before starting any environment:

```bash
drenv setup envs/regional-dr.yaml
```

This configures minikube and the host system for multi-cluster testing.

### 3. Start the Multi-Cluster Environment

Start the regional DR environment with 3 clusters (hub, dr1, dr2):

```bash
drenv start envs/regional-dr.yaml
```

This process takes approximately 20-30 minutes and performs:

#### Cluster Creation
- **hub**: Management cluster with OCM hub components
- **dr1**: Primary cluster with full Ceph deployment
- **dr2**: Secondary cluster with full Ceph deployment

#### Component Deployment Sequence

1. **Ceph Storage Setup** (per cluster):
   - Rook operator deployment
   - Ceph cluster initialization
   - RBD storage pool creation with mirroring enabled
   - CephFS filesystem setup
   - Rook toolbox for debugging

2. **OCM Setup**:
   - Hub cluster: OCM hub and controller components
   - Managed clusters (dr1, dr2): OCM agents and cluster registration

3. **CSI Components**:
   - External snapshotter controllers
   - ODF external snapshotter
   - CSI addons for replication support
   - OLM (Operator Lifecycle Manager)

4. **Additional Services**:
   - MinIO for object storage
   - Velero for backup/restore
   - Submariner for cross-cluster networking
   - ArgoCD for application management

5. **RBD Mirroring Setup**:
   - RBD mirror daemons on both clusters
   - Peer secrets exchange between clusters
   - VolumeReplicationClass creation for different intervals (1m, 5m)
   - Pool mirroring configuration

## Cluster Architecture

### Primary Cluster (dr1)
- **Role**: Active application cluster
- **Storage**: Ceph RBD pool with mirroring enabled
- **CSI**: Full CSI driver with replication capabilities
- **State**: Applications deployed and running

### Secondary Cluster (dr2)
- **Role**: Standby cluster for DR operations
- **Storage**: Ceph RBD pool with mirroring enabled
- **CSI**: Full CSI driver with replication capabilities
- **State**: Ready to receive applications via failover/relocate

### Hub Cluster
- **Role**: Management and orchestration
- **Components**: OCM hub, Submariner broker, ArgoCD
- **Function**: Coordinates DR operations between managed clusters

## Ceph Storage Configuration

### RBD Pool Configuration

The test environment creates a replicated Ceph block pool with mirroring:

```yaml
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: replicapool
  namespace: rook-ceph
spec:
  replicated:
    size: 1
    requireSafeReplicaSize: false
  mirroring:
    enabled: true
    mode: image  # Per-image mirroring
    snapshotSchedules:
      - interval: 2m
        startTime: 14:00:00-05:00
```

### RBD Mirroring Setup

The `rbd-mirror` addon configures bidirectional mirroring:

1. **Peer Discovery**: Extracts site names and bootstrap tokens
2. **Secret Exchange**: Creates Kubernetes secrets with peer credentials
3. **Pool Peering**: Configures mirroring peers on both clusters
4. **VolumeReplicationClass**: Creates VRCs for different sync intervals
5. **Health Monitoring**: Waits for mirroring daemons and pool health

### Volume Replication Classes

Two VolumeReplicationClasses are created automatically:

- `vrc-1m`: 1-minute sync interval
- `vrc-5m`: 5-minute sync interval

Both use snapshot-based mirroring mode.

## Testing CSI Replication APIs

### 1. Access Cluster Contexts

```bash
# List available contexts
kubectl config get-contexts

# Switch to primary cluster
kubectl config use-context dr1

# Switch to secondary cluster
kubectl config use-context dr2
```

### 2. Deploy Test Application

Use the basic test to deploy a sample application:

```bash
# Deploy application on primary cluster
test/basic-test/deploy dr1

# Enable DR protection
test/basic-test/enable-dr dr1
```

This deploys a busybox application with persistent storage that gets protected by RamenDR.

### 3. Monitor Volume Replication

Check VolumeReplication resources:

```bash
# On primary cluster
kubectl get volumereplications -n deployment-rbd

# Check replication status
kubectl describe volumereplication <name> -n deployment-rbd
```

### 4. Test DR Operations

#### Failover (Primary → Secondary)
```bash
test/basic-test/failover dr2
```

#### Relocate (Secondary → Primary)
```bash
test/basic-test/relocate dr1
```

### 5. Manual CSI API Testing

You can manually create VolumeReplication resources to test CSI APIs:

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplication
metadata:
  name: test-vr
  namespace: test-ns
spec:
  volumeReplicationClass: vrc-1m
  replicationState: primary
  dataSource:
    kind: PersistentVolumeClaim
    name: test-pvc
  autoResync: true
```

Apply and monitor:
```bash
kubectl apply -f test-vr.yaml
kubectl get volumereplication test-vr -n test-ns -w
```

## Debugging and Troubleshooting

### Check Cluster Status

```bash
# Minikube cluster status
minikube status -p dr1
minikube status -p dr2
minikube status -p hub
```

### Ceph Health

```bash
# Access Ceph toolbox
kubectl exec -it deploy/rook-ceph-tools -n rook-ceph -- bash

# Check cluster health
ceph status

# Check RBD mirror status
rbd mirror pool status replicapool
```

### RBD Mirror Logs

```bash
# Enable debug logging
RBD_MIRROR_DEBUG=1 test/addons/rbd-mirror/start dr1 dr2

# View mirror daemon logs
kubectl logs -f deploy/rook-ceph-rbd-mirror-a -n rook-ceph
```

### Volume Replication Debugging

```bash
# Check CSI addons controller logs
kubectl logs -f deploy/csi-addons-controller-manager -n csi-addons-system

# Gather cluster information
kubectl gather
```

## Environment Management

### Stop Environment (Keep VMs)

```bash
drenv stop envs/regional-dr.yaml
```

### Start Environment (Reuse VMs)

```bash
drenv start envs/regional-dr.yaml
```

### Delete Environment (Destroy Everything)

```bash
drenv delete envs/regional-dr.yaml
```

### Clean Up Host Changes

```bash
drenv cleanup
```

## Advanced Configuration

### Custom Environment Variables

```bash
# Enable RBD mirror debug logging
RBD_MIRROR_DEBUG=1 drenv start envs/regional-dr.yaml

# Use different minikube driver
export MINIKUBE_DRIVER=kvm2
drenv start envs/regional-dr.yaml
```

### Modifying Cluster Configuration

Edit `envs/regional-dr.yaml` to customize:
- CPU/memory allocation per cluster
- Storage pool sizes
- Network configuration
- Addon versions

### Using External Clusters

For testing with existing clusters, use `envs/regional-dr-external.yaml.example` as a starting point.

## Performance Considerations

- **Memory**: Each cluster needs ~4-6GB RAM
- **CPU**: Each cluster needs 2-4 CPU cores
- **Storage**: Plan for 50GB+ per cluster
- **Network**: Ensure stable connectivity for image downloads

## Common Issues

### Cluster Startup Failures
- Check virtualization setup: `systemctl status libvirtd`
- Verify user in libvirt group: `groups $USER`
- Check available resources: `free -h`, `nproc`

### Ceph Health Issues
- Wait for full cluster convergence (10-15 minutes)
- Check pod statuses: `kubectl get pods -n rook-ceph`
- Review Ceph logs: `kubectl logs -f deploy/rook-ceph-operator -n rook-ceph`

### Mirroring Setup Failures
- Verify network connectivity between clusters
- Check Submariner status: `subctl show connections`
- Review mirror daemon logs for authentication issues

## Next Steps

Once your environment is running:

1. **Explore CSI APIs**: Use `kubectl` to examine VolumeReplication resources
2. **Test DR Scenarios**: Run the basic test suite
3. **Develop Custom Tests**: Create your own test applications
4. **Debug Issues**: Use the debugging tools mentioned above

For more information, see:
- [Test Environment Overview](../README.md)
- [CSI Replication Parameters](./replication-parameters.md)
- [Basic Test Documentation](../../test/basic-test/)