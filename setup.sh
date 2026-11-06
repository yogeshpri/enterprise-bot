#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="demo"
IMAGE_NAME="enterprise-bot:1.0"
NAMESPACE="demo"

echo "===== Enterprise Bot Setup ====="

# 1. Create or reuse kind cluster
if kind get clusters | grep -qx "$CLUSTER_NAME"; then
    echo "Kind cluster already exists. Reusing it."
else
    cat > /tmp/kind-config.yaml <<'CONFIG'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    labels:
      ingress-ready: "true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
CONFIG

    kind create cluster --name "$CLUSTER_NAME" --config /tmp/kind-config.yaml
    rm -f /tmp/kind-config.yaml
fi

kind export kubeconfig --name "$CLUSTER_NAME"

kubectl wait --for=condition=Ready node --all --timeout=180s

# 2. Install ingress-nginx
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl rollout status deployment/ingress-nginx-controller \
    -n ingress-nginx --timeout=180s

# 3. Build and load Docker image
docker build -t "$IMAGE_NAME" "$PROJECT_DIR/service"

kind load docker-image "$IMAGE_NAME" --name "$CLUSTER_NAME"

# 4. Create namespace
kubectl create namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

# 5. Install or upgrade Helm release
helm upgrade --install demo "$PROJECT_DIR/chart" \
    --namespace "$NAMESPACE" \
    --wait \
    --timeout 180s

echo "===== Setup Completed Successfully ====="

kubectl get pods -n "$NAMESPACE"
kubectl get services,ingress -n "$NAMESPACE"
