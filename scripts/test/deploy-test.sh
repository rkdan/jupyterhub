#!/bin/bash
# Spin up N test user sessions against the running JupyterHub.
# Logs in as testuser1..N with the shared user password and starts each server.
#
# Usage:
#   ./deploy-test.sh [--count N] [--url URL] [--prefix NAME] [--teardown]
#
#   --count N      number of users to spawn (default: 7)
#   --url URL      hub base URL (default: http://localhost:30080)
#   --prefix NAME  username prefix (default: testuser)
#   --teardown     delete the test users' servers and stop here
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PASSWORDS_FILE="${REPO_ROOT}/hub/passwords.env"

COUNT=7
HUB_URL="http://localhost:30080"
PREFIX="testuser"
TEARDOWN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --count)    COUNT="$2"; shift 2 ;;
    --url)      HUB_URL="${2%/}"; shift 2 ;;
    --prefix)   PREFIX="$2"; shift 2 ;;
    --teardown) TEARDOWN=true; shift ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 1 ]; then
  echo "Error: --count must be a positive integer" >&2
  exit 1
fi

if [ "$TEARDOWN" = true ]; then
  echo "==> Deleting servers for ${PREFIX}1..${PREFIX}${COUNT}"
  for i in $(seq 1 "$COUNT"); do
    kubectl delete pod -n jhub "jupyter-${PREFIX}${i}" --ignore-not-found --wait=false
  done
  echo "Done. (PVCs left in place — use 'kubectl delete pvc -n jhub claim-${PREFIX}<i>' to remove)"
  exit 0
fi

if [ ! -f "$PASSWORDS_FILE" ]; then
  echo "Error: $PASSWORDS_FILE not found." >&2
  exit 1
fi

USER_PW=$(grep '^user-password=' "$PASSWORDS_FILE" | cut -d= -f2-)
if [ -z "$USER_PW" ]; then
  echo "Error: user-password not set in $PASSWORDS_FILE" >&2
  exit 1
fi

echo "==> Spawning $COUNT users at $HUB_URL"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pids=()
for i in $(seq 1 "$COUNT"); do
  (
    USER="${PREFIX}${i}"
    COOKIES="${TMPDIR}/${USER}.jar"

    xsrf() { awk '$6 == "_xsrf" { print $7 }' "$COOKIES" | tail -n1; }

    # Hit /hub/login to get the _xsrf cookie, echo it back in the form.
    curl -sk -c "$COOKIES" -b "$COOKIES" "${HUB_URL}/hub/login" -o /dev/null
    XSRF=$(xsrf)
    HTTP=$(curl -sk -c "$COOKIES" -b "$COOKIES" -o /dev/null -w '%{http_code}' \
      --data-urlencode "_xsrf=${XSRF}" \
      --data-urlencode "username=${USER}" \
      --data-urlencode "password=${USER_PW}" \
      "${HUB_URL}/hub/login?next=")
    if [ "$HTTP" != "302" ] && [ "$HTTP" != "200" ]; then
      echo "  [${USER}] login failed (HTTP ${HTTP})" >&2
      exit 1
    fi

    # Cookie rotates again on first authenticated page hit, and the API
    # checks against that user-bound _xsrf value. Touch /hub/home to refresh.
    curl -sk -c "$COOKIES" -b "$COOKIES" -o /dev/null "${HUB_URL}/hub/home"
    XSRF=$(xsrf)
    SPAWN=$(curl -sk -c "$COOKIES" -b "$COOKIES" -o /dev/null -w '%{http_code}' \
      -H "X-XSRFToken: ${XSRF}" \
      -X POST "${HUB_URL}/hub/api/users/${USER}/server")
    case "$SPAWN" in
      201|202) echo "  [${USER}] spawn requested (HTTP ${SPAWN})" ;;
      400)     echo "  [${USER}] already running (HTTP 400)" ;;
      *)       echo "  [${USER}] spawn failed (HTTP ${SPAWN})" >&2; exit 1 ;;
    esac
  ) &
  pids+=($!)
done

fail=0
for pid in "${pids[@]}"; do
  wait "$pid" || fail=$((fail + 1))
done

echo
echo "==> Pods in jhub namespace:"
kubectl get pods -n jhub -l component=singleuser-server

echo
if [ "$fail" -gt 0 ]; then
  echo "Done with $fail failure(s). Run 'kubectl get pods -n jhub -w' to watch."
  exit 1
fi
echo "Done. Run 'kubectl get pods -n jhub -w' to watch them come up."
echo "Teardown: $0 --count $COUNT --prefix $PREFIX --teardown"
