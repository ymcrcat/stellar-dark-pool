#!/bin/bash

# End-to-End Test for Stellar Dark Pool (Python Matching Engine)
# Network: TESTNET
#
# This script performs a complete end-to-end test of the dark pool system on Stellar testnet:
# 1. Deploys tokens (Base/Quote)
# 2. Builds and deploys the settlement contract (configured with tokens)
# 3. Generates matching engine keypair
# 4. Creates and funds test user accounts
# 5. Starts matching engine (Python)
# 6. Submits matching orders
# 7. Submits settlement transaction via Soroban RPC (handled by matching engine)
# 8. Verifies transaction on-chain

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
export STELLAR_NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
export SOROBAN_RPC_URL="https://soroban-testnet.stellar.org"
REST_PORT=${REST_PORT:-8080}
BASE_URL="http://localhost:${REST_PORT}"
MATCHING_ENGINE_PID=""
ROOT_DIR="$(pwd)"

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    
    # Stop matching engine
    if [ ! -z "$MATCHING_ENGINE_PID" ]; then
        echo "Stopping matching engine (PID: $MATCHING_ENGINE_PID)"
        kill $MATCHING_ENGINE_PID 2>/dev/null || true
        wait $MATCHING_ENGINE_PID 2>/dev/null || true
    fi
    pkill -f "src.main" 2>/dev/null || true
    
    echo -e "${GREEN}Cleanup complete${NC}"
}

trap cleanup EXIT INT TERM

# Print functions
print_step() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Setup Python Environment
setup_python() {
    print_step "Setting up Python Environment"

    command -v python3 &> /dev/null || { print_error "python3 not found"; exit 1; }

    # Create/activate venv in matching-engine directory
    cd matching-engine
    [ ! -d "venv" ] && { print_info "Creating virtual environment..."; python3 -m venv venv; }

    source venv/bin/activate
    print_info "Installing dependencies..."
    pip install -q -r requirements.txt

    print_success "Python environment ready"
    cd ..
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking Prerequisites"

    local missing_tools=()
    for tool in stellar curl jq; do
        command -v $tool &> /dev/null || missing_tools+=("$tool")
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing tools: ${missing_tools[*]}"
        exit 1
    fi

    print_success "All required prerequisites met"
}

# Step 1: Get Token Contracts
deploy_tokens() {
    print_step "Step 1: Getting Token Contracts"

    # For this E2E test, we use XLM for both Base and Quote assets
    local xlm_token=$(stellar contract id asset --asset native --network testnet)
    print_info "XLM Token ID: $xlm_token"

    export BASE_TOKEN_ID="$xlm_token"
    export QUOTE_TOKEN_ID="$xlm_token"
}

# Step 2: Build and deploy contract
deploy_contract() {
    print_step "Step 2: Building and Deploying Settlement Contract"

    cd contracts/settlement

    print_info "Building contract..."
    stellar contract build --profile release-with-logs --optimize > /tmp/contract-build.log 2>&1 || {
        print_error "Contract build failed."
        exit 1
    }

    # Find WASM file
    local wasm_paths=(
        "$ROOT_DIR/target/wasm32v1-none/release-with-logs/settlement.wasm"
        "$ROOT_DIR/target/wasm32-unknown-unknown/release/settlement.wasm"
    )
    local wasm_file=""
    for path in "${wasm_paths[@]}"; do
        [ -f "$path" ] && { wasm_file="$path"; break; }
    done

    [ -z "$wasm_file" ] && { print_error "WASM file not found"; exit 1; }

    print_info "Deploying contract to testnet..."

    # Ensure 'test' identity exists and is funded
    stellar keys ls 2>/dev/null | grep -q "^test" || stellar keys generate test 2>/dev/null || true
    local deployer=$(stellar keys address test)
    print_info "Funding deployer: $deployer"
    curl -s "https://friendbot.stellar.org/?addr=${deployer}" > /dev/null 2>&1 || true
    sleep 3

    # Deploy contract
    local deploy_output
    set +e
    deploy_output=$(stellar contract deploy \
        --wasm "$wasm_file" \
        --source test \
        --network testnet \
        -- --admin "$deployer" --token_a "$BASE_TOKEN_ID" --token_b "$QUOTE_TOKEN_ID" 2>&1)
    set -e

    CONTRACT_ID=$(echo "$deploy_output" | grep -oE '[A-Z0-9]{56}' | head -1)
    [ -z "$CONTRACT_ID" ] && { print_error "Deployment failed: $deploy_output"; exit 1; }

    print_success "Contract deployed: $CONTRACT_ID"
    cd "$ROOT_DIR"
}

