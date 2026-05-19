#!/bin/bash
# Run a CPU + I/O stress test inside running test-user pods.
# In each pod, spawn N CPU busy loops and a continuous dd write/read loop
# against /home/jovyan (the PVC) for DURATION seconds, then clean up.
# Pods must already be running -- use load-test.sh to spawn them first.
#
# Usage:
#   ./stress-test.sh [--count N] [--prefix NAME] [--duration S]
#                    [--threads N] [--size SIZE] [--teardown]
#
#   --count N      number of test users to target (default: 7)
#   --prefix NAME  username prefix (default: testuser)
#   --duration S   stress duration in seconds (default: 600)
#   --threads N    CPU-burn threads per pod (default: 2)
#   --size SIZE    I/O file size per iteration, e.g. 3G or 512M (default: 3G)
#   --teardown     kill any in-flight stress in the pods and exit
set -euo pipefail

COUNT=7
PREFIX="testuser"
DURATION=600
THREADS=2
SIZE="3G"
NAMESPACE="jhub"
TEARDOWN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --count)    COUNT="$2"; shift 2 ;;
    --prefix)   PREFIX="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --threads)  THREADS="$2"; shift 2 ;;
    --size)     SIZE="$2"; shift 2 ;;
    --teardown) TEARDOWN=true; shift ;;
    -h|--help)
      sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

for n in COUNT DURATION THREADS; do
  v=${!n}
  if ! [[ "$v" =~ ^[0-9]+$ ]] || [ "$v" -lt 1 ]; then
    echo "Error: --${n,,} must be a positive integer" >&2
    exit 1
  fi
done

# Parse SIZE (e.g. "3G", "512M") into MB for dd count=
case "$SIZE" in
  *G|*g) SIZE_MB=$(( ${SIZE%[Gg]} * 1024 )) ;;
  *M|*m) SIZE_MB=${SIZE%[Mm]} ;;
  *)
    echo "Error: --size must be like '3G' or '512M'" >&2
    exit 1 ;;
esac

TARGET_FILE="/home/jovyan/.stress-test.dat"

if [ "$TEARDOWN" = true ]; then
  echo "==> Stopping stress and removing $TARGET_FILE in ${COUNT} pods"
  for i in $(seq 1 "$COUNT"); do
    USER="${PREFIX}${i}"
    (
      kubectl exec -n "$NAMESPACE" "jupyter-${USER}" -- bash -c "
        pkill -9 -x yes 2>/dev/null || true
        pkill -9 -x dd  2>/dev/null || true
        rm -f '${TARGET_FILE}'
      " >/dev/null 2>&1 && echo "  [${USER}] cleaned" || echo "  [${USER}] cleanup failed" >&2
    ) &
  done
  wait
  exit 0
fi

echo "==> Stress-testing ${COUNT} pods (${PREFIX}1..${PREFIX}${COUNT}) for ${DURATION}s"
echo "    cpu threads/pod=${THREADS}  io file=${TARGET_FILE} size=${SIZE} (${SIZE_MB} MB)"
START=$(date +%s)

pids=()
for i in $(seq 1 "$COUNT"); do
  (
    USER="${PREFIX}${i}"
    POD="jupyter-${USER}"

    REMOTE=$(cat <<REMOTE
set -u
TARGET='${TARGET_FILE}'
THREADS=${THREADS}
SIZE_MB=${SIZE_MB}
DURATION=${DURATION}

cleanup() {
  pkill -9 -x yes 2>/dev/null || true
  pkill -9 -x dd  2>/dev/null || true
  rm -f "\$TARGET"
}
trap cleanup EXIT HUP TERM INT

for _ in \$(seq 1 \$THREADS); do
  yes >/dev/null &
done

(
  while :; do
    dd if=/dev/zero of="\$TARGET" bs=1M count=\$SIZE_MB status=none 2>/dev/null || break
    dd if="\$TARGET" of=/dev/null bs=1M     status=none 2>/dev/null || break
  done
) &

sleep \$DURATION
REMOTE
)

    echo "  [${USER}] starting"
    if kubectl exec -n "$NAMESPACE" "$POD" -- bash -c "$REMOTE" >/dev/null 2>&1; then
      echo "  [${USER}] done"
    else
      echo "  [${USER}] FAILED" >&2
      exit 1
    fi
  ) &
  pids+=($!)
done

fail=0
for pid in "${pids[@]}"; do
  wait "$pid" || fail=$((fail + 1))
done

ELAPSED=$(( $(date +%s) - START ))
echo
if [ "$fail" -gt 0 ]; then
  echo "Done in ${ELAPSED}s with $fail failure(s)."
  echo "Teardown: $0 --count $COUNT --prefix $PREFIX --teardown"
  exit 1
fi
echo "Done in ${ELAPSED}s. Test file removed in each pod."
