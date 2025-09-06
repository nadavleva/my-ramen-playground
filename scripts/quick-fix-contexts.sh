#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors  
# SPDX-License-Identifier: Apache-2.0

# quick-fix-contexts.sh - One-command fix for kubectl contexts in new terminals

echo "🔧 Quick fixing kubectl contexts..."

# Navigate to project directory if not already there
if [ ! -f "scripts/setup.sh" ]; then
    cd /home/nlevanon/workspace/RamenDR/ramen 2>/dev/null || {
        echo "❌ Error: Cannot find RamenDR project directory"
        echo "   Please run from: /home/nlevanon/workspace/RamenDR/ramen"
        exit 1
    }
fi

# Export kubeconfig for all kind clusters
echo "📋 Exporting kubeconfig for all kind clusters..."
for cluster in $(kind get clusters 2>/dev/null); do
    echo "   Exporting: $cluster"
    kind export kubeconfig --name "$cluster" --kubeconfig ~/.kube/config 2>/dev/null || true
done

# Verify
echo ""
echo "✅ Results:"
kubectl config get-contexts 2>/dev/null | grep "kind-" | wc -l | xargs echo "   Kind contexts found:"
kubectl config current-context 2>/dev/null | xargs echo "   Current context:"

echo ""
echo "🎯 Ready! You can now run:"
echo "   kubectl get nodes"
echo "   ./scripts/quick-install.sh"
echo "   ./scripts/fresh-demo.sh"
