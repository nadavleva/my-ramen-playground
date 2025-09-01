#!/bin/bash
# Check MinIO S3 Bucket for RamenDR Backups
# 
# This script helps verify that RamenDR is successfully storing metadata in MinIO

set -e

BUCKET_NAME="ramen-metadata"
MINIO_ENDPOINT="http://localhost:9000"

echo "🔍 Checking RamenDR backups in MinIO S3 bucket..."

# Setup port-forward to MinIO
echo "🔗 Setting up port-forward to MinIO..."
kubectl port-forward -n minio-system service/minio 9000:9000 &
PF_PID=$!
sleep 3

# Configure MinIO client  
echo "⚙️ Configuring MinIO client..."
mc alias set minio $MINIO_ENDPOINT minioadmin minioadmin

echo ""
echo "📋 === MinIO Bucket Contents ==="
echo "🗂️ Listing all objects in bucket: $BUCKET_NAME"
mc ls minio/$BUCKET_NAME/ --recursive || echo "❌ Bucket empty or not accessible"

echo ""
echo "📊 === Bucket Statistics ==="
mc stat minio/$BUCKET_NAME/ || echo "❌ Cannot get bucket stats"

echo ""
echo "🔍 === RamenDR Metadata Objects ==="
echo "Looking for RamenDR-specific metadata..."

# Check for common RamenDR object patterns
echo "• VolumeReplicationGroup metadata:"
mc ls minio/$BUCKET_NAME/ --recursive | grep -i "vrg\|volume.*replication" || echo "  No VRG metadata found"

echo "• DRPlacementControl metadata:"  
mc ls minio/$BUCKET_NAME/ --recursive | grep -i "drpc\|placement.*control" || echo "  No DRPC metadata found"

echo "• Application metadata:"
mc ls minio/$BUCKET_NAME/ --recursive | grep -i "app\|namespace" || echo "  No application metadata found"

echo ""
echo "📈 === Bucket Size Analysis ==="
TOTAL_SIZE=$(mc du minio/$BUCKET_NAME/ 2>/dev/null | tail -1 | awk '{print $1}' || echo "0B")
OBJECT_COUNT=$(mc ls minio/$BUCKET_NAME/ --recursive 2>/dev/null | wc -l || echo "0")

echo "• Total size: $TOTAL_SIZE"  
echo "• Object count: $OBJECT_COUNT"

if [[ "$OBJECT_COUNT" -gt 0 ]]; then
    echo "✅ RamenDR is storing data in MinIO!"
else
    echo "⚠️  No objects found - RamenDR may not be active yet"
fi

# Cleanup
kill $PF_PID 2>/dev/null || true

echo ""
echo "✅ MinIO backup check completed!"
