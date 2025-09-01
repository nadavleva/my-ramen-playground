#!/bin/bash

# MinIO Web Console Access Script
# Provides easy access to MinIO web console for RamenDR

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🌐 MinIO Web Console Access${NC}"
echo "================================="

# Check if MinIO is running
echo -e "${BLUE}🔍 Checking MinIO status...${NC}"
if ! kubectl get pod -n minio-system -l app=minio | grep -q Running; then
    echo -e "${YELLOW}⚠️  MinIO is not running. Please deploy it first:${NC}"
    echo "   kubectl apply -f minio-deployment/minio-s3.yaml"
    exit 1
fi

echo -e "${GREEN}✅ MinIO is running${NC}"

# Stop any existing port-forwards
echo -e "${BLUE}🧹 Cleaning up existing port-forwards...${NC}"
pkill -f "kubectl.*port-forward.*minio" 2>/dev/null || true
sleep 2

# Start port-forward
echo -e "${BLUE}🚀 Starting web console port-forward...${NC}"
echo "   This will run in the background"

# Start port-forward in background
nohup kubectl port-forward -n minio-system service/minio 9001:9001 >/tmp/minio-console.log 2>&1 &
PF_PID=$!

# Wait a moment for connection to establish
sleep 5

# Test connection
echo -e "${BLUE}🔍 Testing connection...${NC}"
if curl -s http://localhost:9001 >/dev/null; then
    echo -e "${GREEN}✅ MinIO web console is accessible!${NC}"
else
    echo -e "${YELLOW}⚠️  Connection not ready yet. Wait a few more seconds.${NC}"
fi

echo ""
echo -e "${GREEN}🌐 MinIO Web Console Access:${NC}"
echo "   URL:      http://localhost:9001"
echo "   Username: minioadmin"
echo "   Password: minioadmin"
echo ""
echo -e "${BLUE}💡 What you can do:${NC}"
echo "   1. Browse the 'ramen-metadata' bucket"
echo "   2. See RamenDR backup metadata"
echo "   3. Monitor storage usage"
echo ""
echo -e "${BLUE}🛑 To stop port-forward:${NC}"
echo "   pkill -f 'kubectl.*port-forward.*minio'"
echo ""
echo -e "${GREEN}✨ MinIO console is ready! Open http://localhost:9001 in your browser${NC}"
