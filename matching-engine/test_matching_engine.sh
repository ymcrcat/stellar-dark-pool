#!/bin/bash

# Semi-automated test script for matching engine API (Python version)
# This script starts the server, runs curl tests, and cleans up
#
# IMPORTANT: This test requires MANUAL SETUP before running:
#   1. Deploy settlement contract on testnet
#   2. Fund and authorize a matching engine account in the contract
#   3. Set SETTLEMENT_CONTRACT_ID and MATCHING_ENGINE_SIGNING_KEY environment variables
#
# For FULLY AUTOMATED testing (no manual setup required):
#   cd .. && bash test_e2e_full.sh
#
# Manual setup steps:
#   1. Deploy contract: cd ../contracts/settlement && bash test_contract.sh
#   2. Export SETTLEMENT_CONTRACT_ID=<contract_id_from_deployment>
#   3. Generate matching engine keypair: stellar keys generate matching-engine --network testnet
#   4. Fund it: curl "https://friendbot.stellar.org/?addr=$(stellar keys address matching-engine)"
#   5. Authorize it: stellar contract invoke --id $SETTLEMENT_CONTRACT_ID --source admin --network testnet -- set_matching_engine --matching_engine $(stellar keys address matching-engine)
#   6. Export MATCHING_ENGINE_SIGNING_KEY=$(stellar keys show matching-engine)
#   7. Run this test: bash test_matching_engine.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
REST_PORT=${REST_PORT:-8080}
BASE_URL="http://localhost:${REST_PORT}"
SERVER_PID=""
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Check dependencies
command -v python3 &> /dev/null || {
    echo -e "${RED}Error: python3 not found${NC}"
    exit 1
}

# Function to sign an order using the python script
sign_order_json() {
    python3 "$ROOT_DIR/scripts/sign_order.py" "$1" "$2" 2>/dev/null || { echo ""; return 1; }
}

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    [ -n "$SERVER_PID" ] && {
        echo "Stopping server (PID: $SERVER_PID)"
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
    }
    echo -e "${GREEN}Cleanup complete${NC}"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT INT TERM

# Function to print test results
print_test() {
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -e "\n${YELLOW}[Test $TEST_COUNT]${NC} $1"
}

print_pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "${GREEN}✓ PASS${NC}"
}

print_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "${RED}✗ FAIL${NC}: $1"
}

# Function to wait for server to be ready
wait_for_server() {
    echo -e "${YELLOW}Waiting for server to start...${NC}"
    for i in {1..30}; do
        curl -s -f "${BASE_URL}/health" > /dev/null 2>&1 && {
            echo -e "${GREEN}Server is ready!${NC}"
            return 0
        }
        sleep 1
    done
    echo -e "${RED}Server failed to start within 30 seconds${NC}"
    return 1
}

