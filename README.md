# RCP base container template

Reusable Docker base image for the EPFL RCP CaaS GPU cluster.

The image provides:

1. CUDA runtime libraries.
2. [uv](https://docs.astral.sh/uv/) for per-project Python environments.
3. An LDAP-mapped user so mounted RCP storage has the right UID/GID.

Build the image once, push it to the RCP registry, then reuse it for different uv projects. Each project is mounted as a volume and gets its own `.venv` from its `pyproject.toml` and `uv.lock`.

---

## File layout

```text
.
|-- Dockerfile          # CUDA runtime base, system deps, uv, LDAP user
|-- .dockerignore       # Minimal build context ignores
|-- build.sh            # Build wrapper with required build args
`-- README.md
```

There is intentionally **no** `pyproject.toml` / `uv.lock` / source code here. This template builds a runtime, not a project.

---

## Part 1: Build the container

### 1.1 Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed. Apple Silicon Macs are fine; `build.sh` forces `--platform linux/amd64`.

### 1.2 Find your UID / GID

When the container runs on RCP, the in-container UID/GID must match your EPFL identity. Otherwise mounted RCP storage may be read-only or owned by the wrong user.

SSH into the RCP jumphost and run `id`:

```bash
ssh <gaspar-username>@jumphost.rcp.epfl.ch id
```

The output looks like this:

```text
uid=XXXXXX(<gaspar-username>) gid=YYYYY(<LAB-GROUP-NAME>) groups=YYYYY(<LAB-GROUP-NAME>),...
```

Read off the four build-args from that line:

| Build-arg        | Where it comes from in the output                                       |
| ---------------- | ----------------------------------------------------------------------- |
| `LDAP_USERNAME`  | the name inside the parentheses after `uid=...`                         |
| `LDAP_UID`       | the number right after `uid=`                                           |
| `LDAP_GROUPNAME` | the name inside the parentheses after `gid=...` (your primary group)    |
| `LDAP_GID`       | the number right after `gid=`                                           |

If you have an SSH alias for the jumphost (e.g. `Host EPFL_RCP` in `~/.ssh/config`), `ssh EPFL_RCP id` works too.

This command prints shell assignments you can paste into `build.sh`:

```bash
ssh <gaspar-username>@jumphost.rcp.epfl.ch \
    'printf "LDAP_USERNAME=%s\nLDAP_UID=%s\nLDAP_GROUPNAME=%s\nLDAP_GID=%s\n" "$(id -un)" "$(id -u)" "$(id -gn)" "$(id -g)"'
```

If SSH isn't available, look up the same values at [it-info.epfl.ch](https://it-info.epfl.ch) or ask your lab admin.

### 1.3 Rendering / MuJoCo support

The `Dockerfile` installs OpenGL, OSMesa, GLFW, and patchelf by default. These are useful for RL, robotics, simulation, NeRF, and video recording.

If your workload does not need rendering, comment the OpenGL/MuJoCo `RUN` block in the `Dockerfile` to make the image smaller.

### 1.4 Build the image

Edit the values at the top of `build.sh`:

```bash
LDAP_USERNAME="<gaspar-username>"
LDAP_UID="<UID>"
LDAP_GROUPNAME="<LAB-GROUP-NAME>"
LDAP_GID="<GID>"
PROJECT="<harbor-project>"        # Harbor project you created
IMAGE_NAME="rcp-uv-base"
IMAGE_TAG="v0.1"
```

If you prefer environment variables, use `export NAME=value` before running `build.sh`. Plain `NAME=value` variables are not inherited by `./build.sh`.

Then:

```bash
./build.sh
```

Or call `docker build` directly:

```bash
DOCKER_BUILDKIT=1 docker build \
    --platform linux/amd64 \
    --tag registry.rcp.epfl.ch/<harbor-project>/rcp-uv-base:v0.1 \
    --build-arg LDAP_USERNAME=<gaspar-username> \
    --build-arg LDAP_UID=<UID> \
    --build-arg LDAP_GROUPNAME=<LAB-GROUP-NAME> \
    --build-arg LDAP_GID=<GID> \
    .
```

#### Choosing a base image

Default is `nvidia/cuda:12.2.0-runtime-ubuntu22.04` (~1.5 GB). It works for uv projects that install PyTorch, JAX, or other GPU libraries from prebuilt wheels. Those wheels usually bundle the CUDA/cuDNN pieces they need, so the base image does not need system cuDNN by default.

Swap to a heavier variant only when you actually need to:

| Override `--build-arg BASE_IMAGE=...` | When you need it |
| --- | --- |
| `nvidia/cuda:12.2.0-devel-ubuntu22.04` | Compiling CUDA extensions from source: flash-attn, xformers `--no-binary`, custom CUDA kernels, anything that runs `nvcc` during `pip install` / `uv sync`. |
| `nvidia/cuda:12.2.0-cudnn8-devel-ubuntu22.04` | The above, plus libraries that link against system cuDNN headers at build time. |
| `nvcr.io/nvidia/pytorch:24.10-py3` | NGC's pre-built PyTorch image. Heavy; usually unnecessary when uv already pins PyTorch. |
| `ubuntu:22.04` | CPU-only local iteration, no GPU stack at all. |

If a build fails with `nvcc: not found` or a missing `cudnn.h`, that's the signal to step up to a `devel` variant.

### 1.5 Smoke-test locally

```bash
docker run --rm -it \
    registry.rcp.epfl.ch/<harbor-project>/rcp-uv-base:v0.1 \
    bash -c 'whoami && id && uv --version'
```

Expected output (placeholders for your real values):

```text
<gaspar-username>
uid=<UID>(<gaspar-username>) gid=<GID>(<LAB-GROUP-NAME>) groups=<GID>(<LAB-GROUP-NAME>)
uv 0.6.x
```

If the username, UID, and GID are correct, push the image.

---

## Part 2: Use the RCP Registry

RCP runs a [Harbor](https://goharbor.io/) registry at:
**[registry.rcp.epfl.ch](https://registry.rcp.epfl.ch)**

### 2.1 Web login

Open <https://registry.rcp.epfl.ch> and log in with your GASPAR account.

### 2.2 Create a project

Each Harbor project is a namespace (it becomes `registry.rcp.epfl.ch/<project>/...`).
A whole lab can share one project, or you can create one per research direction.

#### Public vs Private

- **Public**: any RCP user can pull. Good for sharing.
- **Private**: only members or robot accounts can pull.

You can choose at creation time, or change it later in project settings.

### 2.3 Add members

Members: add by GASPAR username and pick a role (Developer / Maintainer / ProjectAdmin / ...).

> The currently deployed Harbor version does **not** support LDAP-group permissions. Add individual users instead.

### 2.4 Robot account (required for private projects)

Cluster jobs (Run.ai / Kubernetes) need to pull images from the registry, but **must not** use your GASPAR account.
Create a **Robot Account** inside the project instead:

1. Project > Robot Accounts > New Robot Account
2. Set the expiration and permissions (usually `pull` is enough)
3. Save the generated name and secret. They are shown only once.

Then create an image-pull `Secret` in your Run.ai / Kubernetes namespace using those credentials. See the RCP "how-to-use-secret" docs for the exact YAML.

### 2.5 Docker CLI: login, push, pull

#### Login

```bash
docker login registry.rcp.epfl.ch
# Username: <GASPAR username>
# Password: <GASPAR password>
```

#### Tag with multiple versions (optional)

```bash
docker build -t registry.rcp.epfl.ch/<project>/<image>:latest \
             -t registry.rcp.epfl.ch/<project>/<image>:v0.1 .
```

`latest` is the default tag. `docker run` without an explicit tag pulls `latest`.

#### Push

```bash
docker push registry.rcp.epfl.ch/<project>/<image>:latest
docker push registry.rcp.epfl.ch/<project>/<image>:v0.1
```

#### Pull

```bash
docker pull registry.rcp.epfl.ch/<project>/<image>:latest
```

#### Re-tag an existing image (no rebuild)

For example, mirror a Docker Hub image into RCP:

```bash
docker pull alpine
docker tag alpine registry.rcp.epfl.ch/<project>/alpine:latest
docker push registry.rcp.epfl.ch/<project>/alpine:latest
```

#### Logout

```bash
docker logout registry.rcp.epfl.ch
```

---

## Part 3: Run a uv project inside the base container

The base image has no project source in it. Mount a uv project, run `uv sync`, and the project gets its own `.venv` inside the mounted directory.

### 3.1 The basic workflow

For a uv project with `pyproject.toml` and `uv.lock` in the project root:

```bash
docker run --rm -it \
    --gpus all \
    -v ~/dev/my-experiment:/home/<gaspar-username>/my-experiment \
    -v ~/.cache/rcp-uv:/home/<gaspar-username>/.cache/uv \
    -w /home/<gaspar-username>/my-experiment \
    registry.rcp.epfl.ch/<harbor-project>/rcp-uv-base:v0.1 \
    bash -lc 'uv sync --locked && uv run python train.py'
```

What this does:

- `-v ~/dev/my-experiment:/home/<gaspar-username>/my-experiment` mounts the project inside the container user's home directory.
- `-v ~/.cache/rcp-uv:/home/<gaspar-username>/.cache/uv` keeps uv's package cache on your host. If you skip this mount, the project's `.venv` still persists, but downloaded packages are cached only for that container run.
- `-w` makes that mount the working directory.
- `uv sync --locked` reads the project's `pyproject.toml` / `uv.lock` and creates `.venv` inside the mount. Because the mount is on your host or RCP shared storage, the `.venv` persists between runs.
- `uv run python train.py` runs your script in that venv.

You can swap `train.py` for `bash` to drop into an interactive shell, or for any other command (`uv run pytest`, `uv run jupyter lab`, etc.).

### 3.2 Switching between projects

For each new experiment, change only the volume mount and the working directory:

```bash
# Project A
docker run ... -v ~/dev/project-a:/home/<gaspar-username>/project-a \
               -v ~/.cache/rcp-uv:/home/<gaspar-username>/.cache/uv \
               -w /home/<gaspar-username>/project-a \
               registry.rcp.epfl.ch/<harbor-project>/rcp-uv-base:v0.1 \
               bash -lc 'uv sync --locked && uv run python train.py'

# Project B
docker run ... -v ~/dev/project-b:/home/<gaspar-username>/project-b \
               -v ~/.cache/rcp-uv:/home/<gaspar-username>/.cache/uv \
               -w /home/<gaspar-username>/project-b \
               registry.rcp.epfl.ch/<harbor-project>/rcp-uv-base:v0.1 \
               bash -lc 'uv sync --locked && uv run python eval.py'
```

The base image stays the same. Each project keeps its own `pyproject.toml`, `uv.lock`, and `.venv` inside its own directory.

### 3.3 On the RCP cluster

The same pattern maps to a Run.ai or Kubernetes job:

- The `image` in the job spec is your pushed base: `registry.rcp.epfl.ch/<harbor-project>/rcp-uv-base:v0.1`.
- The `-v` volume mount becomes a PVC mount onto your home or scratch path.
- The uv cache path is `/home/<gaspar-username>/.cache/uv`; mount that path, or mount the whole home directory, if you want package downloads to persist between cluster jobs.
- The `--gpus all` flag is replaced by the cluster's GPU request mechanism (Run.ai's `gpu` field, or a Kubernetes `nvidia.com/gpu` resource).
- The `command` / `args` is the same `uv sync --locked && uv run python ...` line.

---

## Notes

- Do not put passwords, API keys, or tokens in the Dockerfile or in git. Use Run.ai / Kubernetes Secrets.
- Containers are ephemeral. Put checkpoints, logs, datasets, and project source on mounted storage.
- `.venv` lives on the mounted project volume, not in the image.
- uv's package cache lives at `/home/<gaspar-username>/.cache/uv`. Mount that path if you want downloads to persist.
- Use versioned tags such as `v0.3` for reproducible jobs. Do not rely on `latest` long term.
- Re-run `uv lock` in your project after editing `pyproject.toml`; `uv sync --locked` will fail if the lockfile is stale.
- Apple Silicon Macs must build with `--platform linux/amd64`. The cluster is amd64.
- The base image is per-user because UID/GID are baked in at build time.

---

## References

- [RCP CaaS: How to build a container](https://wiki.rcp.epfl.ch/en/home/CaaS/FAQ/how-to-build-a-container-part2)
- [RCP registry docs](https://wiki.rcp.epfl.ch/home/CaaS/FAQ/how-to-registry)
- [RCP Registry: Harbor](https://registry.rcp.epfl.ch)
- [uv official Docker guide](https://docs.astral.sh/uv/guides/integration/docker/)
