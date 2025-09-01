#!/bin/bash

# Fix common YAML linting issues

echo "🔧 Fixing YAML lint issues..."

# Fix document start markers for files that need them
echo "3. Adding missing document start markers..."
for file in \
  examples/s3-config/s3-secret.yaml \
  examples/s3-config/ramenconfig.yaml \
  examples/minio-deployment/minio-s3.yaml \
  examples/test-application/nginx-with-pvc.yaml \
  examples/test-application/nginx-drpc.yaml \
  examples/test-application/simple-placement.yaml \
  examples/test-application/manual-vrg.yaml \
  examples/test-application/nginx-vrg-correct.yaml; do
  
  if [ -f "$file" ]; then
    # Check if file doesn't start with ---
    if ! head -n 1 "$file" | grep -q "^---"; then
      # Add --- at the beginning
      sed -i '1i---' "$file"
      echo "  Added document start to $file"
    fi
  fi
done

# Fix line length issues in specific files
echo "4. Fixing long lines..."
sed -i 's|# This provides S3-compatible storage for RamenDR to store metadata about protected applications|# S3-compatible storage for RamenDR metadata|' examples/minio-deployment/minio-s3.yaml

# Fix specific indentation issues in nginx-with-pvc.yaml
echo "5. Fixing indentation issues..."
sed -i 's/^      containers:/        containers:/' examples/test-application/nginx-with-pvc.yaml
sed -i 's/^        - name: nginx/          - name: nginx/' examples/test-application/nginx-with-pvc.yaml
sed -i 's/^          image: nginx/            image: nginx/' examples/test-application/nginx-with-pvc.yaml
sed -i 's/^          ports:/            ports:/' examples/test-application/nginx-with-pvc.yaml
sed -i 's/^          volumeMounts:/            volumeMounts:/' examples/test-application/nginx-with-pvc.yaml
sed -i 's/^      volumes:/        volumes:/' examples/test-application/nginx-with-pvc.yaml

# Fix indentation in minio-s3.yaml
sed -i 's/^      containers:/        containers:/' examples/minio-deployment/minio-s3.yaml
sed -i 's/^        - name: minio/          - name: minio/' examples/minio-deployment/minio-s3.yaml
sed -i 's/^          image:/            image:/' examples/minio-deployment/minio-s3.yaml
sed -i 's/^          args:/            args:/' examples/minio-deployment/minio-s3.yaml
sed -i 's/^          env:/            env:/' examples/minio-deployment/minio-s3.yaml
sed -i 's/^          ports:/            ports:/' examples/minio-deployment/minio-s3.yaml
sed -i 's/^          volumeMounts:/            volumeMounts:/' examples/minio-deployment/minio-s3.yaml
sed -i 's/^      volumes:/        volumes:/' examples/minio-deployment/minio-s3.yaml

echo "✅ Basic YAML fixes applied!"
