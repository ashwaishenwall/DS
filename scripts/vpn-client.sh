#!/usr/bin/env bash
set -euo pipefail

APP_IP="${1:?APP_PUBLIC_IP required}"
KEY="${2:?SSH private key path required}"

umask 077
DIR="${HOME}/.fynd-devsecops"
mkdir -p "$DIR"

wg genkey | tee "$DIR/client.key" | wg pubkey > "$DIR/client.pub"
CLIENT_PUB="$(cat "$DIR/client.pub")"

ssh -o StrictHostKeyChecking=accept-new -i "$KEY" "ubuntu@$APP_IP" \
  "sudo wg set wg0 peer '$CLIENT_PUB' allowed-ips 10.8.0.2/32"

SERVER_PUB="$(ssh -i "$KEY" "ubuntu@$APP_IP" "sudo cat /etc/wireguard/server.pub")"

cat >"$DIR/fynd.conf" <<EOF
[Interface]
PrivateKey = $(cat "$DIR/client.key")
Address = 10.8.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $APP_IP:51820
AllowedIPs = 10.20.0.0/16, 10.8.0.0/24
PersistentKeepalive = 25
EOF

echo "Created $DIR/fynd.conf"
echo "Import it into the WireGuard client."
