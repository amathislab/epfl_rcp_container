# RCP uv base container

This repository builds one reusable Docker image for the EPFL RCP CaaS GPU cluster.

The image contains:

1. CUDA runtime libraries.
2. [uv](https://docs.astral.sh/uv/) for Python environments.
3. A Linux user whose UID and RCP group match your EPFL account.

Your research code is not copied into this image. You mount each project when you run the container, then `uv sync` creates that project's `.venv` inside the mounted project directory.

## Repository files

```text
.
|-- Dockerfile          # CUDA base image, system packages, uv, EPFL user
|-- .dockerignore       # Files ignored by docker build
|-- build.sh            # Small wrapper around docker build
`-- README.md
```

## Before you start

You need:

- Docker installed on your laptop or workstation.
- Access to RCP / Run.ai.
- A Harbor project on <https://registry.rcp.epfl.ch>.
- Your EPFL UID and the correct RCP group GID. Get these from an RCP machine, not from your laptop.

Apple Silicon Macs are fine. `build.sh` already builds for `linux/amd64`, which is the cluster architecture.

## 1. Find your UID and RCP group GID

SSH to an RCP machine and run `id`.

For example:

```bash
ssh <gaspar-username>@jumphost.rcp.epfl.ch
id
```

You can also run `id` from another RCP login node, such as `haas001`, if that is where you normally work.

The important point: **do not blindly use the `gid=...` value near the start of the line**. That is only your default Unix group. For RCP containers, you usually want the group that gives access to your Run.ai namespace or shared storage. It may appear later in the `groups=...` list.

Example with fake values:

```text
uid=123456(student1) gid=11111(LAB-StaffU) groups=11111(LAB-StaffU),...,79999(rcp-runai-lab_AppGrpU),...
```

For this example, use:

```bash
LDAP_USERNAME="student1"
LDAP_UID="123456"
LDAP_GROUPNAME="rcp-runai-lab_AppGrpU"
LDAP_GID="79999"
```

Do **not** use `LDAP_GID=11111` unless `LAB-StaffU` is the group that owns the storage or namespace you need.

Useful ways to find the right group:

```bash
# Show your Run.ai-related groups.
id | tr ',' '\n' | grep -i 'rcp-runai'

# Search by lab or project name.
id | tr ',' '\n' | grep -i '<lab-or-project-name>'

# If someone gave you the numeric GID, confirm the matching group name.
id | tr ',' '\n' | grep '<rcp-group-gid>'
```

If the expected group is not listed by `id`, your account probably has not been added to that RCP group yet. Ask your lab admin or RCP support before building the image.

## 2. Build the image

Edit the values at the top of `build.sh`:

```bash
LDAP_USERNAME="<gaspar-username>"
LDAP_UID="<numeric-uid>"
LDAP_GROUPNAME="<rcp-group-name>"
LDAP_GID="<rcp-group-gid>"

PROJECT="<harbor-project>"
IMAGE_NAME="rcp-uv-base"
IMAGE_TAG="v0.1"
```

Concrete example:

```bash
LDAP_USERNAME="student1"
LDAP_UID="123456"
LDAP_GROUPNAME="rcp-runai-lab_AppGrpU"
LDAP_GID="79999"

PROJECT="my-harbor-project"
IMAGE_NAME="rcp-uv-base"
IMAGE_TAG="v0.1"
```

Then build:

```bash
./build.sh
```

The script builds:

```text
registry.rcp.epfl.ch/<harbor-project>/rcp-uv-base:v0.1
```

You can also keep `build.sh` unchanged and pass values as environment variables:

```bash
LDAP_USERNAME="student1" \
LDAP_UID="123456" \
LDAP_GROUPNAME="rcp-runai-lab_AppGrpU" \
LDAP_GID="79999" \
PROJECT="my-harbor-project" \
./build.sh
```

## 3. Test the image locally

Run:

```bash
docker run --rm -it \
    registry.rcp.epfl.ch/<harbor-project>/rcp-uv-base:v0.1 \
    bash -c 'whoami && id && uv --version'
```

Check that the output contains your username, UID, and chosen RCP group:

```text
student1
uid=123456(student1) gid=79999(rcp-runai-lab_AppGrpU) groups=79999(rcp-runai-lab_AppGrpU)
uv 0.6.x
```

If the GID is wrong, fix `LDAP_GROUPNAME` and `LDAP_GID`, then rebuild.

## 4. Push to the RCP registry

Open <https://registry.rcp.epfl.ch> and log in with your GASPAR account.

Create a Harbor project if you do not already have one. The project name is the middle part of the image path:

```text
registry.rcp.epfl.ch/<harbor-project>/<image-name>:<tag>
```

Then log in from Docker and push:

```bash
docker login registry.rcp.epfl.ch
docker push registry.rcp.epfl.ch/<harbor-project>/rcp-uv-base:v0.1
```

For a private Harbor project, create a robot account in Harbor and use it as the image-pull secret for Run.ai / Kubernetes jobs. Do not put your GASPAR password in job YAML files.

## 5. Run a uv project with the image

The image is only the base environment. Your project directory should contain its own `pyproject.toml` and `uv.lock`.

Local example:

```bash
docker run --rm -it \
    --gpus all \
    -v ~/dev/my-experiment:/home/<gaspar-username>/my-experiment \
    -v ~/.cache/rcp-uv:/home/<gaspar-username>/.cache/uv \
    -w /home/<gaspar-username>/my-experiment \
    registry.rcp.epfl.ch/<harbor-project>/rcp-uv-base:v0.1 \
    bash -lc 'uv sync --locked && uv run python train.py'
```

Replace:

- `~/dev/my-experiment` with your project path.
- `<gaspar-username>` with your GASPAR username.
- `<harbor-project>` with your Harbor project.
- `train.py` with the command you want to run.

What persists:

- The project `.venv` is created inside the mounted project directory.
- The uv download cache is stored in `~/.cache/rcp-uv` on the host because of the second `-v` mount.
- Anything not written to a mounted directory disappears when the container exits.

To open a shell instead of running training:

```bash
docker run --rm -it \
    --gpus all \
    -v ~/dev/my-experiment:/home/<gaspar-username>/my-experiment \
    -v ~/.cache/rcp-uv:/home/<gaspar-username>/.cache/uv \
    -w /home/<gaspar-username>/my-experiment \
    registry.rcp.epfl.ch/<harbor-project>/rcp-uv-base:v0.1 \
    bash
```

## 6. Use it on RCP / Run.ai

Use the same image in your Run.ai or Kubernetes job:

```text
registry.rcp.epfl.ch/<harbor-project>/rcp-uv-base:v0.1
```

The local Docker command maps to the cluster like this:

| Local Docker option | Run.ai / Kubernetes equivalent |
| --- | --- |
| `-v ~/dev/my-experiment:...` | mount your PVC or shared storage path |
| `-w /home/<user>/my-experiment` | set the container working directory |
| `--gpus all` | request a GPU in Run.ai / Kubernetes |
| `bash -lc 'uv sync --locked && ...'` | job command / args |

Put checkpoints, logs, datasets, and source code on mounted storage.

## Base image choices

The default base image is:

```text
nvidia/cuda:12.2.0-runtime-ubuntu22.04
```

This is enough for most uv projects that install PyTorch, JAX, or other GPU libraries from wheels.

Use a heavier base only when needed:

| Base image | When to use it |
| --- | --- |
| `nvidia/cuda:12.2.0-devel-ubuntu22.04` | You need `nvcc` to compile CUDA extensions. |
| `nvidia/cuda:12.2.0-cudnn8-devel-ubuntu22.04` | You need `nvcc` and system cuDNN headers. |
| `nvcr.io/nvidia/pytorch:24.10-py3` | You want NVIDIA's full PyTorch image. This is much larger. |
| `ubuntu:22.04` | CPU-only testing with no CUDA stack. |

Example:

```bash
BASE_IMAGE="nvidia/cuda:12.2.0-devel-ubuntu22.04" ./build.sh
```

If a build fails with `nvcc: not found` or `cudnn.h: No such file or directory`, switch to one of the `devel` images.

## Troubleshooting

Permission errors on RCP storage usually mean the image was built with the wrong group. Re-run `id` on an RCP machine, find the group that owns the storage or Run.ai namespace, update `LDAP_GROUPNAME` and `LDAP_GID`, then rebuild and push a new tag.

If `uv sync --locked` fails because the lockfile is stale, run `uv lock` in the project repository, commit the updated `uv.lock`, then try again.

If Docker says the image cannot be pulled by a cluster job, check that the Harbor project exists, the image was pushed, and the Run.ai / Kubernetes image-pull secret uses a Harbor robot account for private projects.

## References

- [RCP CaaS: How to build a container](https://wiki.rcp.epfl.ch/en/home/CaaS/FAQ/how-to-build-a-container-part2)
- [RCP registry docs](https://wiki.rcp.epfl.ch/home/CaaS/FAQ/how-to-registry)
- [RCP Registry: Harbor](https://registry.rcp.epfl.ch)
- [uv official Docker guide](https://docs.astral.sh/uv/guides/integration/docker/)
