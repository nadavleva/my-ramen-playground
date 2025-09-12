# Storage Dependencies

This directory contains local copies of storage-related Custom Resource Definitions (CRDs) and controllers that are required by the RamenDR operator. This approach eliminates external download dependencies and follows the same pattern used by OCM resources.

## Structure

```
demo/yaml/storage-dependencies/
├── crds/                           # Custom Resource Definitions
│   ├── kustomization.yaml         # Kustomization for all CRDs
│   ├── volumereplications.yaml    # Volume Replication CRDs
│   ├── volumereplicationclasses.yaml
│   ├── volumegroupreplications.yaml
│   ├── volumegroupreplicationclasses.yaml
│   ├── volumesnapshots.yaml       # Snapshot CRDs
│   ├── volumesnapshotclasses.yaml
│   ├── volumesnapshotcontents.yaml
│   ├── volumegroupsnapshotclasses.yaml
│   └── networkfenceclass.yaml     # Fence CRDs
├── controllers/                    # Controller deployments
│   ├── kustomization.yaml
│   ├── rbac-snapshot-controller.yaml
│   └── setup-snapshot-controller.yaml
├── resource-classes/               # Demo resource classes for kind clusters
│   ├── kustomization.yaml
│   ├── demo-volumesnapshotclass.yaml
│   └── demo-volumereplicationclass.yaml
└── kustomization.yaml             # Main kustomization
```

## Usage

The `install_storage_dependencies()` function in `demo/scripts/kind_quick-install.sh` uses these local files automatically:

```bash
# Install all storage dependencies using local files
kubectl apply -k demo/yaml/storage-dependencies/

# Install specific components
kubectl apply -k demo/yaml/storage-dependencies/crds/
kubectl apply -k demo/yaml/storage-dependencies/controllers/
kubectl apply -k demo/yaml/storage-dependencies/resource-classes/
```

## Benefits

1. **Reliability**: No dependency on external URLs that might be unavailable
2. **Speed**: Local files load faster than external downloads
3. **Consistency**: Fixed versions ensure reproducible deployments
4. **Organization**: Kustomization files provide clear structure like OCM pattern
5. **Error Resilience**: Installation continues even if some components fail

## Source References

- **Volume Replication CRDs**: https://github.com/csi-addons/volume-replication-operator
- **Snapshot CRDs & Controllers**: https://github.com/kubernetes-csi/external-snapshotter
- **Demo Resource Classes**: Created for kind cluster compatibility

## Maintenance

To update these files with newer versions:

1. Download updated CRDs from their source repositories
2. Replace the files in the appropriate directories
3. Test with `kubectl kustomize` to ensure validity
4. Update version references in this README if needed