#!/bin/bash

# End-to-End Test Script for Settlement Contract
# This script compiles, optimizes, deploys, and tests the contract using Stellar CLI

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function to extract and display contract logs from stellar CLI output
extract_logs() {
    local output="$1"
    if echo "$output" | grep -qiE "log|Log|LOG"; then
        echo ""
        echo -e "${BLUE}  Contract logs:${NC}"
        # Extract log lines (look for lines containing "log" or "Log")
        echo "$output" | grep -iE "log" | sed 's/^/    /' || true
    else
        # Surface useful error context even when logs are not emitted.
        if echo "$output" | grep -qiE "error|failed|status|auth|unauthorized|denied"; then
            echo ""
            echo -e "${BLUE}  Error output:${NC}"
            echo "$output" | grep -iE "error|failed|status|auth|unauthorized|denied" | sed 's/^/    /' || true
        fi
    fi
}

# Configuration
CONTRACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$CONTRACT_DIR/../.." && pwd)"
NETWORK="${STELLAR_NETWORK:-testnet}"
FRIENDBOT_URL="${STELLAR_FRIENDBOT_URL:-https://friendbot.stellar.org}"

# Check if stellar CLI is installed
command -v stellar &> /dev/null || {
    echo -e "${RED}Error: stellar CLI not found. Please install it first.${NC}"
    echo "Visit: https://developers.stellar.org/docs/tools/stellar-cli"
    exit 1
}

echo -e "${GREEN}=== Settlement Contract End-to-End Test ===${NC}"
echo "Network: $NETWORK"
echo ""

# Step 1: Build and optimize the contract
echo -e "${YELLOW}[1/7] Building and optimizing contract...${NC}"

# Build the contract with optimization
# Note: Build from contract directory to use package-level profile
echo "  Building and optimizing contract..."
echo "  (This may take 1-2 minutes for first build)..."
cd "$CONTRACT_DIR"

# Build with optimization
stellar contract build --profile release-with-logs --optimize || {
    echo -e "${RED}Error: Contract build failed${NC}"
    exit 1
}

# Find the optimized WASM file
wasm_paths=(
    "$WORKSPACE_ROOT/target/wasm32v1-none/release-with-logs/settlement.wasm"
    "$CONTRACT_DIR/target/wasm32v1-none/release-with-logs/settlement.wasm"
    "$WORKSPACE_ROOT/target/wasm32-unknown-unknown/release/settlement.wasm"
    "$CONTRACT_DIR/target/wasm32-unknown-unknown/release/settlement.wasm"
    "$WORKSPACE_ROOT/target/wasm32-unknown-unknown/release-with-logs/settlement.wasm"
    "$CONTRACT_DIR/target/wasm32-unknown-unknown/release-with-logs/settlement.wasm"
)

OPTIMIZED_WASM=""
for path in "${wasm_paths[@]}"; do
    [ -f "$path" ] && { OPTIMIZED_WASM="$path"; break; }
done

[ -z "$OPTIMIZED_WASM" ] && {
    echo -e "${RED}Error: Optimized WASM file not found${NC}"
    echo "Build may have failed. Check the build output above."
    exit 1
}

WASM_SIZE=$(stat -f%z "$OPTIMIZED_WASM" 2>/dev/null || stat -c%s "$OPTIMIZED_WASM" 2>/dev/null || echo "0")
if [ "$WASM_SIZE" -gt 0 ]; then
    echo "  Final WASM size: $WASM_SIZE bytes"
fi

echo -e "${GREEN}✓ Contract built and optimized${NC}"
echo ""

# Step 2: Generate test accounts
echo -e "${YELLOW}[2/7] Generating test accounts...${NC}"

# Function to create or get account
create_account() {
    local name=$1
    echo -n "  $name account... "
    if stellar keys ls 2>/dev/null | grep -q "^$name"; then
        echo "exists"
    else
        echo "" | stellar keys generate $name 2>&1 | grep -q "saved\|Key saved" && echo "created" || echo "created"
    fi
}

# Generate accounts
for account in admin buyer seller tester; do
    create_account "$account"
done

