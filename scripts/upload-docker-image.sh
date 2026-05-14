#!/bin/sh

set -eu

usage() {
        cat <<'EOF'
Usage:
  ./upload-image.sh IMAGE SSH_TARGET [REMOTE_IMAGE]

Examples:
  ./upload-image.sh lyceum-clash:latest root@example.com
  ./upload-image.sh lyceum-clash:latest root@example.com lyceum-clash:prod
  ./upload-image.sh myapp:latest myserver

This streams:
  docker save IMAGE | gzip | ssh SSH_TARGET 'gunzip | docker load'

REMOTE_IMAGE is optional. If set, the remote host will also run:
  docker tag IMAGE REMOTE_IMAGE
EOF
}

die() {
        echo "upload-image.sh: $*" >&2
        exit 1
}

valid_image_ref() {
        case "$1" in
                ''|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/@-]*)
                        return 1
                        ;;
        esac
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        usage
        exit 0
fi

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
        usage >&2
        exit 2
fi

image=$1
ssh_target=$2
remote_image=${3:-}

valid_image_ref "$image" || die "invalid image reference: $image"
if [ -n "$remote_image" ]; then
        valid_image_ref "$remote_image" || die "invalid remote image reference: $remote_image"
fi

command -v docker >/dev/null 2>&1 || die "docker is not installed locally"
command -v gzip >/dev/null 2>&1 || die "gzip is not installed locally"
command -v ssh >/dev/null 2>&1 || die "ssh is not installed locally"

docker image inspect "$image" >/dev/null 2>&1 || die "local image not found: $image"

remote_command='gunzip | docker load'
if [ -n "$remote_image" ]; then
        remote_command="$remote_command && docker tag $image $remote_image"
fi

echo "Uploading $image to $ssh_target..."
if [ -n "$remote_image" ]; then
        echo "Remote tag: $remote_image"
fi

docker save "$image" | gzip | ssh "$ssh_target" "$remote_command"
