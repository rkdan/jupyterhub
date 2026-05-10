#!/usr/bin/env bash
#
# enable-mig.sh — Enable NVIDIA MIG on one or more GPUs and create instances.
#
# Usage:
#   sudo ./enable-mig.sh <GPU_INDEX> [GPU_INDEX ...]
#
# Examples:
#   sudo ./enable-mig.sh 0
#   sudo ./enable-mig.sh 0 1 2 3
#
# For each GPU, the script will:
#   1. Enable MIG mode
#   2. Show the available GPU instance profiles
#   3. Prompt you to enter the profile spec to apply (e.g. 19,19,19,19,19,19,19)
#   4. Create the GPU instances and compute instances
#
# Run `sudo nvidia-smi mig -i <GPU> -lgip` to see valid profile IDs for your hardware.

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
configure_gpu() {
    local GPU="$1"

    echo
    echo "============================================================"
    echo " GPU ${GPU}"
    echo "============================================================"

    # 1. Show current MIG state
    echo "==> Current MIG state:"
    nvidia-smi -i "${GPU}" --query-gpu=mig.mode.current,mig.mode.pending --format=csv

    # 2. Enable MIG (idempotent — no-op if already enabled)
    echo "==> Enabling MIG on GPU ${GPU}..."
    nvidia-smi -i "${GPU}" -mig 1

    # 3. Verify
    local CURRENT
    CURRENT=$(nvidia-smi -i "${GPU}" --query-gpu=mig.mode.current --format=csv,noheader | tr -d ' ')
    if [[ "${CURRENT}" != "Enabled" ]]; then
        echo "Error: MIG mode on GPU ${GPU} is '${CURRENT}', expected 'Enabled'." >&2
        echo "  A reboot or driver reset may be required on this hardware." >&2
        return 1
    fi
    echo "==> MIG enabled on GPU ${GPU}."

    # 4. Clear any pre-existing instances (so the script is re-runnable)
    echo "==> Clearing any existing compute/GPU instances on GPU ${GPU}..."
    nvidia-smi mig -i "${GPU}" -dci >/dev/null 2>&1 || true
    nvidia-smi mig -i "${GPU}" -dgi >/dev/null 2>&1 || true

    # 5. Show available profiles
    echo "==> Available GPU instance profiles on GPU ${GPU}:"
    nvidia-smi mig -i "${GPU}" -lgip

    # 6. Prompt for profile spec
    local PROFILE_SPEC=""
    while [[ -z "${PROFILE_SPEC}" ]]; do
        echo
        read -r -p "Enter profile spec for GPU ${GPU} (comma-separated IDs, e.g. 19,19,19,19,19,19,19): " PROFILE_SPEC
        if ! [[ "${PROFILE_SPEC}" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
            echo "  Invalid format. Use comma-separated integers, e.g. 19,19,19 or 9,14"
            PROFILE_SPEC=""
        fi
    done

    # 7. Create GPU instances
    echo "==> Creating GPU instances on GPU ${GPU} with spec: ${PROFILE_SPEC}"
    nvidia-smi mig -i "${GPU}" -cgi "${PROFILE_SPEC}"

    # 8. Create compute instances (one per GPU instance, default profile)
    echo "==> Creating compute instances on GPU ${GPU}..."
    nvidia-smi mig -i "${GPU}" -cci
}

for GPU in "${GPUS[@]}"; do
    configure_gpu "${GPU}"
done

# ---- Final summary ------------------------------------------------------
echo
echo "============================================================"
echo " Final MIG layout"
echo "============================================================"
nvidia-smi -L

echo
echo "Done. Profit."