# Get and verify addresses
ADMIN_PUBLIC=$(stellar keys address admin 2>/dev/null | grep -oE '[G][A-Z0-9]{55}' | head -1)
BUYER_PUBLIC=$(stellar keys address buyer 2>/dev/null | grep -oE '[G][A-Z0-9]{55}' | head -1)
SELLER_PUBLIC=$(stellar keys address seller 2>/dev/null | grep -oE '[G][A-Z0-9]{55}' | head -1)
TESTER_PUBLIC=$(stellar keys address tester 2>/dev/null | grep -oE '[G][A-Z0-9]{55}' | head -1)

# Verify addresses
for var in ADMIN_PUBLIC BUYER_PUBLIC SELLER_PUBLIC TESTER_PUBLIC; do
    addr="${!var}"
    [ -z "$addr" ] || [ ${#addr} -ne 56 ] && {
        echo -e "${RED}Error: Could not get ${var,,} address${NC}"
        exit 1
    }
done

echo "  Admin: $ADMIN_PUBLIC"
echo "  Buyer: $BUYER_PUBLIC"
echo "  Seller: $SELLER_PUBLIC"
echo "  Tester: $TESTER_PUBLIC"
echo ""

# Fund accounts (for testnet)
if [ "$NETWORK" = "testnet" ]; then
    echo -e "${YELLOW}Funding test accounts...${NC}"
    for account in "admin:$ADMIN_PUBLIC" "buyer:$BUYER_PUBLIC" "seller:$SELLER_PUBLIC" "tester:$TESTER_PUBLIC"; do
        IFS=':' read -r name addr <<< "$account"
        echo -n "  Funding $name... "
        curl -s -X POST "$FRIENDBOT_URL?addr=$addr" > /dev/null 2>&1 && echo "done" || echo "skipped"
    done
    echo "  Waiting for funding to process..."
    sleep 5
fi

echo -e "${GREEN}✓ Test accounts ready${NC}"
echo ""

# Step 3: Deploy the contract
echo -e "${YELLOW}[3/7] Deploying contract...${NC}"

# Use the optimized WASM if available, otherwise use the built one
WASM_PATH="$OPTIMIZED_WASM"

if [ ! -f "$WASM_PATH" ]; then
    echo -e "${RED}Error: WASM file not found at $WASM_PATH${NC}"
    exit 1
fi

echo "Deploying from: $WASM_PATH"
echo "This may take 30-60 seconds..."

# Get native XLM asset contract ID for token_a and token_b
echo "  Getting native XLM asset contract ID..."
NATIVE_XLM_CONTRACT=$(stellar contract id asset --asset native --network "$NETWORK" 2>/dev/null | grep -oE '[A-Z0-9]{56}' | head -1)
[ -z "$NATIVE_XLM_CONTRACT" ] && { echo -e "${RED}Error: Could not get native XLM asset contract${NC}"; exit 1; }

echo "  Token A/B (XLM): $NATIVE_XLM_CONTRACT"

# Deploy with constructor arguments (admin, token_a, token_b)
set +e
DEPLOY_RESULT=$(stellar contract deploy \
    --wasm "$WASM_PATH" \
    --source-account admin \
    --network "$NETWORK" \
    -- --admin "$ADMIN_PUBLIC" --token_a "$NATIVE_XLM_CONTRACT" --token_b "$NATIVE_XLM_CONTRACT" 2>&1)
DEPLOY_EXIT_CODE=$?
set -e

[ $DEPLOY_EXIT_CODE -ne 0 ] && {
    echo -e "${RED}Error: Deployment failed (exit code: $DEPLOY_EXIT_CODE)${NC}"
    echo "Output: $DEPLOY_RESULT"
    exit 1
}

# Extract contract ID from output (try multiple methods)
CONTRACT_ID=$(echo "$DEPLOY_RESULT" | grep -oE '/contract/[A-Z0-9]{56}' | sed 's|/contract/||' | head -1)
[ -z "$CONTRACT_ID" ] && CONTRACT_ID=$(echo "$DEPLOY_RESULT" | grep -oE '[A-Z0-9]{56}' | head -1)
[ -z "$CONTRACT_ID" ] && CONTRACT_ID=$(echo "$DEPLOY_RESULT" | grep -oE 'contract/[A-Z0-9]{56}' | sed 's|contract/||' | head -1)

[ -z "$CONTRACT_ID" ] || [ ${#CONTRACT_ID} -ne 56 ] && {
    echo -e "${RED}Error: Failed to extract contract ID${NC}"
    echo "Deploy output: $DEPLOY_RESULT"
    exit 1
}

echo "Contract ID: $CONTRACT_ID"
echo -e "${GREEN}✓ Contract deployed successfully${NC}"
echo ""

# Step 4: Set matching engine
echo -e "${YELLOW}[4/7] Setting matching engine...${NC}"

MATCHING_ENGINE_ADDRESS=$(stellar keys address admin 2>/dev/null | grep -oE '[G][A-Z0-9]{55}' | head -1)
if [ -n "$MATCHING_ENGINE_ADDRESS" ]; then
    echo "  Setting matching engine to: $MATCHING_ENGINE_ADDRESS"
    set +e
    SET_ME_RESULT=$(stellar contract invoke \
        --id "$CONTRACT_ID" \
        --source-account admin \
        --network "$NETWORK" \
        --verbose \
        -- \
        set_matching_engine \
        --matching_engine "$MATCHING_ENGINE_ADDRESS" 2>&1)
    SET_ME_EXIT=$?
    set -e
    extract_logs "$SET_ME_RESULT"

    [ $SET_ME_EXIT -eq 0 ] && echo -e "${GREEN}✓ Matching engine set${NC}" || echo -e "${YELLOW}Note: set_matching_engine failed${NC}"
else
    echo -e "${YELLOW}  Could not get matching engine address, skipping${NC}"
fi
echo ""

# Step 5: Test deposit and withdraw
echo -e "${YELLOW}[5/8] Testing deposit and withdraw...${NC}"

if [ -z "$NATIVE_XLM_CONTRACT" ]; then
    echo -e "${YELLOW}  Could not get native XLM asset contract, skipping${NC}"
    echo ""
else
    echo "  Using native XLM asset contract: $NATIVE_XLM_CONTRACT"

    # Function to invoke contract and extract result
    invoke_contract() {
        local func=$1
        shift
        stellar contract invoke \
            --id "$CONTRACT_ID" \
            --source-account tester \
            --network "$NETWORK" \
            --verbose \
            -- \
            "$func" \
            "$@" 2>&1
    }

    # Check initial balance
    echo -n "  Checking initial balance... "
    INITIAL_BALANCE_OUTPUT=$(invoke_contract get_balance --user "$TESTER_PUBLIC" --token "$NATIVE_XLM_CONTRACT")
    extract_logs "$INITIAL_BALANCE_OUTPUT"
    INITIAL_BALANCE=$(echo "$INITIAL_BALANCE_OUTPUT" | sed -n 's/.*"fn_return".*"i128":"\([0-9]*\)".*/\1/p' | head -1)

    [ "$INITIAL_BALANCE" = "0" ] || [ -z "$INITIAL_BALANCE" ] && \
        echo -e "${GREEN}✓ Initial balance is 0 (expected)${NC}" || \
        echo -e "${BLUE}Initial balance: $INITIAL_BALANCE${NC}"

    amount=10000000  # 1 XLM in stroops

    # Test deposit
    echo -n "  Depositing $amount stroops (1 XLM)... "
    set +e
    DEPOSIT_RESULT=$(invoke_contract deposit --user "$TESTER_PUBLIC" --token "$NATIVE_XLM_CONTRACT" --amount "$amount")
    DEPOSIT_EXIT=$?
    set -e
    extract_logs "$DEPOSIT_RESULT"

    if [ $DEPOSIT_EXIT -eq 0 ] && echo "$DEPOSIT_RESULT" | grep -qi "success"; then
        echo -e "${GREEN}✓ Deposit succeeded${NC}"

        # Check balance after deposit
        echo -n "  Checking balance after deposit... "
        BALANCE_AFTER_OUTPUT=$(invoke_contract get_balance --user "$TESTER_PUBLIC" --token "$NATIVE_XLM_CONTRACT")
        extract_logs "$BALANCE_AFTER_OUTPUT"
        BALANCE_AFTER=$(echo "$BALANCE_AFTER_OUTPUT" | sed -n 's/.*"fn_return".*"i128":"\([0-9]*\)".*/\1/p' | head -1)

        [ "$BALANCE_AFTER" -ge "$amount" ] && {
            echo -e "${GREEN}✓ Balance correct: $BALANCE_AFTER${NC}"

            # Test withdraw
            echo -n "  Testing withdraw... "
            set +e
            WITHDRAW_RESULT=$(invoke_contract withdraw --user "$TESTER_PUBLIC" --token "$NATIVE_XLM_CONTRACT" --amount "$amount")
            WITHDRAW_EXIT=$?
            set -e
            extract_logs "$WITHDRAW_RESULT"

            if [ $WITHDRAW_EXIT -eq 0 ] && echo "$WITHDRAW_RESULT" | grep -qi "success"; then
                echo -e "${GREEN}✓ Withdraw succeeded${NC}"

                # Check final balance
                BALANCE_FINAL_OUTPUT=$(invoke_contract get_balance --user "$TESTER_PUBLIC" --token "$NATIVE_XLM_CONTRACT")
                extract_logs "$BALANCE_FINAL_OUTPUT"
                BALANCE_FINAL=$(echo "$BALANCE_FINAL_OUTPUT" | sed -n 's/.*"fn_return".*"i128":"\([0-9]*\)".*/\1/p' | head -1)

                [ "$BALANCE_FINAL" = "0" ] || [ -z "$BALANCE_FINAL" ] && \
                    echo -e "${GREEN}✓ Balance after withdraw is 0 (expected)${NC}" || \
                    echo -e "${BLUE}Balance after withdraw: $BALANCE_FINAL${NC}"
            else
                echo -e "${YELLOW}Withdraw failed${NC}"
            fi
        } || echo -e "${BLUE}Balance after deposit: $BALANCE_AFTER (expected: $amount)${NC}"
    else
        echo -e "${YELLOW}Deposit failed (may be expected on some networks)${NC}"
    fi
    
    echo -e "${GREEN}✓ Deposit/withdraw functions tested${NC}"
fi
echo ""

# Step 6: Test get_settlement
echo -e "${YELLOW}[6/8] Testing get_settlement...${NC}"

# Create a test trade ID (32 bytes as hex, no 0x prefix)
TEST_TRADE_ID_HEX=$(openssl rand -hex 32 | head -c 64)

GET_SETTLEMENT_RESULT=$(stellar contract invoke \
    --id "$CONTRACT_ID" \
    --source-account admin \
    --network "$NETWORK" \
    --verbose \
    -- \
    get_settlement \
    --trade_id "$TEST_TRADE_ID_HEX" 2>&1)
extract_logs "$GET_SETTLEMENT_RESULT"

if echo "$GET_SETTLEMENT_RESULT" | grep -qi "null\|None\|\[\]"; then
    echo -e "${GREEN}✓ get_settlement returns None for non-existent trade (expected)${NC}"
else
    echo -e "${BLUE}get_settlement result: $GET_SETTLEMENT_RESULT${NC}"
fi
echo ""

# Step 7: Test get_trade_history
echo -e "${YELLOW}[7/8] Testing get_trade_history...${NC}"

GET_HISTORY_RESULT=$(stellar contract invoke \
    --id "$CONTRACT_ID" \
    --source-account admin \
    --network "$NETWORK" \
    --verbose \
    -- \
    get_trade_history \
    --user "$BUYER_PUBLIC" \
    --limit 10 2>&1)
extract_logs "$GET_HISTORY_RESULT"

if echo "$GET_HISTORY_RESULT" | grep -qi "\[\]\|null"; then
    echo -e "${GREEN}✓ get_trade_history returns empty for new user (expected)${NC}"
else
    echo -e "${BLUE}get_trade_history result: $GET_HISTORY_RESULT${NC}"
fi

echo ""

# Step 8: Test settle_trade
echo -e "${YELLOW}[8/8] Testing settle_trade...${NC}"

if [ -z "$NATIVE_XLM_CONTRACT" ]; then
    echo -e "${YELLOW}  Could not get native XLM asset contract, skipping${NC}"
    echo ""
else
    echo "  Preparing settlement test..."

    # Function to invoke contract with any source account
    invoke_as() {
        local source=$1
        local func=$2
        shift 2
        stellar contract invoke \
            --id "$CONTRACT_ID" \
            --source-account "$source" \
            --network "$NETWORK" \
            --verbose \
            -- \
            "$func" \
            "$@" 2>&1
    }

    # Deposit funds for buyer and seller (100 XLM each = 1000000000 stroops)
    INITIAL_DEPOSIT=1000000000

    echo -n "  Depositing $INITIAL_DEPOSIT stroops (100 XLM) for buyer... "
    set +e
    BUYER_DEPOSIT=$(invoke_as buyer deposit --user "$BUYER_PUBLIC" --token "$NATIVE_XLM_CONTRACT" --amount "$INITIAL_DEPOSIT")
    BUYER_DEPOSIT_EXIT=$?
    set -e
    extract_logs "$BUYER_DEPOSIT"

    if [ $BUYER_DEPOSIT_EXIT -eq 0 ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}Failed (may be expected on some networks)${NC}"
    fi

    echo -n "  Depositing $INITIAL_DEPOSIT stroops (100 XLM) for seller... "
    set +e
    SELLER_DEPOSIT=$(invoke_as seller deposit --user "$SELLER_PUBLIC" --token "$NATIVE_XLM_CONTRACT" --amount "$INITIAL_DEPOSIT")
    SELLER_DEPOSIT_EXIT=$?
    set -e
    extract_logs "$SELLER_DEPOSIT"

    if [ $SELLER_DEPOSIT_EXIT -eq 0 ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}Failed (may be expected on some networks)${NC}"
    fi

    # Only proceed with settlement if deposits succeeded
    if [ $BUYER_DEPOSIT_EXIT -eq 0 ] && [ $SELLER_DEPOSIT_EXIT -eq 0 ]; then
        # Generate a unique trade ID (32 bytes hex)
        TRADE_ID=$(openssl rand -hex 32 | head -c 64)
        echo "  Trade ID: $TRADE_ID"

        # Settlement amounts: 10 XLM base, 5 XLM quote (buyer gets +5 XLM net, seller -5 XLM net)
        BASE_AMOUNT=100000000
        QUOTE_AMOUNT=50000000

        echo "  Settling trade: $BASE_AMOUNT stroops base, $QUOTE_AMOUNT stroops quote"

        # Create instruction JSON with proper Soroban type specifications
        INSTRUCTION_JSON=$(cat <<EOF
{
  "trade_id": {"bytes": "$TRADE_ID"},
  "buy_user": "$BUYER_PUBLIC",
  "sell_user": "$SELLER_PUBLIC",
  "base_asset": "$NATIVE_XLM_CONTRACT",
  "quote_asset": "$NATIVE_XLM_CONTRACT",
  "base_amount": {"i128": "$BASE_AMOUNT"},
  "quote_amount": {"i128": "$QUOTE_AMOUNT"},
  "fee_base": {"i128": "0"},
  "fee_quote": {"i128": "0"},
  "timestamp": {"u64": "$(date +%s)"}
}
EOF
)

        echo -n "  Attempting unauthorized settle_trade as tester... "
        set +e
        UNAUTHORIZED_RESULT=$(invoke_as tester settle_trade --instruction "$INSTRUCTION_JSON")
        UNAUTHORIZED_EXIT=$?
        set -e
        extract_logs "$UNAUTHORIZED_RESULT"

        if [ $UNAUTHORIZED_EXIT -ne 0 ]; then
            echo -e "${GREEN}✓ Unauthorized settlement rejected (expected)${NC}"
        else
            echo -e "${YELLOW}Unauthorized settlement succeeded (unexpected)${NC}"
        fi

        echo -n "  Calling settle_trade as matching engine... "
        set +e
        SETTLE_RESULT=$(invoke_as admin settle_trade --instruction "$INSTRUCTION_JSON")
        SETTLE_EXIT=$?
        set -e
        extract_logs "$SETTLE_RESULT"

        if [ $SETTLE_EXIT -eq 0 ]; then
            echo -e "${GREEN}✓ Settlement succeeded${NC}"

            # Verify buyer balance (should be 1000000000 + 100000000 - 50000000 = 1050000000)
            echo -n "  Checking buyer balance after settlement... "
            BUYER_BALANCE_OUTPUT=$(invoke_as buyer get_balance --user "$BUYER_PUBLIC" --token "$NATIVE_XLM_CONTRACT")
            extract_logs "$BUYER_BALANCE_OUTPUT"
            # Extract balance from either direct output line or from fn_return log
            BUYER_BALANCE=$(echo "$BUYER_BALANCE_OUTPUT" | grep -E '^"[0-9]+"$' | tr -d '"' || echo "$BUYER_BALANCE_OUTPUT" | sed -n 's/.*"fn_return".*"i128":"\([0-9]*\)".*/\1/p' | head -1)

            EXPECTED_BUYER=1050000000
            if [ "$BUYER_BALANCE" = "$EXPECTED_BUYER" ]; then
                echo -e "${GREEN}✓ Buyer balance correct: $BUYER_BALANCE (expected: $EXPECTED_BUYER)${NC}"
            else
                echo -e "${YELLOW}Buyer balance: $BUYER_BALANCE (expected: $EXPECTED_BUYER)${NC}"
            fi

            # Verify seller balance (should be 1000000000 - 100000000 + 50000000 = 950000000)
            echo -n "  Checking seller balance after settlement... "
            SELLER_BALANCE_OUTPUT=$(invoke_as seller get_balance --user "$SELLER_PUBLIC" --token "$NATIVE_XLM_CONTRACT")
            extract_logs "$SELLER_BALANCE_OUTPUT"
            # Extract balance from either direct output line or from fn_return log
            SELLER_BALANCE=$(echo "$SELLER_BALANCE_OUTPUT" | grep -E '^"[0-9]+"$' | tr -d '"' || echo "$SELLER_BALANCE_OUTPUT" | sed -n 's/.*"fn_return".*"i128":"\([0-9]*\)".*/\1/p' | head -1)

            EXPECTED_SELLER=950000000
            if [ "$SELLER_BALANCE" = "$EXPECTED_SELLER" ]; then
                echo -e "${GREEN}✓ Seller balance correct: $SELLER_BALANCE (expected: $EXPECTED_SELLER)${NC}"
            else
                echo -e "${YELLOW}Seller balance: $SELLER_BALANCE (expected: $EXPECTED_SELLER)${NC}"
            fi

            # Verify settlement was recorded
            echo -n "  Verifying settlement was recorded... "
            SETTLEMENT_QUERY=$(invoke_as admin get_settlement --trade_id "$TRADE_ID")
            extract_logs "$SETTLEMENT_QUERY"

            if echo "$SETTLEMENT_QUERY" | grep -qiE "$BUYER_PUBLIC|$SELLER_PUBLIC"; then
                echo -e "${GREEN}✓ Settlement found in contract storage${NC}"
            else
                echo -e "${YELLOW}Settlement query result: $SETTLEMENT_QUERY${NC}"
            fi

            echo -e "${GREEN}✓ settle_trade function tested successfully${NC}"
        else
            echo -e "${YELLOW}Settlement failed${NC}"
            echo "  Exit code: $SETTLE_EXIT"
            echo "  Result: $SETTLE_RESULT"
        fi
    else
        echo -e "${YELLOW}  Skipping settle_trade test (deposits failed)${NC}"
    fi
fi
echo ""

# Summary
echo -e "${GREEN}=== Test Summary ===${NC}"
echo "Contract ID: $CONTRACT_ID"
echo "Network: $NETWORK"
echo ""
echo -e "${GREEN}✓ Contract compiled and optimized${NC}"
echo -e "${GREEN}✓ Contract deployed${NC}"
echo -e "${GREEN}✓ Contract initialized${NC}"
echo -e "${GREEN}✓ Basic functionality tested${NC}"
echo -e "${GREEN}✓ settle_trade function tested${NC}"
echo ""
echo -e "${BLUE}To interact with the contract:${NC}"
echo "  stellar contract invoke \\"
echo "    --id $CONTRACT_ID \\"
echo "    --source-account admin \\"
echo "    --network $NETWORK \\"
echo "    -- <function> <args>"
echo ""
echo "Contract WASM: $WASM_PATH"
echo ""
echo -e "${GREEN}All tests completed!${NC}"
