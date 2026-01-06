#!/bin/bash
set -e

echo "========================================="
echo "Stellar Dark Pool Matching Engine"
echo "========================================="

# Generate ephemeral Stellar keypair if MATCHING_ENGINE_SIGNING_KEY is not set
if [ -z "${MATCHING_ENGINE_SIGNING_KEY}" ]; then
    echo "Generating ephemeral Stellar keypair..."

    # Generate a new keypair using stellar CLI
    stellar keys generate matching-engine --network ${STELLAR_NETWORK_PASSPHRASE:-testnet} --no-fund > /dev/null 2>&1 || true

    # Get the secret key
    export MATCHING_ENGINE_SIGNING_KEY=$(stellar keys show matching-engine)

    # Get the public key for logging
    MATCHING_ENGINE_PUBLIC=$(stellar keys address matching-engine)

    echo "✓ Generated new keypair:"
    echo "  Public Key:  $MATCHING_ENGINE_PUBLIC"
    echo "  Secret Key:  [HIDDEN]"
    echo ""
    echo "⚠️  IMPORTANT: This keypair is ephemeral and will be regenerated on container restart!"
    echo "⚠️  For production, fund this address and authorize it in the settlement contract:"
    echo ""
    echo "  1. Fund via Friendbot (testnet):"
    echo "     curl \"https://friendbot.stellar.org/?addr=$MATCHING_ENGINE_PUBLIC\""
    echo ""
    echo "  2. Authorize in settlement contract:"
    echo "     stellar contract invoke --id \$SETTLEMENT_CONTRACT_ID \\"
    echo "       --source admin --network testnet -- \\"
    echo "       set_matching_engine --matching_engine $MATCHING_ENGINE_PUBLIC"
    echo ""
else
    echo "Using MATCHING_ENGINE_SIGNING_KEY from environment"
fi

echo "========================================="
echo "Starting matching engine..."
echo "========================================="
echo ""

# Execute the CMD (passed as arguments to this script)
exec "$@"
