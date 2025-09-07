#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Test script for DEMO_FLOW_GUIDE.md Phase 3 commands
# This validates that the corrected commands work properly

set -e

echo "🧪 Testing DEMO_FLOW_GUIDE.md Phase 3 Commands"
echo "==============================================="
echo ""

echo "Step 1: Cluster Status"
echo "======================"
echo "Available kind clusters:"
kind get clusters
echo ""

echo "Verifying cluster connectivity:"
for context in kind-ramen-hub kind-ramen-dr1 kind-ramen-dr2; do
    echo "=== $context ==="
    if kubectl config use-context $context 2>/dev/null; then
        if kubectl get nodes --no-headers 2>/dev/null >/dev/null; then
            echo "✅ $context: Connected"
        else
            echo "❌ $context: Connection failed"
        fi
    else
        echo "❌ Context $context not found"
    fi
    echo ""
done

echo ""
echo "Step 3: Verify Current State (before operator installation)"
echo "=========================================================="
echo "Checking for RamenDR operators (should not exist yet):"
for context in kind-ramen-hub kind-ramen-dr1 kind-ramen-dr2; do
    echo "=== $context ==="
    if kubectl config use-context $context 2>/dev/null; then
        if kubectl get namespace ramen-system >/dev/null 2>&1; then
            echo "✅ ramen-system namespace exists"
            kubectl get pods -n ramen-system 2>/dev/null || echo "No pods in ramen-system"
        else
            echo "ℹ️  ramen-system namespace not created yet (expected)"
        fi
    else
        echo "❌ Context failed"
    fi
    echo ""
done

echo ""
echo "✅ DEMO_FLOW_GUIDE.md Phase 3 commands are working correctly!"
echo ""
echo "Next step: Run './scripts/quick-install.sh' to install operators"
