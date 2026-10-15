#!/usr/bin/env bash
set -euo pipefail
sudo systemctl stop docker.service docker.socket || true
sudo systemctl stop containerd.service || true
sudo rm -rf /var/lib/docker /var/lib/containerd /run/docker /run/containerd
sudo mkdir -p /var/lib/docker /var/lib/containerd /run/containerd
sudo systemctl start containerd.service
sudo systemctl start docker.socket docker.service
for i in $(seq 1 60); do
  if docker info >/dev/null 2>&1; then break; fi
  sleep 1
done
docker info >/dev/null
if [[ -n "$(docker image ls -aq)" ]]; then echo 'Docker image store is not empty' >&2; docker image ls; exit 1; fi
