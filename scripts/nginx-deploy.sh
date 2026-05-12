#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NGINX_DIR="${REPO_ROOT}/nginx"

if [ ! -f "${NGINX_DIR}/.env" ]; then
    echo "ERROR: ${NGINX_DIR}/.env not found"
    echo "Create it: cp ${NGINX_DIR}/.env.example ${NGINX_DIR}/.env"
    exit 1
fi

export $(cat "${NGINX_DIR}/.env" | grep -v '^#' | grep -v '^$' | xargs)

for var in DOMAIN SSL_CERT_PATH SSL_KEY_PATH; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: $var not set in .env"
        exit 1
    fi
done

echo "[1/4] Checking cert exists..."
if [ ! -f "${SSL_CERT_PATH}" ]; then
    echo "ERROR: cert not found at ${SSL_CERT_PATH}"
    echo "Run: sudo certbot certonly --nginx -d ${DOMAIN}"
    exit 1
fi

echo "[2/4] Generating nginx config..."
envsubst '${DOMAIN} ${SSL_CERT_PATH} ${SSL_KEY_PATH}' \
    < "${NGINX_DIR}/nginx.conf.template" \
    > "${NGINX_DIR}/${DOMAIN}"

echo "[3/4] Installing config..."
sudo cp "${NGINX_DIR}/${DOMAIN}" /etc/nginx/sites-available/
if [ ! -L "/etc/nginx/sites-enabled/${DOMAIN}" ]; then
    sudo ln -s "/etc/nginx/sites-available/${DOMAIN}" /etc/nginx/sites-enabled/
fi

echo "[4/4] Testing and reloading nginx..."
sudo nginx -t
sudo systemctl reload nginx

echo ""
echo "Done. Test with:"
echo "  curl -I https://${DOMAIN}"
