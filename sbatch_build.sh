#!/usr/bin/env bash
#SBATCH --job-name=build
#SBATCH --partition=gpu-h200
#SBATCH --account=uwit
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gpus=1
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --exclude=g011,g014,g018,g019
#SBATCH --output=log/build_%j.log
#SBATCH --error=log/build_%j.log
#
# Build isaac-sim.sif on a GPU node so %post can bake the Kit/RTX shader cache.
#
#   mkdir -p log && sbatch sbatch_build.sh
#
# Steps:
#   1. Preflight: run warmup_shaders.py against BASELINE_SIF with an empty cache
#      (catches script errors before the long build; gives the cold-start time).
#   2. apptainer build --nv (GPU visible in %post -> shader warm-up runs).
#   3. apptainer test --nv, and report the baked cache contents.
#   4. Run warmup_shaders.py against TARGET_SIF with the cache seeded from the image
#      (warm-start time, to compare with step 1).
#
# Env overrides: TARGET_SIF (default isaac-sim.new.sif), BASELINE_SIF (default
# isaac-sim.sif), SKIP_PREFLIGHT=1.

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}"
[ -f isaac-sim.def ] || { echo "Run from the isaac-hpc directory (isaac-sim.def not found)" >&2; exit 1; }

DEF_FILE="${DEF_FILE:-isaac-sim.def}"
TARGET_SIF="${TARGET_SIF:-isaac-sim.new.sif}"
BASELINE_SIF="${BASELINE_SIF:-isaac-sim.sif}"
KIT_DIR=/workspace/.venv/lib/python3.12/site-packages/isaacsim/kit

SCRATCH="/tmp/${USER}/${SLURM_JOB_ID:-build_$$}"
trap 'rm -rf "${SCRATCH}"' EXIT INT TERM
mkdir -p "${SCRATCH}/apptainer-tmp"
export APPTAINER_TMPDIR="${SCRATCH}/apptainer-tmp"

echo "=========================================================="
echo "Isaac Sim container build ${SLURM_JOB_ID:-local} on $(hostname) at $(date)"
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
echo "Def: ${DEF_FILE} -> ${TARGET_SIF}   Baseline: ${BASELINE_SIF}"
df -h /tmp | tail -1
echo "=========================================================="

# No host library staging: the image carries its own userland libs and --nv injects
# the driver. If the preflight fails on a missing driver lib, that is the signal.

# run_warmup <sif> <label> [seed]: run warmup_shaders.py with a fresh writable Kit cache,
# optionally seeded from the image's /workspace/baked_kit_cache (as the origami runners do).
run_warmup() {
    local sif="$1" label="$2" seed="${3:-}"
    local run="${SCRATCH}/run_${label}"
    mkdir -p "${run}/kit/cache" "${run}/kit/data" "${run}/kit/logs" \
             "${run}/tmp/nvidia/omniverse" "${run}/tmp/nvidia/cache" "${run}/tmp/nvidia/logs"
    if [ -n "${seed}" ]; then
        apptainer exec -B "${run}/kit:/seed" "${sif}" \
            sh -c 'cp -r /workspace/baked_kit_cache/cache/. /seed/cache/ && cp -r /workspace/baked_kit_cache/data/. /seed/data/'
    fi
    local t0=$SECONDS rc=0
    apptainer exec --nv \
        -B "${run}/tmp:/tmp" \
        -B "${PWD}:/build" \
        -B "${run}/kit/cache:${KIT_DIR}/cache" \
        -B "${run}/kit/data:${KIT_DIR}/data" \
        -B "${run}/kit/logs:${KIT_DIR}/logs" \
        "${sif}" \
        env HOME=/tmp XDG_RUNTIME_DIR=/tmp \
            OMNI_USER_DATA_DIR=/tmp/nvidia/omniverse OMNI_CACHE_DIR=/tmp/nvidia/cache OMNI_LOG_DIR=/tmp/nvidia/logs \
            python -u /build/warmup_shaders.py || rc=$?
    WARMUP_SECONDS=$((SECONDS - t0))
    echo "[${label}] exit=${rc} wall=${WARMUP_SECONDS}s cache=$(du -sh "${run}/kit/cache" | cut -f1)"
    return ${rc}
}

# 1. Preflight (cold)
COLD=n/a
if [ "${SKIP_PREFLIGHT:-0}" != 1 ] && [ -f "${BASELINE_SIF}" ]; then
    echo "---------- [1/4] Preflight: cold warm-up on ${BASELINE_SIF} ----------"
    # Non-fatal: the baseline image predates the userland lib additions in the def.
    if run_warmup "${BASELINE_SIF}" cold; then COLD=${WARMUP_SECONDS}; else COLD="failed(${WARMUP_SECONDS}s)"; fi
fi

# 2. Build
echo "---------- [2/4] Build ${TARGET_SIF} ----------"
t0=$SECONDS
apptainer build --nv --notest --force "${TARGET_SIF}" "${DEF_FILE}"
BUILD=$((SECONDS - t0))
ls -lh "${TARGET_SIF}"

# 3. Test + inspect baked cache
echo "---------- [3/4] Test and inspect ${TARGET_SIF} ----------"
apptainer test --nv "${TARGET_SIF}"
apptainer exec "${TARGET_SIF}" sh -c '
    B=/workspace/baked_kit_cache
    echo "Baked for: $(cat $B/DRIVER 2>/dev/null || echo MISSING)"
    du -sh $B $B/cache $B/data 2>/dev/null
    echo "RTX shadercache files: $(find $B -path "*shadercache*" -type f | wc -l)"
    [ -d $B/cache ] || { echo "ERROR: image has no baked shader cache" >&2; exit 1; }'

# 4. Warm run
echo "---------- [4/4] Seeded warm-up on ${TARGET_SIF} ----------"
run_warmup "${TARGET_SIF}" warm seed
WARM=${WARMUP_SECONDS}

echo "=========================================================="
echo "Build: ${BUILD}s   Kit start-to-render cold: ${COLD}s   warm (seeded): ${WARM}s"
echo "Output: ${PWD}/${TARGET_SIF}"
echo "Finished at $(date)"
echo "=========================================================="