# Step 3: Generate matching engine keypair
generate_matching_engine_keypair() {
    print_step "Step 3: Generating Matching Engine Keypair"

    stellar keys rm matching_engine_key 2>/dev/null || true
    stellar keys generate matching_engine_key --fund

    MATCHING_ENGINE_PUBLIC=$(stellar keys address matching_engine_key)
    print_info "Public Key: $MATCHING_ENGINE_PUBLIC"
    print_info "Waiting for funding..."
    sleep 5
}

# Step 4: Create test user accounts
create_test_accounts() {
    print_step "Step 4: Creating Test User Accounts"

    # Remove existing keys and create new ones
    for user in e2e_user1 e2e_user2; do
        stellar keys rm $user 2>/dev/null || true
        stellar keys generate $user --fund
    done

    USER1_PUBLIC=$(stellar keys address e2e_user1)
    USER1_SECRET=$(stellar keys show e2e_user1)
    USER2_PUBLIC=$(stellar keys address e2e_user2)
    USER2_SECRET=$(stellar keys show e2e_user2)

    print_info "User1: $USER1_PUBLIC"
    print_info "User2: $USER2_PUBLIC"
    print_info "Waiting for funding..."
    sleep 5
}

# Step 5: Register matching engine in contract
register_matching_engine() {
    print_step "Step 5: Registering Matching Engine in Contract"
    
    print_info "Invoking set_matching_engine..."
    stellar contract invoke \
        --id "$CONTRACT_ID" \
        --source test \
        --network testnet \
        -- \
        set_matching_engine \
        --matching_engine "$MATCHING_ENGINE_PUBLIC"
    
    print_success "Matching engine registered"
}

# Step 6: Start matching engine
start_matching_engine() {
    print_step "Step 6: Starting Matching Engine"

    cd matching-engine

    export SETTLEMENT_CONTRACT_ID="$CONTRACT_ID"
    export MATCHING_ENGINE_KEY_ALIAS="matching_engine_key"
    export REST_PORT="$REST_PORT"

    python3 -m src.main > /tmp/matching-engine-full.log 2>&1 &
    MATCHING_ENGINE_PID=$!

    # Wait for ready (30 second timeout)
    for i in {1..30}; do
        curl -s -f "${BASE_URL}/health" > /dev/null 2>&1 && {
            print_success "Matching engine is ready"
            cd ..
            return
        }
        sleep 1
    done

    print_error "Failed to start matching engine"
    cat /tmp/matching-engine-full.log
    exit 1
}

# Step 7: Deposit funds
deposit_funds() {
    print_step "Step 7: Depositing Funds"

    local amount=1000000000  # 100 XLM in stroops

    for user_key in "e2e_user1:$USER1_PUBLIC:$QUOTE_TOKEN_ID" "e2e_user2:$USER2_PUBLIC:$BASE_TOKEN_ID"; do
        IFS=':' read -r key addr token <<< "$user_key"
        print_info "Depositing for $key..."
        stellar contract invoke \
            --id "$CONTRACT_ID" \
            --source "$key" \
            --network testnet \
            -- \
            deposit --user "$addr" --token "$token" --amount "$amount"
    done

    print_success "Deposits complete"
}

