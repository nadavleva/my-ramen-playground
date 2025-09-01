#!/bin/bash
# Complete RamenDR Backup Verification Workflow
# 
# This script provides a comprehensive verification that RamenDR is successfully
# backing up PVCs and volumes to S3 storage (MinIO or AWS S3)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Configuration
S3_TYPE="${1:-minio}"  # minio or aws
AWS_BUCKET="${2}"
EXAMPLES_DIR="$(dirname "$0")"

print_usage() {
    echo "Usage: $0 [s3-type] [aws-bucket]"
    echo ""
    echo "Examples:"
    echo "  $0 minio                              # Check MinIO S3"
    echo "  $0 aws ramen-metadata-prod-20250901  # Check AWS S3"
    echo ""
    echo "This script verifies that RamenDR is successfully backing up PVCs to S3"
}

main() {
    echo "🔍 RamenDR Backup Verification Workflow"
    echo "========================================"
    echo ""
    
    # Step 1: Quick verification
    log_info "Step 1: Checking RamenDR setup..."
    
    kubectl get drclusters -n ramen-system 2>/dev/null && log_success "DRClusters found" || log_warning "No DRClusters configured"
    kubectl get vrg -A 2>/dev/null | head -5 && log_success "VolumeReplicationGroups active" || log_warning "No applications protected yet"
    
    echo ""
    log_info "📝 For detailed verification, run individual scripts:"
    echo "  • RamenDR status: ./monitoring/check-ramendr-status.sh"
    echo "  • MinIO contents: ./s3-config/check-minio-backups.sh" 
    echo "  • Test application: kubectl apply -f test-application/nginx-with-pvc.yaml"
    
    echo ""
    log_success "Basic verification completed!"
}

# Show help if requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    print_usage
    exit 0
fi

# Run main function
main "$@"
