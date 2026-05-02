# syntax=docker/dockerfile:1.7

# Base image
# Override BASE_IMAGE when a project needs nvcc, system cuDNN headers, or a CPU-only base.
ARG BASE_IMAGE=nvidia/cuda:12.2.0-runtime-ubuntu22.04
ARG UV_VERSION=0.6.1

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

# Common build and research workflow tools.
RUN apt-get update -o Acquire::Retries=3 \
 && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        ffmpeg \
        git \
        openssh-client \
        unzip \
 && rm -rf /var/lib/apt/lists/*

# OpenGL, MuJoCo, and headless rendering libraries. Comment this block out for a smaller image.
RUN apt-get update -o Acquire::Retries=3 \
 && apt-get install -y --no-install-recommends \
        libegl1-mesa-dev \
        libgl1-mesa-dri \
        libgl1-mesa-glx \
        libglew-dev \
        libglfw3 \
        libglu1-mesa-dev \
        libglx-mesa0 \
        libosmesa6 \
        libosmesa6-dev \
        patchelf \
 && rm -rf /var/lib/apt/lists/*

# uv is copied from the official image and pinned by UV_VERSION.
COPY --from=uv /uv /uvx /usr/local/bin/

# RCP shared storage requires the in-container UID/GID to match the EPFL identity.
ARG LDAP_USERNAME
ARG LDAP_UID
ARG LDAP_GROUPNAME
ARG LDAP_GID
RUN groupadd "${LDAP_GROUPNAME}" --gid "${LDAP_GID}" \
 && useradd -m -s /bin/bash -g "${LDAP_GROUPNAME}" -u "${LDAP_UID}" "${LDAP_USERNAME}"

# uv runtime configuration
ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_CACHE_DIR=/home/${LDAP_USERNAME}/.cache/uv

WORKDIR /home/${LDAP_USERNAME}
USER ${LDAP_USERNAME}

CMD ["bash"]
