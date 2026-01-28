#!/bin/bash

# List all YAML objects used by the setup script
echo "YAML Objects in yaml/objects/ folder:"
echo "===================================="
echo ""

for file in yaml/objects/*.yaml; do
    if [ -f "$file" ]; then
        echo "📄 $(basename "$file")"
        echo "   Purpose: $(head -n 10 "$file" | grep -E '^# |^## ' | head -n 1 | sed 's/^# *//' || echo "Kubernetes $(grep -E '^kind:' "$file" | head -n 1 | cut -d: -f2 | xargs)")"
        echo "   Kind: $(grep -E '^kind:' "$file" | head -n 1 | cut -d: -f2 | xargs)"
        echo "   Used in: $(grep -n "$(basename "$file")" setup-dr-clusters-with-ceph.sh | cut -d: -f1 | paste -sd ',' - | sed 's/^/Lines /')"
        echo ""
    fi
done

echo "Total YAML files: $(ls yaml/objects/*.yaml 2>/dev/null | wc -l)"
echo ""
echo "Usage: These files are referenced by setup-dr-clusters-with-ceph.sh"
echo "       instead of generating temporary files at runtime."