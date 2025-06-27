# Isaac HPC

Building an Apptainer native Isaac Sim (and Lab) container.

Yes, I know there are [Isaac Sim](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/isaac-sim) and [Isaac Lab](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/isaac-lab) Docker containers from NGC. The setup for these containers didn't seem intuitive when I looked and I thought I'd (maybe) learn something by going through the pain to set it up myself.

```
apptainer pull rocky9_cuda-dev-12.9.1.sif docker://nvcr.io/nvidia/cuda:12.9.1-devel-rockylinux9
```
