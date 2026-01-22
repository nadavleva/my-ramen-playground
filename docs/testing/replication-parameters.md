<!--
SPDX-FileCopyrightText: The RamenDR authors
SPDX-License-Identifier: Apache-2.0
-->

# CSI Replication API Parameters and Values

This document provides comprehensive information about the CSI Replication API parameters used in Ramen and Ceph CSI implementations, based on analysis of the codebase and test files.

## Overview

The CSI Replication API defines gRPC services for managing volume replication between storage systems. This document focuses on the `EnableVolumeReplicationRequest` and `DisableVolumeReplicationRequest` parameters and their values as implemented in Ceph CSI and consumed by Ramen.

## CSI Replication API Structure

### EnableVolumeReplicationRequest

```protobuf
message EnableVolumeReplicationRequest {
  string volume_id = 1;  // deprecated, use replication_source
  map<string, string> parameters = 2;
  map<string, string> secrets = 3;
  string replication_id = 4;
  ReplicationSource replication_source = 5;
}
```

### DisableVolumeReplicationRequest

```protobuf
message DisableVolumeReplicationRequest {
  string volume_id = 1;  // deprecated, use replication_source
  map<string, string> parameters = 2;
  map<string, string> secrets = 3;
  string replication_id = 4;
  ReplicationSource replication_source = 5;
}
```

## Ceph CSI Implementation Parameters

The Ceph CSI driver implements CSI replication using RBD mirroring. Here are the key parameters handled:

### Core Parameters

| Parameter Key | Type | Description | Valid Values | Default | Used In |
|---------------|------|-------------|--------------|---------|---------|
| `mirroringMode` | string | RBD mirroring mode | `"snapshot"`, `"journal"` | `"snapshot"` | EnableVolumeReplication |
| `force` | bool | Force option for operations | `"true"`, `"false"` | `"false"` | DisableVolumeReplication, ResyncVolume |
| `schedulingInterval` | string | Snapshot scheduling interval | `"1m"`, `"1h"`, `"1d"`, etc. | - | EnableVolumeReplication (PromoteVolume) |
| `schedulingStartTime` | string | ISO 8601 start time | `"14:00:00-05:00"` | - | EnableVolumeReplication (PromoteVolume) |
| `flattenMode` | string | Parent image handling | `"never"`, `"force"` | `"never"` | EnableVolumeReplication |

### Mirroring Mode Values

- **`snapshot`** (default): Uses RBD snapshots to propagate images between clusters. Supports scheduling for periodic snapshots.
- **`journal`**: Uses RBD journaling for real-time replication. Does not support scheduling parameters.

### Validation Rules

1. **Scheduling validation**: Only snapshot mode supports scheduling parameters. Journal mode will ignore scheduling parameters if provided.

2. **Interval format**: Must match regex `^\d+[mhd]$` (e.g., "30m", "2h", "1d")

3. **Parameter precedence**: Parameters in the `parameters` map take precedence over defaults

## Implementation Details

### Parameter Extraction Functions

The Ceph CSI implementation provides utility functions for parameter extraction:

```go
// From internal/csi-addons/rbd/replication.go
func getMirroringMode(ctx context.Context, parameters map[string]string) (librbd.ImageMirrorMode, error)
func getForceOption(ctx context.Context, parameters map[string]string) (bool, error)
func getFlattenMode(ctx context.Context, parameters map[string]string) (types.FlattenMode, error)
func getSchedulingDetails(parameters map[string]string) (admin.Interval, admin.StartTime)
func validateSchedulingDetails(ctx context.Context, parameters map[string]string) error
```

### Validation Logic

```go
// Scheduling is only supported for snapshot mode
func validateSchedulingDetails(ctx context.Context, parameters map[string]string) error {
    val := parameters[imageMirroringKey]

    switch imageMirroringMode(val) {
    case imageMirrorModeJournal:
        // Journal mode doesn't support scheduling
        if _, ok := parameters[schedulingIntervalKey]; ok {
            return status.Errorf(codes.InvalidArgument,
                "%s parameter cannot be used with %s mirror mode",
                schedulingIntervalKey, string(imageMirrorModeJournal))
        }
    case imageMirrorModeSnapshot:
        // Validate interval format (must end with m/h/d)
        interval := parameters[schedulingIntervalKey]
        if interval != "" {
            if err := validateSchedulingInterval(interval); err != nil {
                return status.Error(codes.InvalidArgument, err.Error())
            }
        }
    }
    return nil
}
```

## Ramen Implementation and Test Data

Ramen uses the CSI replication APIs through Kubernetes CRDs. The test data shows how these parameters are configured in practice.

### VolumeReplicationClass Examples

