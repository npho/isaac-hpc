# Isaac HPC

Apptainer (Singularity) container build and runtime environment for NVIDIA [Isaac Sim](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/isaac-sim) and [Isaac Lab](https://isaac-sim.github.io/IsaacLab/) on HPC clusters.

Rather than relying on large monolithic NGC images, this repository builds a native Apptainer image on top of a CUDA base image, using [`uv`](https://docs.astral.sh/uv/) and PyPI/NVIDIA package indexes to manage dependencies cleanly and reproducibly.

## Key Stack

- **Base Image:** `nvidia/cuda:12.8.2-runtime-ubuntu24.04`
- **Python:** 3.12 (managed via `uv`)
- **Core Packages:**
  - `isaacsim==6.1.0.0`
  - `isaaclab>=3.0.0rc1`
  - `torch==2.11.0` (CUDA 12.8 wheel index)
  - `rsl-rl-lib`

## Repository Structure

- `isaac-sim.def`: Apptainer definition file configuring system packages, `uv`, and runtime environment.
- `nvidia_icd.json`: NVIDIA Vulkan ICD configuration for headless and off-screen GPU rendering.
- `pyproject.toml`: Python dependency specifications and wheel indexes.
- `uv.lock`: Frozen lockfile used by `uv sync` for reproducible container builds.
- `sim.py`: Minimal headless simulation verification script.

## Building the Container

### 1. Pull the CUDA Base Image
```bash
apptainer pull cuda_12.8.2-runtime-ubuntu24.04.sif docker://nvidia/cuda:12.8.2-runtime-ubuntu24.04
```

### 2. Build the SIF Container
The definition file copies `pyproject.toml` and `uv.lock` into the container and executes `uv sync --frozen`:

```bash
apptainer build isaac-sim.sif isaac-sim.def
```

> **Note:** If you modify dependencies in `pyproject.toml`, update `uv.lock` with `uv lock` before building.

## Verification & Testing

Run the container's built-in `%test` suite (verifies Python 3.12, PyTorch CUDA support, and core imports for `rsl_rl`, `isaacsim`, and `isaaclab`):

```bash
apptainer test --nv isaac-sim.sif
```

## Usage

Always pass `--nv` to enable NVIDIA GPU access inside the container.

### Run Python Scripts
The container runscript defaults to `python` within the virtual environment:

```bash
apptainer run --nv isaac-sim.sif sim.py
```

### Execute Commands
```bash
apptainer exec --nv isaac-sim.sif python -c "import isaaclab; print('Isaac Lab ready')"
```

### Interactive Shell
```bash
apptainer shell --nv isaac-sim.sif
```
