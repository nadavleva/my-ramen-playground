#!/bin/bash

set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

log_info "🔧 Installing Storage Dependencies for RamenDR"
echo "============================================="

# Main installation function
main() {
    log_info "Installing storage replication dependencies..."
    # Install VolSync CRDs on DR clusters if missing
    VOLSYNC_CRD_SRC="$SCRIPT_DIR/../yaml/volsync"
    for ctx in ramen-dr1 ramen-dr2; do
        for crd in volsync.backube_replicationsources.yaml volsync.backube_replicationdestinations.yaml; do
            if [ -f "$VOLSYNC_CRD_SRC/$crd" ]; then
                if ! kubectl --context="$ctx" get crd "${crd%.yaml}.volsync.backube" >/dev/null 2>&1; then
                    echo "Applying $crd to $ctx..."
                    kubectl --context="$ctx" apply -f "$VOLSYNC_CRD_SRC/$crd"
                else
                    echo "$crd already present on $ctx"
                fi
            else
                echo "$crd not found in $VOLSYNC_CRD_SRC"
            fi
        done
    done
    
    # Use the working install-missing-resource-classes.sh script
    if [ -f "$SCRIPT_DIR/install-missing-resource-classes.sh" ]; then
        log_info "Using install-missing-resource-classes.sh for storage dependencies..."
        "$SCRIPT_DIR/install-missing-resource-classes.sh"
    else
        log_error "install-missing-resource-classes.sh not found!"
        return 1
    fi
    
    log_success "✅ Storage dependencies installation completed!"
}

# Allow script to be called directly or sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi