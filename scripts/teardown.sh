#!/bin/bash
# Tear down the JupyterHub deployment.
# Leaves intact: k3s, MIG partitioning, NVIDIA runtime config, device plugin,
# the pytorch-codeserver image, and PVC-backed user data.
# Use `teardown.sh --purge` to also delete user PVCs.

set -e

PURGE_DATA=false
if [ "$1" = "--purge" ]; then
  PURGE_DATA=true
fi

echo "==> Uninstalling Helm release"
if helm status jhub -n jhub >/dev/null 2>&1; then
  helm uninstall jhub -n jhub
else
  echo "    (no Helm release 'jhub' found, skipping)"
fi

if [ "$PURGE_DATA" = true ]; then
  echo "==> Deleting user PVCs (--purge specified)"
  kubectl delete pvc --all -n jhub --ignore-not-found
else
  echo "==> Keeping user PVCs (re-deploy will reattach them)"
  echo "    Run with --purge to delete user data"
fi

echo "==> Deleting jhub-passwords secret"
kubectl delete secret jhub-passwords -n jhub --ignore-not-found

echo "==> Deleting namespace"
kubectl delete namespace jhub --ignore-not-found --wait=false

# Wait up to 30s for clean termination, then force-clear finalizers
echo "==> Waiting for namespace to terminate"
for i in $(seq 1 30); do
  if ! kubectl get namespace jhub >/dev/null 2>&1; then
    echo "    namespace gone"
    break
  fi
  sleep 1
done

if kubectl get namespace jhub >/dev/null 2>&1; then
  echo "==> Namespace stuck on Terminating — clearing finalizers"
  kubectl get namespace jhub -o json \
    | jq '.spec.finalizers = []' \
    | kubectl replace --raw "/api/v1/namespaces/jhub/finalize" -f - >/dev/null
fi

echo
echo "Teardown complete."
echo "  Image preserved:    docker.io/library/pytorch-codeserver:latest"
echo "  Cluster preserved:  k3s, MIG, NVIDIA runtime, device plugin"
if [ "$PURGE_DATA" = false ]; then
  echo "  User data preserved (PVCs in PV pool)"
fi
echo
echo "Run ./deploy.sh to bring it back up."