#!/bin/bash
# AWS S3 Setup for RamenDR
# 
# This script creates S3 bucket and configures RamenDR for AWS S3

set -e

# Configuration
BUCKET_NAME="ramen-metadata-${USER}-$(date +%Y%m%d)"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-default}"

echo "🚀 Setting up AWS S3 for RamenDR..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity --profile "$PROFILE" >/dev/null 2>&1; then
    echo "❌ AWS credentials not configured. Please run:"
    echo "   aws configure --profile $PROFILE"
    echo "   # Or set up ~/.aws/credentials and ~/.aws/config"
    exit 1
fi

echo "✅ AWS credentials verified for profile: $PROFILE"

# Create S3 bucket
echo "📦 Creating S3 bucket: $BUCKET_NAME"
if aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION" --profile "$PROFILE"; then
    echo "✅ Bucket created successfully"
else
    echo "⚠️  Bucket creation failed (may already exist)"
fi

# Enable versioning (recommended for RamenDR)
echo "🔄 Enabling versioning on bucket..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled \
    --profile "$PROFILE"

# Create lifecycle policy (optional - cleanup old versions)
echo "🗂️ Setting up lifecycle policy..."
cat > /tmp/lifecycle.json << EOF
{
    "Rules": [
        {
            "ID": "RamenDRMetadataCleanup",
            "Status": "Enabled",
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 30
            },
            "AbortIncompleteMultipartUpload": {
                "DaysAfterInitiation": 7
            }
        }
    ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
    --bucket "$BUCKET_NAME" \
    --lifecycle-configuration file:///tmp/lifecycle.json \
    --profile "$PROFILE"

rm /tmp/lifecycle.json

# Create AWS S3 secret for RamenDR
echo "🔐 Creating AWS S3 secret for RamenDR..."
ACCESS_KEY=$(aws configure get aws_access_key_id --profile "$PROFILE")
SECRET_KEY=$(aws configure get aws_secret_access_key --profile "$PROFILE")

kubectl create secret generic ramen-s3-secret \
    --namespace=ramen-system \
    --from-literal=AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
    --from-literal=AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
    --dry-run=client -o yaml > examples/s3-config/aws-s3-secret.yaml

echo "✅ AWS S3 secret file created: examples/s3-config/aws-s3-secret.yaml"

# Create AWS DRCluster configuration
echo "🌐 Creating AWS DRCluster configuration..."
cat > examples/dr-policy/aws-drclusters.yaml << EOF
# AWS S3 DRCluster Configuration for RamenDR
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRCluster
metadata:
  name: aws-east-cluster
  namespace: ramen-system
spec:
  s3ProfileName: aws-s3-production
  region: us-east-1
  # Add your storage classes
  # storageClasses:
  # - name: gp3
  #   provisioner: ebs.csi.aws.com

---
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRCluster
metadata:
  name: aws-west-cluster
  namespace: ramen-system
spec:
  s3ProfileName: aws-s3-production
  region: us-west-2
  # Add your storage classes
  # storageClasses:
  # - name: gp3
  #   provisioner: ebs.csi.aws.com
EOF

echo "✅ AWS DRCluster configuration created: examples/dr-policy/aws-drclusters.yaml"

# Summary
echo ""
echo "🎉 AWS S3 setup completed!"
echo ""
echo "📋 Summary:"
echo "   • Bucket: $BUCKET_NAME"
echo "   • Region: $AWS_REGION"
echo "   • Versioning: Enabled"
echo "   • Lifecycle: 30-day cleanup"
echo ""
echo "📝 Next steps:"
echo "   1. Apply the secret: kubectl apply -f examples/s3-config/aws-s3-secret.yaml"
echo "   2. Update DRCluster configs with your actual bucket name and storage classes"
echo "   3. Apply DRCluster configs: kubectl apply -f examples/dr-policy/aws-drclusters.yaml"
echo ""
echo "⚠️  Remember to:"
echo "   • Update bucket name in your DRCluster specs"
echo "   • Configure appropriate IAM permissions"
echo "   • Update storage classes for your environment"
