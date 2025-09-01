#!/bin/bash
# MinIO Bucket Creation for RamenDR
# 
# This script creates the required S3 bucket in MinIO for RamenDR metadata storage

set -e

BUCKET_NAME="ramen-metadata"
MINIO_ENDPOINT="http://localhost:9000"
MINIO_USER="minioadmin"
MINIO_PASSWORD="minioadmin"

echo "🚀 Creating MinIO bucket for RamenDR..."

# Download and setup MinIO client if not present
if ! command -v mc &> /dev/null; then
    echo "📦 Installing MinIO client..."
    curl -O https://dl.min.io/client/mc/release/linux-amd64/mc
    chmod +x mc
    sudo mv mc /usr/local/bin/ 2>/dev/null || echo "⚠️  Could not install globally, using local mc"
fi

# Setup port-forward to MinIO (if running in cluster)
echo "�� Setting up port-forward to MinIO..."
kubectl port-forward -n minio-system service/minio 9000:9000 &
PF_PID=$!
sleep 3

# Configure MinIO client
echo "⚙️ Configuring MinIO client..."
mc alias set minio $MINIO_ENDPOINT $MINIO_USER $MINIO_PASSWORD

# Create bucket
echo "📦 Creating bucket: $BUCKET_NAME"
mc mb minio/$BUCKET_NAME || echo "✅ Bucket may already exist"

# Verify bucket
echo "🔍 Verifying bucket creation..."
mc ls minio/

# Cleanup
kill $PF_PID 2>/dev/null || true

echo "✅ MinIO bucket '$BUCKET_NAME' is ready for RamenDR!"
