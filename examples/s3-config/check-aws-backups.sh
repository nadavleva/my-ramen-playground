#!/bin/bash
# Check AWS S3 Bucket for RamenDR Backups
# 
# This script helps verify that RamenDR is successfully storing metadata in AWS S3

set -e

BUCKET_NAME="${1:-ramen-metadata-production}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-default}"

if [[ -z "$1" ]]; then
    echo "Usage: $0 <bucket-name> [aws-profile]"
    echo "Example: $0 ramen-metadata-production-20250901"
    exit 1
fi

echo "🔍 Checking RamenDR backups in AWS S3 bucket..."
echo "• Bucket: $BUCKET_NAME"
echo "• Region: $AWS_REGION"  
echo "• Profile: $PROFILE"

# Check AWS credentials
if ! aws sts get-caller-identity --profile "$PROFILE" >/dev/null 2>&1; then
    echo "❌ AWS credentials not configured for profile: $PROFILE"
    exit 1
fi

echo ""
echo "📋 === S3 Bucket Contents ==="
echo "🗂️ Listing all objects in bucket: $BUCKET_NAME"
aws s3 ls "s3://$BUCKET_NAME/" --recursive --profile "$PROFILE" || echo "❌ Bucket empty or not accessible"

echo ""
echo "📊 === Bucket Statistics ==="
TOTAL_SIZE=$(aws s3 ls "s3://$BUCKET_NAME/" --recursive --summarize --profile "$PROFILE" 2>/dev/null | grep "Total Size" | awk '{print $3, $4}' || echo "Unknown")
OBJECT_COUNT=$(aws s3 ls "s3://$BUCKET_NAME/" --recursive --summarize --profile "$PROFILE" 2>/dev/null | grep "Total Objects" | awk '{print $3}' || echo "0")

echo "• Total size: $TOTAL_SIZE"
echo "• Object count: $OBJECT_COUNT"

echo ""
echo "🔍 === RamenDR Metadata Objects ==="
echo "Looking for RamenDR-specific metadata..."

# Check for common RamenDR object patterns
echo "• VolumeReplicationGroup metadata:"
aws s3 ls "s3://$BUCKET_NAME/" --recursive --profile "$PROFILE" | grep -i "vrg\|volume.*replication" || echo "  No VRG metadata found"

echo "• DRPlacementControl metadata:"
aws s3 ls "s3://$BUCKET_NAME/" --recursive --profile "$PROFILE" | grep -i "drpc\|placement.*control" || echo "  No DRPC metadata found"

echo "• Application metadata:"
aws s3 ls "s3://$BUCKET_NAME/" --recursive --profile "$PROFILE" | grep -i "app\|namespace" || echo "  No application metadata found"

echo ""
echo "🔐 === Bucket Security Check ==="
echo "• Bucket versioning:"
aws s3api get-bucket-versioning --bucket "$BUCKET_NAME" --profile "$PROFILE" | jq -r '.Status // "Disabled"' || echo "Unknown"

echo "• Bucket encryption:"
aws s3api get-bucket-encryption --bucket "$BUCKET_NAME" --profile "$PROFILE" >/dev/null 2>&1 && echo "Enabled" || echo "Disabled"

if [[ "$OBJECT_COUNT" -gt 0 ]]; then
    echo ""
    echo "✅ RamenDR is storing data in AWS S3!"
    echo ""
    echo "📝 Recent objects (last 10):"
    aws s3 ls "s3://$BUCKET_NAME/" --recursive --profile "$PROFILE" | sort -k1,2 | tail -10
else
    echo ""
    echo "⚠️  No objects found - RamenDR may not be active yet"
fi

echo ""
echo "✅ AWS S3 backup check completed!"
