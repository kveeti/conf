#!/usr/bin/env bash

# usage: [--qr] <client_name> <server_pubkey> <server_endpoint> <client_ip>

set -euo pipefail

SHOW_QR=false
ARGS=()

for arg in "$@"; do
    if [[ "$arg" == "--qr" ]]; then
        SHOW_QR=true
    else
        ARGS+=("$arg")
    fi
done

CLIENT_NAME="${ARGS[0]:-}"
SERVER_PUBLIC_KEY="${ARGS[1]:-}"
SERVER_ENDPOINT="${ARGS[2]:-}"
CLIENT_IP="${ARGS[3]:-}"

if [[ -z "$CLIENT_NAME" || -z "$SERVER_PUBLIC_KEY" || -z "$SERVER_ENDPOINT" || -z "$CLIENT_IP" ]]; then
    echo "usage: $0 [--qr] <client_name> <server_pubkey> <server_endpoint> <client_ip>"
    echo "example: $0 jogn abc123... 1.2.3.4:51820 10.0.0.2"
    echo "example: $0 --qr john abc123... 1.2.3.4:51820 10.0.0.2"
    exit 1
fi

# generate client keys
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PRESHARED_KEY=$(wg genpsk)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

# create client config
CONFIG=$(cat << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/32
DNS = 10.255.255.1

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
PresharedKey = $CLIENT_PRESHARED_KEY
Endpoint = $SERVER_ENDPOINT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 21
EOF
)

echo "--- config ---"
echo "$CONFIG"
echo "--- config ---"
echo ""

# show QR code if --qr flag is given
if [[ "$SHOW_QR" == "true" ]]; then
    if command -v qrencode &> /dev/null; then
        echo "--- QR code ---"
        echo "$CONFIG" | qrencode -t ANSIUTF8
        echo "--- QR code ---"
    else
        echo "Error: 'qrencode' is not installed. Install it to use --qr flag"
        exit 1
    fi
    echo ""
fi

echo "client public key: $CLIENT_PUBLIC_KEY"
echo "add this to server config:"
echo ""
echo "[Peer]"
echo "PublicKey = $CLIENT_PUBLIC_KEY"
echo "AllowedIPs = $CLIENT_IP/32"

