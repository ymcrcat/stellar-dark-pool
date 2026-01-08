#!/bin/bash

# End-to-End Test for Stellar Dark Pool (Docker-based Matching Engine)
# Network: TESTNET
#
# This script performs a complete end-to-end test using Docker for the matching engine:
# 1. Deploys tokens (Base/Quote)
# 2. Builds and deploys the settlement contract (configured with tokens)
# 3. Creates and funds test user accounts
# 4. Starts matching engine in Docker container (auto-generates keypair)
# 5. Extracts and funds the Docker-generated keypair
# 6. Registers matching engine in contract
# 7. Submits matching orders
# 8. Submits settlement transaction via Soroban RPC (handled by matching engine)
# 9. Verifies transaction on-chain
#
# Requirements: Docker, docker-compose, stellar CLI, curl, jq
# Note: Matching engine keypair is ephemeral and regenerated on each container start

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
BASE_URL="${BASE_URL:-}"
CURL_OPTS="${CURL_OPTS:-}"
ROOT_DIR="$(pwd)"
DOCKER_COMPOSE_FILE="docker-compose.yml"

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    
    # Stop Docker container
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        echo "Stopping matching engine container..."
        docker-compose down -v 2>/dev/null || true
    fi
    
    # Remove .env file
    rm -f .env
    
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

