#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
exec ssh -i guest_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=guest_known_hosts -o ConnectTimeout=4 -p 2222 gregor@127.0.0.1 "$@"