# Step 8: Submit orders
submit_orders() {
    print_step "Step 8: Submitting Orders"

    local ts=$(date +%s)
    local order_template='{"order_id":"%s","user_address":"%s","asset_pair":{"base":"XLM","quote":"XLM"},"side":"%s","order_type":"Limit","price":1.0,"quantity":10,"time_in_force":"GTC","timestamp":%d}'

    # Buy Order
    local buy_json=$(printf "$order_template" "order-1" "$USER1_PUBLIC" "Buy" "$ts")
    BUY_SIG=$(python3 scripts/sign_order.py "$USER1_SECRET" "$buy_json")
    local buy_req="${buy_json%\}},\"signature\":\"$BUY_SIG\"}"

    print_info "Submitting buy order..."
    curl -s -X POST -H "Content-Type: application/json" -d "$buy_req" "${BASE_URL}/api/v1/orders" | jq .

    # Sell Order
    local sell_json=$(printf "$order_template" "order-2" "$USER2_PUBLIC" "Sell" "$ts")
    SELL_SIG=$(python3 scripts/sign_order.py "$USER2_SECRET" "$sell_json")
    local sell_req="${sell_json%\}},\"signature\":\"$SELL_SIG\"}"

    print_info "Submitting sell order..."
    local sell_resp=$(curl -s -X POST -H "Content-Type: application/json" -d "$sell_req" "${BASE_URL}/api/v1/orders")
    echo "$sell_resp" | jq .

    TRADE_ID=$(echo "$sell_resp" | jq -r '.trades[0].trade_id')
    print_success "Matched Trade ID: $TRADE_ID"
}

# Step 9: Settlement
submit_settlement() {
    print_step "Step 9: Submitting Settlement"

    # Build settlement instruction
    # Using unequal amounts to demonstrate visible balance changes
    local settlement_req=$(cat <<EOF
{
  "trade_id": "$TRADE_ID",
  "buy_user": "$USER1_PUBLIC",
  "sell_user": "$USER2_PUBLIC",
  "base_asset": "XLM",
  "quote_asset": "XLM",
  "base_amount": 100000000,
  "quote_amount": 50000000,
  "fee_base": 0,
  "fee_quote": 0,
  "timestamp": $(date +%s),
  "buy_order_signature": "$BUY_SIG",
  "sell_order_signature": "$SELL_SIG"
}
EOF
)

    print_info "Submitting settlement..."
    local settle_resp=$(curl -s -X POST -H "Content-Type: application/json" -d "$settlement_req" "${BASE_URL}/api/v1/settlement/submit")
    echo "$settle_resp" | jq .

    local tx_hash=$(echo "$settle_resp" | jq -r '.transaction_hash // empty')
    [ -z "$tx_hash" ] && { print_error "Settlement failed"; exit 1; }

    print_success "Settlement successful! TX: $tx_hash"
}

# Step 10: Verify balances after settlement
verify_balances() {
    print_step "Step 10: Verifying Balances After Settlement"

    # Check buyer balance (should be 1050000000 = 105 XLM)
    print_info "Checking buyer balance..."
    local buyer_balance=$(stellar contract invoke \
        --id "$CONTRACT_ID" \
        --source e2e_user1 \
        --network testnet \
        -- get_balance \
        --user "$USER1_PUBLIC" \
        --token "$BASE_TOKEN_ID" 2>&1 | grep -o '"[0-9]*"' | tr -d '"')

    print_info "Buyer balance: $buyer_balance (expected: 1050000000)"

    # Check seller balance (should be 950000000 = 95 XLM)
    print_info "Checking seller balance..."
    local seller_balance=$(stellar contract invoke \
        --id "$CONTRACT_ID" \
        --source e2e_user2 \
        --network testnet \
        -- get_balance \
        --user "$USER2_PUBLIC" \
        --token "$BASE_TOKEN_ID" 2>&1 | grep -o '"[0-9]*"' | tr -d '"')

    print_info "Seller balance: $seller_balance (expected: 950000000)"

    # Verify balances are correct
    if [ "$buyer_balance" = "1050000000" ] && [ "$seller_balance" = "950000000" ]; then
        print_success "Balance verification passed!"
    else
        print_error "Balance verification failed!"
        print_error "Expected: Buyer=1050000000, Seller=950000000"
        print_error "Got: Buyer=$buyer_balance, Seller=$seller_balance"
        exit 1
    fi
}

# Main
main() {
    setup_python
    check_prerequisites
    deploy_tokens
    deploy_contract
    generate_matching_engine_keypair
    create_test_accounts
    register_matching_engine
    start_matching_engine
    deposit_funds
    submit_orders
    submit_settlement
    verify_balances

    print_step "Full E2E Test Completed Successfully"
}

main