# Determine whether the matching engine is serving HTTPS or HTTP.
configure_base_url() {
    if [ -n "$BASE_URL" ]; then
        if [[ "$BASE_URL" == https://* ]] && [ -z "$CURL_OPTS" ]; then
            CURL_OPTS="-k"
        fi
        return
    fi

    local host="localhost:${REST_PORT}"
    if curl -s -k -f "https://${host}/health" > /dev/null 2>&1; then
        BASE_URL="https://${host}"
        CURL_OPTS="-k"
    else
        BASE_URL="http://${host}"
        CURL_OPTS=""
    fi
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking Prerequisites"
    
    # Clean up any leftover containers from previous runs
    print_info "Cleaning up any leftover Docker containers..."
    docker-compose down -v 2>/dev/null || true
    rm -f .env

    local missing_tools=()
    for tool in docker stellar curl jq python3; do
        command -v $tool &> /dev/null || missing_tools+=("$tool")
    done
    
    # Check docker-compose separately (might be docker compose v2)
    if ! docker-compose version &> /dev/null && ! docker compose version &> /dev/null; then
        missing_tools+=("docker-compose")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Check if stellar-sdk is installed (needed for order signing script)
    if ! python3 -c "import stellar_sdk" 2>/dev/null; then
        print_info "stellar-sdk not found, installing from matching-engine requirements..."
        pip3 install -q stellar-sdk || {
            print_error "Failed to install stellar-sdk. Install manually with: pip3 install stellar-sdk"
            exit 1
        }
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

# Step 3: Prepare for Docker-generated matching engine keypair
generate_matching_engine_keypair() {
    print_step "Step 3: Preparing for Docker-Generated Matching Engine Keypair"
    
    print_info "Matching engine keypair will be auto-generated by Docker container"
    print_info "We'll extract it from container logs after startup"
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

# Step 4.5: Create Docker environment file
create_docker_env() {
    print_step "Step 4.5: Creating Docker Environment File"
    
    # Create .env file in root directory (where docker-compose is run from)
    cat > .env << EOF
STELLAR_NETWORK_PASSPHRASE=${STELLAR_NETWORK_PASSPHRASE}
SOROBAN_RPC_URL=${SOROBAN_RPC_URL}
SETTLEMENT_CONTRACT_ID=${CONTRACT_ID}
REST_PORT=${REST_PORT}
EOF

    # Ensure compose interpolation uses the freshly deployed contract
    export SETTLEMENT_CONTRACT_ID="${CONTRACT_ID}"
    export REST_PORT="${REST_PORT}"
    
    print_success "Docker environment file created"
}

# Step 5: Start matching engine in Docker
start_matching_engine() {
    print_step "Step 5: Starting Matching Engine (Docker)"

    print_info "Building and starting Docker container..."
    docker-compose up -d --build
    
    # Wait for container to be healthy
    print_info "Waiting for container to start..."
    sleep 5

    configure_base_url
    print_info "Using matching engine URL: ${BASE_URL}"

    # Verify the container picked up the correct settlement contract ID
    local logged_contract_id
    logged_contract_id=$(docker-compose logs matching-engine 2>/dev/null | grep "Settlement Contract ID:" | tail -1 | awk '{print $NF}')
    if [ -z "$logged_contract_id" ] || [ "$logged_contract_id" = "[NOT" ] || [ "$logged_contract_id" = "SET]" ]; then
        print_error "Matching engine did not receive SETTLEMENT_CONTRACT_ID"
        docker-compose logs matching-engine 2>&1 | head -50
        exit 1
    fi
    if [ -n "${CONTRACT_ID:-}" ] && [ "$logged_contract_id" != "$CONTRACT_ID" ]; then
        print_error "Matching engine is using a different settlement contract"
        print_error "Expected: $CONTRACT_ID"
        print_error "Got:      $logged_contract_id"
        docker-compose logs matching-engine 2>&1 | head -50
        exit 1
    fi
    
    # Extract public key from logs
    print_info "Extracting auto-generated public key from container logs..."
    MATCHING_ENGINE_PUBLIC=""
    for i in {1..10}; do
        MATCHING_ENGINE_PUBLIC=$(docker-compose logs matching-engine 2>/dev/null | grep "Public Key:" | tail -1 | awk '{print $NF}')
        if [ ! -z "$MATCHING_ENGINE_PUBLIC" ]; then
            break
        fi
        sleep 1
    done
    
    if [ -z "$MATCHING_ENGINE_PUBLIC" ]; then
        print_error "Failed to extract public key from container logs"
        docker-compose logs matching-engine
        exit 1
    fi
    
    print_success "Extracted public key: $MATCHING_ENGINE_PUBLIC"
    
    # Wait for health endpoint
    print_info "Waiting for matching engine to be ready..."
    for i in {1..30}; do
        curl $CURL_OPTS -s -f "${BASE_URL}/health" > /dev/null 2>&1 && {
            print_success "Matching engine is ready"
            return
        }
        sleep 1
    done

    print_error "Failed to start matching engine"
    docker-compose logs matching-engine
    exit 1
}

# Step 6: Fund the Docker-generated matching engine account
fund_matching_engine() {
    print_step "Step 6: Funding Docker-Generated Matching Engine Account"
    
    print_info "Funding matching engine account via Friendbot..."
    curl -s "https://friendbot.stellar.org/?addr=${MATCHING_ENGINE_PUBLIC}" > /dev/null 2>&1 || true
    
    print_info "Waiting for funding to complete..."
    sleep 5
    
    print_success "Matching engine account funded"
}

# Step 7: Register matching engine in contract
register_matching_engine() {
    print_step "Step 7: Registering Matching Engine in Contract"
    
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

# Step 8: Deposit funds
deposit_funds() {
    print_step "Step 8: Depositing Funds"

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
    
    # Wait and verify deposits are queryable on-chain
    print_info "Verifying deposits are queryable on-chain..."
    sleep 5
    
    # Poll until user1 balance is queryable (up to 30 seconds)
    local verified=false
    for i in {1..30}; do
        local user1_balance=$(stellar contract invoke \
            --id "$CONTRACT_ID" \
            --source e2e_user1 \
            --network testnet \
            -- get_balance \
            --user "$USER1_PUBLIC" \
            --token "$QUOTE_TOKEN_ID" 2>&1 | grep -o '"[0-9]*"' | tr -d '"' || echo "0")
        
        if [ "$user1_balance" = "1000000000" ]; then
            verified=true
            print_success "Deposits verified on-chain (User1: $user1_balance stroops)"
            break
        fi
        
        if [ $((i % 5)) -eq 0 ]; then
            print_info "Still waiting for deposits to be queryable... (attempt $i/30, balance: $user1_balance)"
        fi
        sleep 1
    done
    
    if [ "$verified" = false ]; then
        print_error "Deposits not queryable after 30 seconds!"
        print_error "This may be a Stellar testnet issue. Try running the script again."
        exit 1
    fi
    
    # Clear matching engine's balance cache to force fresh queries
    print_info "Clearing matching engine balance cache..."
    curl $CURL_OPTS -s -X POST "${BASE_URL}/api/v1/admin/clear_cache" | jq -r '.message'
    
    # Additional wait for RPC consistency across all nodes
    print_info "Waiting for RPC consistency..."
    sleep 10

    # Ensure matching engine can see vault balances before submitting orders
    print_info "Checking matching engine vault balances..."
    local expected_balance="1000000000"
    for i in {1..30}; do
        local user1_balance=$(curl $CURL_OPTS -s "${BASE_URL}/api/v1/balances?user_address=${USER1_PUBLIC}&token=XLM" | jq -r '.balance_raw // 0')
        local user2_balance=$(curl $CURL_OPTS -s "${BASE_URL}/api/v1/balances?user_address=${USER2_PUBLIC}&token=XLM" | jq -r '.balance_raw // 0')

        if [ "$user1_balance" = "$expected_balance" ] && [ "$user2_balance" = "$expected_balance" ]; then
            print_success "Matching engine sees vault balances (user1/user2: $expected_balance)"
            return
        fi

        if [ $((i % 5)) -eq 0 ]; then
            print_info "Waiting for matching engine balance sync... (attempt $i/30, user1: $user1_balance, user2: $user2_balance)"
        fi
        sleep 2
    done

    print_error "Matching engine did not observe deposited balances after 60 seconds."
    docker-compose logs matching-engine 2>&1 | tail -50
    exit 1
}

# Step 9: Submit orders (settlement happens automatically)
submit_orders() {
    print_step "Step 9: Submitting Orders (Auto-Settlement Enabled)"

    local ts=$(date +%s)
    # Use "XLM" string like test_e2e_full.sh (matching engine will convert to contract address)
    local order_template='{"order_id":"%s","user_address":"%s","asset_pair":{"base":"XLM","quote":"XLM"},"side":"%s","order_type":"Limit","price":0.5,"quantity":10,"time_in_force":"GTC","timestamp":%d}'

    # Buy Order
    local buy_json=$(printf "$order_template" "order-1" "$USER1_PUBLIC" "Buy" "$ts")
    BUY_SIG=$(python3 scripts/sign_order.py "$USER1_SECRET" "$buy_json")
    local buy_req="${buy_json%\}},\"signature\":\"$BUY_SIG\"}"

    print_info "Submitting buy order..."
    local buy_resp=$(curl $CURL_OPTS -s -X POST -H "Content-Type: application/json" -d "$buy_req" "${BASE_URL}/api/v1/orders")
    echo "$buy_resp" | jq .
    
    # Check if buy order submission failed
    if echo "$buy_resp" | jq -e '.detail' > /dev/null 2>&1; then
        print_error "Buy order submission failed!"
        print_error "Response: $(echo "$buy_resp" | jq -r '.detail')"
        exit 1
    fi

    # Sell Order (this will match and auto-settle!)
    local sell_json=$(printf "$order_template" "order-2" "$USER2_PUBLIC" "Sell" "$ts")
    SELL_SIG=$(python3 scripts/sign_order.py "$USER2_SECRET" "$sell_json")
    local sell_req="${sell_json%\}},\"signature\":\"$SELL_SIG\"}"

    print_info "Submitting sell order (will match and auto-settle)..."
    local sell_resp=$(curl $CURL_OPTS -s -X POST -H "Content-Type: application/json" -d "$sell_req" "${BASE_URL}/api/v1/orders")
    echo "$sell_resp" | jq .

    # Check if order submission failed
    if echo "$sell_resp" | jq -e '.detail' > /dev/null 2>&1; then
        print_error "Order submission failed!"
        print_error "Response: $(echo "$sell_resp" | jq -r '.detail')"
        print_error ""
        print_error "Checking matching engine logs for details..."
        docker-compose logs matching-engine 2>&1 | tail -30
        exit 1
    fi

    TRADE_ID=$(echo "$sell_resp" | jq -r '.trades[0].trade_id // empty')
    
    if [ -z "$TRADE_ID" ] || [ "$TRADE_ID" = "null" ]; then
        print_error "Orders did not match! No trade ID returned."
        print_error "Buy order response:"
        curl $CURL_OPTS -s "${BASE_URL}/api/v1/orders/order-1?asset_pair=XLM/XLM" | jq .
        print_error ""
        print_error "Checking matching engine logs..."
        docker-compose logs matching-engine 2>&1 | tail -30
        exit 1
    fi
    
    print_success "Matched Trade ID: $TRADE_ID"

    # Wait for settlement to complete (poll for success)
    print_info "Waiting for automatic settlement to complete..."
    local settled=false
    for i in {1..30}; do
        if docker-compose logs matching-engine 2>&1 | grep -q "Trade.*settled successfully"; then
            settled=true
            break
        fi
        sleep 1
    done
    
    if [ "$settled" = true ]; then
        # Show settlement transaction
        docker-compose logs matching-engine 2>&1 | grep "Trade.*settled successfully" | tail -1
        print_success "Settlement completed successfully"
    else
        print_error "Settlement did not complete within 30 seconds"
        docker-compose logs matching-engine 2>&1 | grep -i "trade\|settle\|error" | tail -10
    fi
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
        print_error ""
        print_error "Checking matching engine logs for errors..."
        docker-compose logs matching-engine 2>&1 | tail -50
        exit 1
    fi
}

# Main
main() {
    check_prerequisites
    deploy_tokens
    deploy_contract
    generate_matching_engine_keypair
    create_test_accounts
    create_docker_env
    start_matching_engine
    fund_matching_engine
    register_matching_engine
    deposit_funds
    submit_orders
    verify_balances

    print_step "Docker-based E2E Test Completed Successfully"
    
    print_info "To view matching engine logs, run: docker-compose logs matching-engine"
    print_info "To stop the container manually, run: docker-compose down -v"
}

main
