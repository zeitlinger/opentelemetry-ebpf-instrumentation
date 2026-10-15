#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -f guest.pid ]] && kill -0 "$(cat guest.pid)" 2>/dev/null; then
  echo "VM already running (pid $(cat guest.pid))" >&2
  exit 1
fi
qemu-system-x86_64 \
  -enable-kvm -cpu host -m 8192 -smp 4 \
  -drive file=guest.qcow2,format=qcow2,if=virtio \
  -drive file=seed.iso,format=raw,media=cdrom,readonly=on \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -display none -serial file:logs/serial.log -monitor none \
  -daemonize -pidfile guest.pid
