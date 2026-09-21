SHELL := /bin/bash

# Configuration variables
BASE_IMAGE ?= docker://nvidia/cuda:12.8.2-runtime-ubuntu24.04
BASE_SIF   ?= cuda_12.8.2-runtime-ubuntu24.04.sif
TARGET_SIF ?= isaac-sim.sif
DEF_FILE   ?= isaac-sim.def

.PHONY: all help pull-base build lock test run shell clean clean-all

all: build

help:
	@echo "Isaac HPC Container Management"
	@echo ""
	@echo "Available targets:"
	@echo "  make pull-base  Pull the base CUDA runtime image ($(BASE_SIF))"
	@echo "  make build      Build $(TARGET_SIF) (pulls base image if needed)"
	@echo "  make lock       Update Python dependencies lockfile (uv lock)"
	@echo "  make test       Run container test suite with GPU support"
	@echo "  make run        Run minimal simulation script (sim.py) with GPU"
	@echo "  make shell      Open an interactive shell inside $(TARGET_SIF)"
	@echo "  make clean      Remove the built target image ($(TARGET_SIF))"
	@echo "  make clean-all  Remove both target and base container images"

# Pull the base CUDA runtime container if it doesn't exist
$(BASE_SIF):
	@echo "[+] Pulling base image $(BASE_IMAGE)..."
	apptainer pull $(BASE_SIF) $(BASE_IMAGE)

pull-base: $(BASE_SIF)

# Build the Isaac Sim container
$(TARGET_SIF): $(BASE_SIF) $(DEF_FILE) pyproject.toml uv.lock nvidia_icd.json
	@echo "[+] Building $(TARGET_SIF) using $(DEF_FILE)..."
	apptainer build $(TARGET_SIF) $(DEF_FILE)

build: $(TARGET_SIF)

# Update uv dependency lockfile
lock:
	@echo "[+] Updating lockfile with uv..."
	uv lock

# Verify container integrity
test: $(TARGET_SIF)
	@echo "[+] Testing container with GPU..."
	apptainer test --nv $(TARGET_SIF)

# Run test simulation
run: $(TARGET_SIF)
	@echo "[+] Running headless simulation test..."
	apptainer run --nv $(TARGET_SIF) sim.py

# Launch interactive shell
shell: $(TARGET_SIF)
	@echo "[+] Launching container shell with GPU..."
	apptainer shell --nv $(TARGET_SIF)

# Clean up built artifacts
clean:
	@echo "[+] Removing $(TARGET_SIF)..."
	rm -f $(TARGET_SIF)

clean-all: clean
	@echo "[+] Removing $(BASE_SIF)..."
	rm -f $(BASE_SIF)
