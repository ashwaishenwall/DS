#!/usr/bin/env bash
set -euo pipefail
WAZUH_IP="${1:?WAZUH_PUBLIC_IP required}"
KEY="${2:?SSH private key path required}"

ssh -i "$KEY" "ubuntu@$WAZUH_IP" \
  "sudo cat /opt/fynd-devsecops/admin-credentials.txt"
