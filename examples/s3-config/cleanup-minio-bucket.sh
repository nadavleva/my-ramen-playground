#!/bin/bash
# MinIO Bucket Cleanup for RamenDR
# 
# This script removes all RamenDR metadata from MinIO S3 buckets

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

BUCKET_NAME="ramen-metadata"
MINIO_ENDPOINT="http://localhost:9000"
MINIO_USER="minioadmin"
MINIO_PASSWORD="minioadmin"

echo "=============================================="
echo "🧹 MinIO S3 Bucket Cleanup for RamenDR"
echo "=============================================="
echo ""

log_warning "This will permanently delete ALL data in the ramen-metadata bucket:"
echo "   • RamenDR application metadata"
echo "   • VolumeReplicationGroup backups"
echo "   • Cluster state information"
echo ""

# Confirmation
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Bucket cleanup cancelled by user"
    exit 0
fi

echo ""
log_info "🚀 Starting S3 bucket cleanup..."

# Check if MinIO is running
if ! kubectl get pods -n minio-system -l app=minio >/dev/null 2>&1; then
    log_error "MinIO is not running or not accessible"
    echo ""
    log_info "💡 To start MinIO:"
    echo "   kubectl apply -f ../minio-deployment/minio-s3.yaml"
    echo "   kubectl wait --for=condition=available deployment/minio -n minio-system"
    exit 1
fi

log_success "MinIO is accessible"

# Setup port-forward to MinIO
log_info "🔌 Setting up port-forward to MinIO..."
kubectl port-forward -n minio-system service/minio 9000:9000 >/dev/null 2>&1 &
PF_PID=$!
sleep 3

# Check for MinIO client
if ! command -v mc &> /dev/null; then
    log_info "📦 MinIO client not found, attempting to install..."
    
    # Try to download mc client
    if curl -s -O https://dl.min.io/client/mc/release/linux-amd64/mc 2>/dev/null; then
        chmod +x mc
        MC_CMD="./mc"
        log_success "MinIO client downloaded locally"
    else
        log_error "Could not download MinIO client"
        echo ""
        log_info "💡 Manual installation:"
        echo "   curl -O https://dl.min.io/client/mc/release/linux-amd64/mc"
        echo "   chmod +x mc"
        echo "   sudo mv mc /usr/local/bin/"
        kill $PF_PID 2>/dev/null || true
        exit 1
    fi
else
    MC_CMD="mc"
    log_success "MinIO client found"
fi

# Configure MinIO client
log_info "⚙️ Configuring MinIO client..."
$MC_CMD alias set minio $MINIO_ENDPOINT $MINIO_USER $MINIO_PASSWORD >/dev/null 2>&1

# Check if bucket exists
log_info "🔍 Checking for ramen-metadata bucket..."
if $MC_CMD ls minio/$BUCKET_NAME >/dev/null 2>&1; then
    log_success "Found ramen-metadata bucket"
    
    # Show bucket contents before cleanup
    echo ""
    log_info "📋 Current bucket contents:"
    $MC_CMD ls --recursive minio/$BUCKET_NAME/ 2>/dev/null || echo "   (bucket is empty)"
    
    echo ""
    log_info "🗑️ Removing all bucket contents..."
    
    # Remove all objects from bucket
    if $MC_CMD rm --recursive --force minio/$BUCKET_NAME/ 2>/dev/null; then
        log_success "All bucket contents removed"
    else
        log_warning "Some items may not have been removed (bucket might be empty)"
    fi
    
    # Verify cleanup
    echo ""
    log_info "🔍 Verifying cleanup..."
    remaining_objects=$($MC_CMD ls --recursive minio/$BUCKET_NAME/ 2>/dev/null | wc -l)
    if [ "$remaining_objects" -eq 0 ]; then
        log_success "✅ Bucket is now empty"
    else
        log_warning "⚠️  $remaining_objects objects remain in bucket"
        $MC_CMD ls --recursive minio/$BUCKET_NAME/ | head -5
    fi
    
else
    log_info "No ramen-metadata bucket found - nothing to clean"
fi

# List all buckets for verification
echo ""
log_info "📋 All MinIO buckets:"
$MC_CMD ls minio/ 2>/dev/null || echo "   No buckets found"

# Cleanup
kill $PF_PID 2>/dev/null || true

# Clean up local mc if downloaded
if [ "$MC_CMD" = "./mc" ]; then
    rm -f ./mc
    log_info "Cleaned up local MinIO client"
fi

echo ""
log_success "🎉 S3 bucket cleanup completed!"

echo ""
log_info "📝 Verification steps:"
echo "   1. Access MinIO console: kubectl port-forward -n minio-system service/minio 9001:9001"
echo "   2. Open browser: http://localhost:9001"
echo "   3. Login: minioadmin / minioadmin"
echo "   4. Verify ramen-metadata bucket is empty or deleted"

echo ""
log_success "Ready for fresh RamenDR demo!"
