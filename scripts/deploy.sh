#!/bin/bash
set -e

SECRET_FILE="hub-config/passwords.env"

if [ ! -f "$SECRET_FILE" ]; then
  echo "Error: $SECRET_FILE not found."
  echo "Copy hub-config/passwords.env.example to $SECRET_FILE and fill in real values."
  exit 1
fi

kubectl create namespace jhub --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic jhub-passwords -n jhub \
  --from-env-file="$SECRET_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install jhub jupyterhub/jupyterhub \
  --namespace jhub --create-namespace \
  --values config-vscode.yaml \
  --set-file hub.extraConfig.01-admin-password\\.py=hub-config/admin.py \
  --set-file hub.extraConfig.02-code-spawner\\.py=hub-config/code_spawner.py

kubectl rollout status -n jhub deployment/hub