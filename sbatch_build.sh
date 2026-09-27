#!/usr/bin/env bash
#SBATCH --job-name=build
#SBATCH --partition=gpu-h200
#SBATCH --account=uwit
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=log/build_%j.log
#SBATCH --error=log/build_%j.log
#
# Build isaac-sim.sif from Apptainer definition.
# Pure CPU build without requiring GPU bindings or shader compilation.
#
#   mkdir -p log && sbatch sbatch_build.sh
#

set -euo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}"
[ -f isaac-sim.def ] || { echo "Run from the isaac-hpc directory (isaac-sim.def not found)" >&2; exit 1; }

DEF_FILE="${DEF_FILE:-isaac-sim.def}"
TARGET_SIF="${TARGET_SIF:-isaac-sim.sif}"

SCRATCH="/tmp/${USER}/${SLURM_JOB_ID:-build_$$}"
trap 'rm -rf "${SCRATCH}"' EXIT INT TERM
mkdir -p "${SCRATCH}/apptainer-tmp"
export APPTAINER_TMPDIR="${SCRATCH}/apptainer-tmp"

echo "=========================================================="
echo "Isaac Sim container build ${SLURM_JOB_ID:-local} on $(hostname) at $(date)"
echo "Def: ${DEF_FILE} -> ${TARGET_SIF}"
df -h /tmp | tail -1
echo "=========================================================="

echo "---------- Building ${TARGET_SIF} ----------"
t0=$SECONDS
apptainer build --notest --force "${TARGET_SIF}" "${DEF_FILE}"
BUILD=$((SECONDS - t0))

echo "=========================================================="
echo "Build completed in ${BUILD}s"
ls -lh "${TARGET_SIF}"
echo "Finished at $(date)"
echo "=========================================================="