From test data in `test/addons/rbd-mirror/start-data/vrc.yaml`:

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplicationClass
metadata:
  name: vrc-1m
spec:
  provisioner: rook-ceph.rbd.csi.ceph.com
  parameters:
    replication.storage.openshift.io/replication-secret-name: rook-csi-rbd-provisioner
    replication.storage.openshift.io/replication-secret-namespace: rook-ceph
    schedulingInterval: 1m  # Maps to CSI parameter
```

### VolumeReplication Examples

From test data in `test/addons/rbd-mirror/test-data/vr-1m.yaml`:

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplication
metadata:
  name: vr-1m
spec:
  volumeReplicationClass: vrc-1m
  replicationState: primary
  dataSource:
    kind: PersistentVolumeClaim
    name: rbd-pvc
  autoResync: true
```

## Test Coverage

### Ceph CSI Tests

The Ceph CSI implementation includes comprehensive tests for parameter handling:

- **File**: `internal/csi-addons/rbd/replication_test.go`
- **Coverage**: Parameter validation, scheduling details, mirroring modes
- **Key test cases**: Valid parameter combinations, error conditions, edge cases

Example test cases from the test file:

```go
// Valid snapshot mode with scheduling
{
    name: "valid parameters",
    parameters: map[string]string{
        imageMirroringKey:      string(imageMirrorModeSnapshot),
        schedulingIntervalKey:  "1h",
        schedulingStartTimeKey: "14:00:00-05:00",
    },
    wantErr: false,
}

// Valid journal mode (no scheduling)
{
    name: "when mirroring mode is journal",
    parameters: map[string]string{
        imageMirroringKey:     string(imageMirrorModeJournal),
        schedulingIntervalKey: "1h",  // This should be ignored
    },
    wantErr: false,
}
```

### Ramen Integration Tests

Ramen's volume replication group tests cover the integration:

- **File**: `internal/controller/vrg_volrep_test.go`
- **Coverage**: VRG reconciliation, state transitions, error handling
- **Test data**: Various VolumeReplicationClass configurations

## Usage Examples

### Enable Volume Replication - Snapshot Mode with Scheduling

```go
req := &replication.EnableVolumeReplicationRequest{
    VolumeId: "csi-vol-12345",
    Parameters: map[string]string{
        "mirroringMode":       "snapshot",
        "schedulingInterval":  "1h",
        "schedulingStartTime": "14:00:00-05:00",
        "flattenMode":         "never",
    },
    Secrets: map[string]string{
        "admin": "secret-key",
    },
}
```

### Enable Volume Replication - Journal Mode (Real-time)

```go
req := &replication.EnableVolumeReplicationRequest{
    VolumeId: "csi-vol-12345",
    Parameters: map[string]string{
        "mirroringMode": "journal",
        "flattenMode":   "force",
    },
    Secrets: map[string]string{
        "admin": "secret-key",
    },
}
```

### Disable Volume Replication

```go
req := &replication.DisableVolumeReplicationRequest{
    VolumeId: "csi-vol-12345",
    Parameters: map[string]string{
        "force": "true",  // Force disable even if issues
    },
    Secrets: map[string]string{
        "admin": "secret-key",
    },
}
```

## References

### Code References

- **Ceph CSI Replication Implementation**: [`internal/csi-addons/rbd/replication.go`](https://github.com/nadavleva/ceph-csi/blob/devel/internal/csi-addons/rbd/replication.go)
- **Ceph CSI Replication Tests**: [`internal/csi-addons/rbd/replication_test.go`](https://github.com/nadavleva/ceph-csi/blob/devel/internal/csi-addons/rbd/replication_test.go)
- **CSI Addons Specification**: [`vendor/github.com/csi-addons/spec/lib/go/replication/`](https://github.com/nadavleva/ceph-csi/blob/devel/vendor/github.com/csi-addons/spec/lib/go/replication/)

### Ramen Test Data

- **RBD Mirror Test Data**: [`test/addons/rbd-mirror/test-data/`](https://github.com/RamenDR/ramen/tree/main/test/addons/rbd-mirror/test-data)
- **VRG Tests**: [`internal/controller/vrg_volrep_test.go`](https://github.com/RamenDR/ramen/blob/main/internal/controller/vrg_volrep_test.go)

### CSI Specification

- **CSI Addons Replication Spec**: https://github.com/csi-addons/spec/tree/main/replication

## Notes

- The `volume_id` field is deprecated in favor of `replication_source`
- Scheduling parameters are only valid for snapshot-based mirroring
- The `force` parameter is primarily used for cleanup operations
- Parameter validation is performed at the CSI driver level
- Ramen translates Kubernetes CRD parameters to CSI gRPC calls