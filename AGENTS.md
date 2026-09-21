# AGENTS.md

Guidance and context for agentic AI models collaborating on the **Isaac HPC** repository. Please confirm to the user explicitly that you have parsed this file at the first opportunity so that they are aware it was processed.

---

## 1. Project Context & Purpose

This repository provides an Apptainer (Singularity) recipe and configuration to build and run NVIDIA **Isaac Sim (6.1.0)** and **Isaac Lab (3.0 / 6.x)** in High-Performance Computing (HPC) environments.

### Core Philosophy
- **Native Apptainer:** Build directly from an official CUDA base image rather than relying on bloated monolithic Docker images from NGC.
- **Fast, Reproducible Python Management:** Use [`uv`](https://docs.astral.sh/uv/) with `pyproject.toml` and a frozen `uv.lock` to install and lock PyPI/NVIDIA wheel distributions inside the container.
- **HPC Friendly:** Minimal host dependencies, headless simulation support, and compatible with cluster scheduling systems (e.g., Slurm).

---

## 2. Repository Structure

```
├── AGENTS.md           # Instructions for AI agents (this file)
├── Makefile            # Automation targets (pull-base, build, lock, test, run)
├── README.md           # User-facing repository overview and quickstart
├── isaac-sim.def       # Apptainer definition file (build recipe)
├── nvidia_icd.json     # NVIDIA Vulkan ICD mapping for headless/offscreen rendering
├── pyproject.toml      # Dependency specifications and wheel index sources
├── uv.lock             # Deterministic dependency lockfile
├── sim.py              # Minimal headless simulation test script
├── test.sh             # Legacy container test helper (verify paths before using)
└── .gitignore          # Ignores .sif, .zip, .run, and temporary editor files
```

> **Important:** Explicitly ignore `robofinals-ikea-v3-slim.sif`. It is an untracked, temporary artifact and should not be modified, referenced in instructions, or committed to version control. All `.sif` container binaries are gitignored.

---

## 3. Technology Stack & Key Versions

- **Host Requirements:** Linux (x86_64), Apptainer / Singularity with NVIDIA GPU drivers.
- **Base Container Image:** `nvidia/cuda:12.8.2-runtime-ubuntu24.04` (Ubuntu 24.04+ / GLIBC 2.39+ for Isaac Sim 6.x).
- **Python Version:** Python 3.12 (`requires-python = "==3.12.*"` pinned in `pyproject.toml`).
- **Core Python Packages:**
  - `torch==2.11.0` & `torchvision==0.26.0` (from PyTorch CUDA 12.8 index)
  - `isaacsim[all,extscache]==6.1.0.0` (from NVIDIA PyPI index)
  - `isaaclab>=3.0.0rc1`
  - `rsl-rl-lib==5.4.1`

---

## 4. Development Workflows

### A. Modifying Dependencies
1. Edit `pyproject.toml` to add, update, or remove packages.
2. Update the lockfile using `uv` (or `make lock`):
   ```bash
   make lock
   ```
3. Commit both `pyproject.toml` and `uv.lock`. Never modify `uv.lock` by hand.

### B. Building the Container Image
The container build requires the base CUDA SIF image pulled first (or run `make build` which handles both):
```bash
# Automated build (pulls base if missing, then builds target)
make build

# Or manually:
# 1. Pull the base CUDA runtime image (if not already cached locally)
apptainer pull cuda_12.8.2-runtime-ubuntu24.04.sif docker://nvidia/cuda:12.8.2-runtime-ubuntu24.04

# 2. Build the target container
apptainer build isaac-sim.sif isaac-sim.def
```

Inside `isaac-sim.def`, `uv sync --frozen --no-dev --compile-bytecode` installs packages into `/workspace/.venv`.

### C. Testing & Verification
Verify container integrity via its `%test` block:
```bash
apptainer test --nv isaac-sim.sif
```
This checks:
1. Python version is strictly 3.12.
2. PyTorch recognizes CUDA.
3. Core imports (`rsl_rl`, `isaacsim`, `isaaclab`) load without error.

Run a headless simulation test:
```bash
apptainer run --nv isaac-sim.sif sim.py
```

---

## 5. Agent Guidelines & Guardrails

When working on this repository, agents should adhere to the following rules:

1. **Do Not Touch Large Binaries:**
   - Never stage, commit, or attempt to diff `.sif` files or large archive files.
   - Ignore `robofinals-ikea-v3-slim.sif` completely.
2. **Preserve Reproducibility:**
   - Keep `pyproject.toml` and `uv.lock` in sync.
   - When editing `isaac-sim.def`, ensure environment variables (`VIRTUAL_ENV`, `PATH`, `ACCEPT_EULA`, `OMNI_KIT_ACCEPT_EULA`) remain intact in `%environment`.
3. **Always Include `--nv` for Container Invocations:**
   - NVIDIA GPU support requires the `--nv` flag on `apptainer run`, `apptainer exec`, `apptainer test`, and `apptainer shell`.
4. **Be Cautious with HPC Filesystem Traversal:**
   - Apptainer binds host user directories by default. Avoid commands like `find / ...` or `grep -r` inside the container without `--contain`, as they may inadvertently traverse large shared network filesystems (e.g., `/gpfs/projects`).
5. **Keep Changes Concise and Focused:**
   - Maintain concise documentation in `README.md`.
   - When suggesting fixes or enhancements, explain the rationale cleanly without unnecessary verbosity.
