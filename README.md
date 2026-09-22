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

- `Makefile`: Convenient automation targets (`make pull-base`, `make build`, `make test`, etc.).
- `isaac-sim.def`: Apptainer definition file configuring system packages, `uv`, and runtime environment.
- `nvidia_icd.json`: NVIDIA Vulkan ICD configuration for headless and off-screen GPU rendering.
- `pyproject.toml`: Python dependency specifications and wheel indexes.
- `uv.lock`: Frozen lockfile used by `uv sync` for reproducible container builds.
- `sim.py`: Minimal headless simulation verification script.

## Building the Container

You can use `make` for automated builds (pulls the base CUDA image automatically if not present):

```bash
make build
```

Alternatively, you can run the steps manually:

### 1. Pull the CUDA Base Image
```bash
apptainer pull cuda_12.8.2-runtime-ubuntu24.04.sif docker://nvidia/cuda:12.8.2-runtime-ubuntu24.04
```

### 2. Build the SIF Container
The definition file copies `pyproject.toml` and `uv.lock` into the container and executes `uv sync --frozen`:

```bash
apptainer build isaac-sim.sif isaac-sim.def
```

> **Note:** If you modify dependencies in `pyproject.toml`, update `uv.lock` with `make lock` (or `uv lock`) before building.

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

---

## Bootstrapping New Projects

Depending on whether your workflow requires modifying the base container or developing an external codebase against it, you can bootstrap a new project using one of the following patterns:

### Workflow A: Adding Packages Directly via `uv` (Recommended for Self-Contained Images)

If you need additional Python libraries (e.g., `wandb`, `viser`, `rerun-sdk`, `skrl`, or `lerobot`) baked permanently into the container:

1. **Add packages to `pyproject.toml`:**
   Add packages to the `dependencies` list in [`pyproject.toml`](file:///gpfs/scrubbed/npho/isaac-hpc/pyproject.toml):
   ```toml
   dependencies = [
       "torch==2.11.0",
       "torchvision==0.26.0",
       "isaacsim[all,extscache]==6.1.0.0",
       "isaaclab>=3.0.0rc1",
       "rsl-rl-lib==5.4.1",
       "viser>=1.0.0",        # New dependency
       "wandb>=0.19.0",       # New dependency
   ]
   ```
   *(Or if you have `uv` installed on your host, run `uv add <package>`.)*

2. **Update the frozen lockfile:**
   Regenerate `uv.lock` deterministically:
   ```bash
   make lock
   # or: uv lock
   ```

3. **Rebuild the container:**
   ```bash
   make build
   ```
   The build recipe executes `uv sync --frozen --no-dev --compile-bytecode`, ensuring exact, reproducible package installations.

> [!TIP]
> **Custom package indexes and Git sources:**
> You can configure alternative wheel indexes (e.g. PyTorch, Hugging Face, private package registries) or Git repositories directly in `pyproject.toml`:
> ```toml
> [tool.uv.sources]
> my-custom-pkg = { git = "https://github.com/my-org/my-pkg.git", branch = "main" }
> ```

---

### Workflow B: Developing External Projects (Host Bind-Mount)

For active day-to-day development where you modify code on the host filesystem without rebuilding the container:

1. **Develop on the host filesystem:**
   Keep your project repository on the cluster filesystem (e.g., `/gpfs/projects/my_project`).

2. **Execute inside the container via bind-mount (`-B`):**
   ```bash
   apptainer run --nv \
       -B /gpfs/projects/my_project:/workspace/my_project \
       isaac-sim.sif /workspace/my_project/train.py --task Isaac-Cartpole-v0
   ```

3. **Installing ephemeral runtime dependencies:**
   If your external project has custom dependencies you want to test without rebuilding `isaac-sim.sif`, install them directly into the container virtual environment during an interactive session:
   ```bash
   apptainer exec --nv -B $(pwd):/app isaac-sim.sif \
       uv pip install --python /workspace/.venv -e /app
   ```

---

### Workflow C: Building a Derived (Layered) Container

If your research group maintains `isaac-sim.sif` as a shared "golden image" and you want to build a lightweight, project-specific container on top:

1. Create a `my-project.def` definition file:
   ```apptainer
   Bootstrap: localimage
   From: isaac-sim.sif

   %files
       ./pyproject.toml /workspace/my_project/pyproject.toml
       ./src /workspace/my_project/src

   %post
       export VIRTUAL_ENV=/workspace/.venv
       export PATH=/workspace/.venv/bin:${PATH}

       # Install project packages on top of the pre-built virtualenv
       uv pip install --python /workspace/.venv -e /workspace/my_project
   ```

2. Build the project-specific layer:
   ```bash
   apptainer build my-project.sif my-project.def
   ```

---

### Workflow D: Built-In Source Hook (`/workspace/src`)

[`isaac-sim.def`](file:///gpfs/scrubbed/npho/isaac-hpc/isaac-sim.def) already includes a built-in hook for source trees:
1. Place your project code in a `src/` directory containing a `pyproject.toml` or `setup.py`.
2. In `isaac-sim.def`, uncomment the `%files` line:
   ```apptainer
   %files
       pyproject.toml /workspace/pyproject.toml
       uv.lock /workspace/uv.lock
       src /workspace/src
   ```
3. Run `make build`. During `%post`, the definition file automatically runs:
   ```bash
   if [ -f "/workspace/src/pyproject.toml" ]; then
       cd /workspace/src && uv pip install --no-deps -e .
   fi
   ```
