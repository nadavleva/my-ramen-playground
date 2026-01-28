#!/bin/bash
# Resume setup script from specific step

# Usage: ./resume-setup.sh [step_number]
# Example: ./resume-setup.sh 6

STEP=${1:-6}

echo "Resuming DR cluster setup from step $STEP..."
echo ""

START_STEP=$STEP ./setup-dr-clusters-with-ceph.sh