# Disposable KVM Docker guest for OBI benchmarks

Created 2026-10-14 under this durable benchmark directory; no host packages were installed.

## Host prerequisites verified

- Ubuntu 24.04.5 host, x86_64.
- `/usr/bin/qemu-system-x86_64` and `/usr/bin/qemu-img` available.
- `/dev/kvm` available; its ACL grants the `gregor` user read/write.
- QEMU `-enable-kvm` boots this guest successfully.
- QEMU user-mode networking provides outbound guest access and SSH forwarding on `127.0.0.1:2222`; no host TAP/TUN device is used.
- Docker, Podman, libvirt, and Buildah are not installed on the host.

## Bootstrap steps (reproducible artifacts are here)

1. Downloaded the official Ubuntu Noble cloud image and `SHA256SUMS` from `https://cloud-images.ubuntu.com/noble/current/`; `logs/image-check.log` records the successful checksum. Base image is `noble-server-cloudimg-amd64.img`.
2. Downloaded the pure-Python `pycdlib` wheel into `tools/pycdlib.whl`, extracted it under `tools/pycdlib/` with Python's standard-library `zipfile`, and used `build-seed.py` to create `seed.iso` (volume label `CIDATA`) with NoCloud cloud-init `seed/user-data` and `seed/meta-data`. This avoids installing system packages on the host. The private SSH key is `guest_ed25519`; it is local benchmark material and must not be published.
3. Created `guest.qcow2` as a 40 GiB qcow2 overlay backed by the downloaded cloud image. Cloud-init creates the `gregor` sudo user with the key, updates apt, installs Ubuntu's `docker.io`, then attempts `docker-buildx`, enables Docker, and adds the user to the docker group.
4. Started QEMU using `boot-guest.sh`: KVM acceleration, 8 GiB RAM, 4 vCPUs, virtio disk/network, QEMU user networking, and host port 2222 forwarded to guest SSH. Serial output is `logs/serial.log`; `ssh-guest.sh` connects using the local key.
5. Verified cloud-init completed with no errors; Docker daemon is active; Docker server/client version 29.1.3; Buildx 0.30.1; storage driver `overlayfs`; architecture x86_64. `docker run --rm hello-world` succeeded (initially pulled the image). Details in `logs/guest-ready.txt` and `logs/cloud-init-output.log`.

## VM lifecycle

The VM is left running for the requested later benchmark work. Stop it with `kill "$(cat guest.pid)"` and restart using `./boot-guest.sh`. Do not use this prewarmed `hello-world` image as a first-use test target. Benchmark output should remain outside the guest under the sibling durable benchmark directory; use a fresh guest overlay or remove only the intended target image/cache before measuring.
