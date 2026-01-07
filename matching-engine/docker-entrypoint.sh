#!/bin/bash
set -e

echo "========================================="
echo "Stellar Dark Pool Matching Engine"
echo "========================================="

# Always generate ephemeral Stellar keypair
echo "Generating ephemeral Stellar keypair..."

# Generate a new keypair using Python stellar-sdk
KEYPAIR_DATA=$(python3 -c "from stellar_sdk import Keypair; kp = Keypair.random(); print(f'{kp.secret}|{kp.public_key}')")

# Extract secret and public keys
export MATCHING_ENGINE_SIGNING_KEY=$(echo "$KEYPAIR_DATA" | cut -d'|' -f1)
MATCHING_ENGINE_PUBLIC=$(echo "$KEYPAIR_DATA" | cut -d'|' -f2)

echo "✓ Generated new keypair:"
echo "  Public Key:  $MATCHING_ENGINE_PUBLIC"
echo "  Secret Key:  [HIDDEN]"
echo ""
echo "Configuration:"
echo "  Settlement Contract ID: ${SETTLEMENT_CONTRACT_ID:-[NOT SET]}"
echo ""
echo "⚠️  IMPORTANT: This keypair is ephemeral and will be regenerated on container restart!"
echo "⚠️  To use the matching engine, fund and authorize this address:"
echo ""
echo "  1. Fund via Friendbot (testnet):"
echo "     curl \"https://friendbot.stellar.org/?addr=$MATCHING_ENGINE_PUBLIC\""
echo ""
echo "  2. Authorize in settlement contract (using Stellar CLI on host):"
echo "     stellar contract invoke --id \$SETTLEMENT_CONTRACT_ID \\"
echo "       --source admin --network testnet -- \\"
echo "       set_matching_engine --matching_engine $MATCHING_ENGINE_PUBLIC"
echo ""

if [ -z "${TLS_CERT_PATH:-}" ] || [ -z "${TLS_KEY_PATH:-}" ]; then
    echo "Generating self-signed TLS certificate (TLS passthrough mode)..."
    mkdir -p /tmp/tls
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /tmp/tls/key.pem \
        -out /tmp/tls/cert.pem \
        -days 365 \
        -subj "/CN=${MATCHING_ENGINE_PUBLIC}" >/dev/null 2>&1
    export TLS_CERT_PATH="/tmp/tls/cert.pem"
    export TLS_KEY_PATH="/tmp/tls/key.pem"
fi

if [ -f "${TLS_CERT_PATH:-}" ] && [ -f "${TLS_KEY_PATH:-}" ]; then
    echo "TLS enabled with certificate:"
    echo "  TLS_CERT_PATH: ${TLS_CERT_PATH}"
    echo "  TLS_KEY_PATH:  ${TLS_KEY_PATH}"
else
    echo "TLS not enabled (certificate files not found)."
fi
echo ""

echo "========================================="
echo "Starting matching engine..."
echo "========================================="
echo ""

# Execute the CMD (passed as arguments to this script)
exec "$@"
