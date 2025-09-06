#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# ultimate-fix-contexts.sh - Ultimate fix for kubectl context issues across terminals

echo "🔧 Ultimate kubectl contexts fix..."
echo "=================================="
echo ""

# Ensure we're in the right directory
echo "📁 Checking working directory..."
if [ ! -f "scripts/setup.sh" ]; then
    echo "❌ Error: Not in RamenDR project directory"
    echo "   Please run from: /home/nlevanon/workspace/RamenDR/ramen"
    echo "   Run: cd /home/nlevanon/workspace/RamenDR/ramen"
    exit 1
fi
echo "✅ Working directory: $(pwd)"
echo ""

# Check kubectl availability and PATH
echo "🔍 Checking kubectl..."
KUBECTL_PATH=""

# Try different kubectl locations
if command -v kubectl >/dev/null 2>&1; then
    KUBECTL_PATH=$(which kubectl)
    echo "✅ kubectl found in PATH: $KUBECTL_PATH"
elif [ -f "/home/nlevanon/aws-gpfs-playground/4.19.1/kubectl" ]; then
    KUBECTL_PATH="/home/nlevanon/aws-gpfs-playground/4.19.1/kubectl"
    echo "✅ kubectl found at: $KUBECTL_PATH"
    echo "⚠️  Note: kubectl not in PATH, using absolute path"
elif [ -f "/usr/local/bin/kubectl" ]; then
    KUBECTL_PATH="/usr/local/bin/kubectl"
    echo "✅ kubectl found at: $KUBECTL_PATH"
else
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi
echo ""

# Check kind
echo "🔍 Checking kind..."
if command -v kind >/dev/null 2>&1; then
    echo "✅ kind found: $(which kind)"
else
    echo "❌ kind not found. Please install kind first."
    exit 1
fi
echo ""

# Export kubeconfig with absolute path
echo "📋 Exporting kubeconfig for all clusters..."
KUBECONFIG_FILE="$HOME/.kube/config"
echo "   Target kubeconfig: $KUBECONFIG_FILE"

# Ensure .kube directory exists
mkdir -p "$HOME/.kube"

# Export for each cluster
for cluster in $(kind get clusters 2>/dev/null); do
    echo "   📤 Exporting: $cluster"
    if kind export kubeconfig --name "$cluster" --kubeconfig "$KUBECONFIG_FILE"; then
        echo "      ✅ Success"
    else
        echo "      ❌ Failed"
    fi
done
echo ""

# Test with absolute kubectl path
echo "🧪 Testing kubectl with absolute path..."
echo "   Using: $KUBECTL_PATH"

# Test basic functionality
if "$KUBECTL_PATH" version --client >/dev/null 2>&1; then
    echo "   ✅ kubectl responds"
else
    echo "   ❌ kubectl not responding"
    exit 1
fi

# Test contexts
echo ""
echo "📊 Checking contexts..."
CONTEXTS=$("$KUBECTL_PATH" config get-contexts -o name 2>/dev/null | grep "kind-" | wc -l)
echo "   Kind contexts found: $CONTEXTS"

if [ "$CONTEXTS" -gt 0 ]; then
    echo "   ✅ Contexts detected!"
    echo ""
    echo "📋 Available contexts:"
    "$KUBECTL_PATH" config get-contexts | grep "kind-" | sed 's/^/      /'
    echo ""
    
    # Test cluster access
    echo "🔗 Testing cluster connectivity..."
    CURRENT_CONTEXT=$("$KUBECTL_PATH" config current-context 2>/dev/null || echo "none")
    echo "   Current context: $CURRENT_CONTEXT"
    
    if "$KUBECTL_PATH" get nodes >/dev/null 2>&1; then
        echo "   ✅ Can access current cluster"
    else
        echo "   ⚠️  Current cluster not accessible, trying context switch..."
        "$KUBECTL_PATH" config use-context kind-ramen-hub >/dev/null 2>&1 || true
    fi
else
    echo "   ❌ No kind contexts found"
    echo ""
    echo "🔧 Troubleshooting:"
    echo "   1. Check if clusters exist: kind get clusters"
    echo "   2. Check kubeconfig file: ls -la ~/.kube/config"
    echo "   3. Try recreating: ./scripts/setup.sh kind"
    exit 1
fi

echo ""
echo "✅ SUCCESS! Your kubectl contexts are now ready."
echo ""
echo "🎯 Test commands (use absolute path if needed):"
if [ "$KUBECTL_PATH" != "kubectl" ]; then
    echo "   $KUBECTL_PATH config get-contexts"
    echo "   $KUBECTL_PATH get nodes"
    echo "   $KUBECTL_PATH config use-context kind-ramen-hub"
    echo ""
    echo "💡 To avoid using absolute path, add to your PATH:"
    echo "   export PATH=\"$(dirname "$KUBECTL_PATH"):\$PATH\""
else
    echo "   kubectl config get-contexts"
    echo "   kubectl get nodes"
    echo "   kubectl config use-context kind-ramen-hub"
fi
echo ""
echo "🚀 Ready for RamenDR installation:"
echo "   ./scripts/quick-install.sh"
echo "   ./scripts/fresh-demo.sh"
echo ""