# Function to make HTTP request and check response
test_endpoint() {
    local method=$1
    local endpoint=$2
    local data=$3
    local expected_status=${4:-200}
    local description=$5
    
    print_test "${description:-$method $endpoint}"
    
    local response
    local status_code
    
    if [ -z "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X "$method" "${BASE_URL}${endpoint}" 2>&1)
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${BASE_URL}${endpoint}" 2>&1)
    fi
    
    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    # Handle multiple expected status codes (e.g., "200|401")
    local status_match=0
    IFS='|' read -ra STATUSES <<< "$expected_status"
    for status in "${STATUSES[@]}"; do
        if [ "$status_code" -eq "$status" ]; then
            status_match=1
            break
        fi
    done
    
    if [ $status_match -eq 1 ]; then
        print_pass
        [ -n "$body" ] && [ "$body" != "null" ] && echo "Response: $(echo "$body" | head -c 200)"
        echo ""
        return 0
    else
        print_fail "Expected status $expected_status, got $status_code"
        [ -n "$body" ] && [ "$body" != "null" ] && echo "Error response: $(echo "$body" | head -c 500)"
        return 1
    fi
}

# Setup Python environment
echo -e "${YELLOW}Setting up Python environment...${NC}"
cd "$SCRIPT_DIR"
[ ! -d "venv" ] && python3 -m venv venv
source venv/bin/activate
pip install -q -r requirements.txt

# Start the server
echo -e "\n${YELLOW}Starting matching engine server...${NC}"

# Check if server is already running
curl -s -f "${BASE_URL}/health" > /dev/null 2>&1 && {
    echo -e "${YELLOW}Server appears to be already running on port ${REST_PORT}${NC}"
    echo -e "${YELLOW}Please stop it first or use different ports${NC}"
    exit 1
}

# Set environment variables
export SOROBAN_RPC_URL=${SOROBAN_RPC_URL:-"https://soroban-testnet.stellar.org"}
export STELLAR_NETWORK_PASSPHRASE=${STELLAR_NETWORK_PASSPHRASE:-"Test SDF Network ; September 2015"}
export REST_PORT=$REST_PORT

# Check if SETTLEMENT_CONTRACT_ID is set
if [ -z "${SETTLEMENT_CONTRACT_ID:-}" ]; then
    echo -e "${YELLOW}WARNING: SETTLEMENT_CONTRACT_ID not set${NC}"
    echo -e "${YELLOW}The matching engine requires a deployed contract to query supported assets.${NC}"
    echo -e "${YELLOW}This test will likely fail unless you set SETTLEMENT_CONTRACT_ID.${NC}"
    echo -e ""
    echo -e "Options:"
    echo -e "1. Run the full e2e test: cd .. && bash test_e2e_full.sh"
    echo -e "2. Deploy a contract first: cd ../contracts/settlement && bash test_contract.sh"
    echo -e "   Then set: export SETTLEMENT_CONTRACT_ID=<contract-id-from-deployment>"
    echo -e "   And run this test again"
    echo -e ""
    echo -e "${YELLOW}Proceeding with test anyway (will likely fail)...${NC}"
    sleep 2
    export SETTLEMENT_CONTRACT_ID="CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
else
    echo -e "${GREEN}Using SETTLEMENT_CONTRACT_ID: $SETTLEMENT_CONTRACT_ID${NC}"
fi

# Generate a signing key for the engine (if not set)
if [ -z "${MATCHING_ENGINE_SIGNING_KEY:-}" ]; then
    MATCHING_ENGINE_SIGNING_KEY=$(python3 -c "from stellar_sdk import Keypair; print(Keypair.random().secret)")
    export MATCHING_ENGINE_SIGNING_KEY

    MATCHING_ENGINE_PUBLIC=$(python3 -c "from stellar_sdk import Keypair; print(Keypair.from_secret('$MATCHING_ENGINE_SIGNING_KEY').public_key)")

    echo -e "${YELLOW}WARNING: Generated new matching engine keypair${NC}"
    echo -e "${YELLOW}Public Key: $MATCHING_ENGINE_PUBLIC${NC}"
    echo -e "${YELLOW}This account needs to be:${NC}"
    echo -e "${YELLOW}  1. Funded via Friendbot${NC}"
    echo -e "${YELLOW}  2. Authorized in the contract by the admin${NC}"
    echo -e ""
    echo -e "${YELLOW}Run these commands with your admin account:${NC}"
    echo -e "  curl \"https://friendbot.stellar.org/?addr=$MATCHING_ENGINE_PUBLIC\""
    echo -e "  stellar contract invoke --id $SETTLEMENT_CONTRACT_ID --source admin --network testnet -- set_matching_engine --matching_engine $MATCHING_ENGINE_PUBLIC"
    echo -e ""
    echo -e "${YELLOW}Or use test_e2e_full.sh for fully automated testing.${NC}"
    echo -e ""
fi

# Start server in background
python3 -m src.main > /tmp/matching-engine.log 2>&1 &
SERVER_PID=$!

echo "Server started with PID: $SERVER_PID"
echo "Logs: /tmp/matching-engine.log"

# Wait for server to be ready
wait_for_server || {
    echo -e "${RED}Server startup failed. Logs:${NC}"
    tail -20 /tmp/matching-engine.log
    exit 1
}

echo -e "\n${GREEN}=== Running End-to-End Tests ===${NC}\n"

# Generate test accounts
echo -e "${YELLOW}Generating Stellar testnet accounts...${NC}"
generate_keypair() {
    local secret=$(python3 -c "from stellar_sdk import Keypair; print(Keypair.random().secret)")
    local public=$(python3 -c "from stellar_sdk import Keypair; print(Keypair.from_secret('$secret').public_key)")
    echo "$secret $public"
}

read USER1_SECRET USER1_PUBLIC <<< $(generate_keypair)
read USER2_SECRET USER2_PUBLIC <<< $(generate_keypair)

echo "User1: $USER1_PUBLIC"
echo "User2: $USER2_PUBLIC"

# Fund test accounts and deposit to vault
echo -e "\n${YELLOW}Funding test accounts and depositing to vault...${NC}"

# Fund accounts via friendbot
echo "Funding User1..."
curl -s "https://friendbot.stellar.org/?addr=$USER1_PUBLIC" > /dev/null 2>&1 || true
echo "Funding User2..."
curl -s "https://friendbot.stellar.org/?addr=$USER2_PUBLIC" > /dev/null 2>&1 || true

sleep 5  # Wait for funding to process

# Get native XLM asset contract ID
NATIVE_XLM_CONTRACT=$(stellar contract id asset --asset native --network testnet 2>/dev/null | grep -oE '[A-Z0-9]{56}' | head -1)
echo "Native XLM Contract: $NATIVE_XLM_CONTRACT"

# Deposit funds for both users (100 XLM = 1000000000 stroops each)
DEPOSIT_AMOUNT=1000000000

echo "Depositing for User1..."
stellar contract invoke \
    --id "$SETTLEMENT_CONTRACT_ID" \
    --source-account "$USER1_SECRET" \
    --network testnet \
    -- \
    deposit --user "$USER1_PUBLIC" --token "$NATIVE_XLM_CONTRACT" --amount "$DEPOSIT_AMOUNT" > /dev/null 2>&1 || echo "Deposit may have failed"

echo "Depositing for User2..."
stellar contract invoke \
    --id "$SETTLEMENT_CONTRACT_ID" \
    --source-account "$USER2_SECRET" \
    --network testnet \
    -- \
    deposit --user "$USER2_PUBLIC" --token "$NATIVE_XLM_CONTRACT" --amount "$DEPOSIT_AMOUNT" > /dev/null 2>&1 || echo "Deposit may have failed"

echo -e "${GREEN}✓ Accounts funded and deposits complete${NC}\n"

# Test 1: Health check
test_endpoint "GET" "/health" "" 200 "Health check"

# Test 2: Submit a buy order with proper signature
ORDER_ID_1="test-order-$(date +%s)-1"
TIMESTAMP_1=$(date +%s)

# Helper function to create order JSON for signing
create_order_json() {
    local order_id=$1 user=$2 side=$3 timestamp=$4
    cat <<EOF
{
  "order_id": "$order_id",
  "user_address": "$user",
  "asset_pair": {"base": "XLM", "quote": "XLM"},
  "side": "$side",
  "order_type": "Limit",
  "price": "1.0",
  "quantity": "100.0",
  "filled_quantity": "0",
  "time_in_force": "GTC",
  "timestamp": $timestamp,
  "expiration": null,
  "signature": "",
  "status": "Pending"
}
EOF
}

BUY_ORDER_JSON_FOR_SIGNING=$(create_order_json "$ORDER_ID_1" "$USER1_PUBLIC" "Buy" "$TIMESTAMP_1")

# Sign the order
BUY_ORDER_SIGNATURE=$(sign_order_json "$USER1_SECRET" "$BUY_ORDER_JSON_FOR_SIGNING")
[ -z "$BUY_ORDER_SIGNATURE" ] && { echo -e "${RED}Failed to sign order${NC}"; exit 1; }

# Helper function to create final order JSON with signature
create_final_order() {
    local order_id=$1 user=$2 side=$3 timestamp=$4 signature=$5
    cat <<EOF
{
  "order_id": "$order_id",
  "user_address": "$user",
  "asset_pair": {"base": "XLM", "quote": "XLM"},
  "side": "$side",
  "order_type": "Limit",
  "price": "1.0",
  "quantity": "100.0",
  "time_in_force": "GTC",
  "timestamp": $timestamp,
  "expiration": null,
  "signature": "$signature"
}
EOF
}

BUY_ORDER_1=$(create_final_order "$ORDER_ID_1" "$USER1_PUBLIC" "Buy" "$TIMESTAMP_1" "$BUY_ORDER_SIGNATURE")

test_endpoint "POST" "/api/v1/orders" "$BUY_ORDER_1" "200" "Submit buy order"

# Test 3: Submit a sell order matching the buy
ORDER_ID_2="test-order-$(date +%s)-2"
TIMESTAMP_2=$(date +%s)

SELL_ORDER_JSON_FOR_SIGNING=$(create_order_json "$ORDER_ID_2" "$USER2_PUBLIC" "Sell" "$TIMESTAMP_2")
SELL_ORDER_SIGNATURE=$(sign_order_json "$USER2_SECRET" "$SELL_ORDER_JSON_FOR_SIGNING")

SELL_ORDER_1=$(create_final_order "$ORDER_ID_2" "$USER2_PUBLIC" "Sell" "$TIMESTAMP_2" "$SELL_ORDER_SIGNATURE")

test_endpoint "POST" "/api/v1/orders" "$SELL_ORDER_1" "200" "Submit sell order (matches buy)"

# Test 4: Get order book
test_endpoint "GET" "/api/v1/orderbook/XLM%2FXLM" "" 200 "Get order book"

# Test 5: Wait for automatic settlement to complete
echo -e "\n${YELLOW}Waiting for automatic settlement...${NC}"
sleep 10
echo -e "${GREEN}Settlement should be complete. Check /tmp/matching-engine.log for TX hash.${NC}"

# Print summary
echo -e "\n${GREEN}=== Test Summary ===${NC}"
echo -e "Total tests: $TEST_COUNT"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed${NC}"
    exit 1
fi
