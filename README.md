# Isaac HPC

Building an Apptainer native Isaac Sim (and Lab) container.

There are [Isaac Sim](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/isaac-sim) and [Isaac Lab](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/isaac-lab) Docker containers from [NGC](https://catalog.ngc.nvidia.com/orgs/nvidia/collections/cuda_toolkit/artifacts). The setup for these containers didn't seem intuitive when I looked and I thought I'd (maybe) learn something by going through the pain to set it up myself. Since moving Isaac Sim to PyPi the setup has been much easier and negates some of the initial motivation for this repo. However, there's still some value in setting up an environment around the core packages.

```
apptainer pull cuda_12.1.1-runtime-ubuntu22.04.sif docker://nvidia/cuda:12.1.1-runtime-ubuntu22.04
apptainer build isaac-sim.sif isaac-sim.def
```
