# RamenDR Storage Demo Guide

## Overview
This section provides storage-focused demos that can run independently of RamenDR, allowing you to validate storage infrastructure before deploying disaster recovery.

## Storage Options

### 1. HostPath Storage (Default)
- **Use case**: Development, testing
- **Pros**: Simple, fast setup
- **Cons**: No real replication, single-node

### 2. Ceph Storage (Production-like)  
- **Use case**: Production validation, realistic testing
- **Pros**: Distributed, replication-capable, snapshot support
- **Cons**: Resource intensive, complex setup

## Demo Workflows

### Quick Storage Test
```bash
# Test basic storage provisioning
./demo/scripts/storage/quick-storage-test.sh
```

### Full Ceph Demo
```bash
# Complete Ceph setup and validation
./demo/scripts/storage/full-ceph-demo.sh
```

### Storage Benchmark
```bash
# Performance testing
./demo/scripts/storage/storage-benchmark.sh
```

## Troubleshooting
See `STORAGE_TROUBLESHOOTING.md` for common issues and solutions.
