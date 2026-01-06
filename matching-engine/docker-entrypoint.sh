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

echo "========================================="
echo "Starting matching engine..."
echo "========================================="
echo ""

# Execute the CMD (passed as arguments to this script)
exec "$@"
