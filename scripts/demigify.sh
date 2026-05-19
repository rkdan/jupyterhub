#!/usr/bin/env bash
#
# demigify.sh — Tear down NVIDIA MIG instances and disable MIG on one or more GPUs.
#
# Usage:
#   sudo ./demigify.sh <GPU_INDEX> [GPU_INDEX ...]
#
# Examples:
#   sudo ./demigify.sh 0
#   sudo ./demigify.sh 0 1 2 3
#
# For each GPU, the script will:
#   1. Destroy all compute instances
#   2. Destroy all GPU instances
#   3. Disable MIG mode
#
# A reboot or driver reset may be required on some hardware before MIG mode
# fully transitions to Disabled.

set -euo pipefail

# ---- Args ---------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <GPU_INDEX> [GPU_INDEX ...]" >&2
    echo "  e.g.  $0 0 1 2 3" >&2
    exit 1
fi

GPUS=("$@")

# ---- Sanity checks ------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "Error: must be run as root (or via sudo)." >&2
    exit 1
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "Error: nvidia-smi not found in PATH." >&2
    exit 1
fi

# Validate each GPU index exists
TOTAL_GPUS=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -n1 | tr -d ' ')
for GPU in "${GPUS[@]}"; do
    if ! [[ "${GPU}" =~ ^[0-9]+$ ]]; then
        echo "Error: '${GPU}' is not a valid GPU index." >&2
        exit 1
    fi
    if (( GPU >= TOTAL_GPUS )); then
        echo "Error: GPU index ${GPU} out of range (system has ${TOTAL_GPUS} GPUs)." >&2
        exit 1
    fi
done

# ---- Per-GPU loop -------------------------------------------------------
teardown_gpu() {
    local GPU="$1"

    echo
    echo "============================================================"
    echo " GPU ${GPU}"
    echo "============================================================"

    # 1. Show current MIG state
    echo "==> Current MIG state:"
    nvidia-smi -i "${GPU}" --query-gpu=mig.mode.current,mig.mode.pending --format=csv

    local CURRENT
    CURRENT=$(nvidia-smi -i "${GPU}" --query-gpu=mig.mode.current --format=csv,noheader | tr -d ' ')

    if [[ "${CURRENT}" == "Enabled" ]]; then
        # 2. Destroy compute instances (must go before GPU instances)
        echo "==> Destroying compute instances on GPU ${GPU}..."
        nvidia-smi mig -i "${GPU}" -dci >/dev/null 2>&1 || true

        # 3. Destroy GPU instances
        echo "==> Destroying GPU instances on GPU ${GPU}..."
        nvidia-smi mig -i "${GPU}" -dgi >/dev/null 2>&1 || true
    else
        echo "==> MIG is not enabled on GPU ${GPU}; skipping instance teardown."
    fi

    # 4. Disable MIG (idempotent — no-op if already disabled)
    echo "==> Disabling MIG on GPU ${GPU}..."
    nvidia-smi -i "${GPU}" -mig 0

    # 5. Verify
    CURRENT=$(nvidia-smi -i "${GPU}" --query-gpu=mig.mode.current --format=csv,noheader | tr -d ' ')
    if [[ "${CURRENT}" != "Disabled" ]]; then
        echo "Warning: MIG mode on GPU ${GPU} is '${CURRENT}', expected 'Disabled'." >&2
        echo "  A reboot or driver reset may be required on this hardware." >&2
        return 1
    fi
    echo "==> MIG disabled on GPU ${GPU}."
}

for GPU in "${GPUS[@]}"; do
    teardown_gpu "${GPU}" || true
done

# ---- Final summary ------------------------------------------------------
echo
echo "============================================================"
echo " Final GPU layout"
echo "============================================================"
nvidia-smi -L

echo
echo "Done. Demigified."
