#!/bin/bash
set -e

USE_GPU=0
for arg in "$@"; do
  case "$arg" in
    --gpu) USE_GPU=1 ;;
    -h|--help)
      echo "Usage: $0 [--gpu]"
      echo "  --gpu   deploy the GPU config (default: CPU)"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

if [ "$USE_GPU" -eq 1 ]; then
  CONFIG_FILE="configs/config-vscode-gpu.yaml"
else
  CONFIG_FILE="configs/config-vscode-cpu.yaml"
fi

SECRET_FILE="hub/passwords.env"
REPO_FILE="hub/repo.env"

if [ ! -f "$SECRET_FILE" ]; then
  echo "Error: $SECRET_FILE not found."
  echo "Copy hub/passwords.env.example to $SECRET_FILE and fill in real values."
  exit 1
fi

if [ ! -f "$REPO_FILE" ]; then
  echo "Error: $REPO_FILE not found."
  echo "Copy hub/repo.env.example to $REPO_FILE and set GIT_ORG / GIT_REPO."
  exit 1
fi

# shellcheck disable=SC1090
. "$REPO_FILE"

if [ -z "${GIT_ORG:-}" ] || [ -z "${GIT_REPO:-}" ]; then
  echo "Error: GIT_ORG and GIT_REPO must both be set in $REPO_FILE." >&2
  exit 1
fi

echo "Deploying with config: $CONFIG_FILE"
echo "Repo: https://github.com/$GIT_ORG/$GIT_REPO"

kubectl create namespace jhub --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic jhub-passwords -n jhub \
  --from-env-file="$SECRET_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install jhub jupyterhub/jupyterhub \
  --namespace jhub --create-namespace \
  --values "$CONFIG_FILE" \
  --set "singleuser.extraEnv.GIT_ORG=$GIT_ORG" \
  --set "singleuser.extraEnv.GIT_REPO=$GIT_REPO" \
  --set "hub.extraEnv.GIT_REPO=$GIT_REPO" \
  --set-file hub.extraConfig.01-admin-password\\.py=hub/admin.py \
  --set-file hub.extraConfig.02-code-spawner\\.py=hub/code_spawner.py

kubectl rollout status -n jhub deployment/hub
