#!/usr/bin/env bash
# Build helper for the RCP base container template.
# Edit these defaults or export the same names before running.

set -euo pipefail

# EPFL identity
LDAP_USERNAME="${LDAP_USERNAME:-CHANGE_ME}"            # GASPAR username
LDAP_UID="${LDAP_UID:-000000}"                          # numeric UID
LDAP_GROUPNAME="${LDAP_GROUPNAME:-CHANGE_ME}"          # primary group name
LDAP_GID="${LDAP_GID:-00000}"                           # numeric GID

# Image coordinates
# RCP convention: registry.rcp.epfl.ch/<project>/<image>:<tag>
# <project> is a Harbor project created at https://registry.rcp.epfl.ch.
PROJECT="${PROJECT:-CHANGE_ME}"
IMAGE_NAME="${IMAGE_NAME:-rcp-uv-base}"
IMAGE_TAG="${IMAGE_TAG:-v0.1}"
IMAGE="registry.rcp.epfl.ch/${PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_changed() {
    name="$1"
    value="$2"
    placeholder="$3"

    if [ -z "${value}" ] || [ "${value}" = "${placeholder}" ]; then
        die "Set ${name} in build.sh or export it before running."
    fi
}

require_numeric() {
    name="$1"
    value="$2"

    case "${value}" in
        ''|*[!0-9]*)
            die "${name} must be numeric, got '${value}'."
            ;;
    esac
}

require_image_component() {
    name="$1"
    value="$2"

    case "${value}" in
        ''|*[[:upper:]]*|*[[:space:]]*)
            die "${name} must be lowercase and contain no spaces, got '${value}'."
            ;;
    esac
}

require_changed LDAP_USERNAME "${LDAP_USERNAME}" CHANGE_ME
require_changed LDAP_UID "${LDAP_UID}" 000000
require_changed LDAP_GROUPNAME "${LDAP_GROUPNAME}" CHANGE_ME
require_changed LDAP_GID "${LDAP_GID}" 00000
require_changed PROJECT "${PROJECT}" CHANGE_ME

require_numeric LDAP_UID "${LDAP_UID}"
require_numeric LDAP_GID "${LDAP_GID}"
require_image_component PROJECT "${PROJECT}"
require_image_component IMAGE_NAME "${IMAGE_NAME}"
require_changed IMAGE_TAG "${IMAGE_TAG}" CHANGE_ME

echo "Building ${IMAGE} ..."
DOCKER_BUILDKIT=1 docker build \
    --platform linux/amd64 \
    --tag "${IMAGE}" \
    --build-arg LDAP_USERNAME="${LDAP_USERNAME}" \
    --build-arg LDAP_UID="${LDAP_UID}" \
    --build-arg LDAP_GROUPNAME="${LDAP_GROUPNAME}" \
    --build-arg LDAP_GID="${LDAP_GID}" \
    .

cat <<EOF

Built: ${IMAGE}

Next steps:
  Verify: docker run --rm -it ${IMAGE} bash -c 'id && uv --version'
  Login:  docker login registry.rcp.epfl.ch
  Push:   docker push ${IMAGE}
EOF
