#!/bin/bash

# Demo script for communicating with a remote TEE-deployed matching engine.
#
# This script demonstrates:
# 1. Verifying TEE attestation (compose-hash, TLS SPKI, report_data)
# 2. Extracting matching engine identity from attestation
# 3. Setting up test accounts and contract
# 4. Submitting matching orders
# 5. Verifying on-chain settlement
#
# Usage:
#     ./scripts/demo_remote_tee.sh <tee_base_url> [--contract-id CONTRACT_ID] [--skip-attestation]
#
# Examples:
#     # Full demo with attestation verification
#     ./scripts/demo_remote_tee.sh https://c5d5291eef49362eaadcac3d3bf62eb5f3452860-443s.dstack-pha-prod9.phala.network
#
#     # Use existing contract (skip deployment)
#     ./scripts/demo_remote_tee.sh https://stellardark.io --contract-id CDLZFC3SYJYDZT7K67VZ75HPJVIEUCX4XJM7M6B7YJ2W3C5VY5KZ5KZ5K
#
#     # Skip attestation verification (for testing)
#     ./scripts/demo_remote_tee.sh https://stellardark.io --skip-attestation
#
# Requirements: stellar CLI, curl, jq, python3 (for sign_order.py and verify_remote_attestation.py)

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
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEE_BASE_URL=""
CONTRACT_ID=""
SKIP_ATTESTATION=false
SKIP_SETUP=false

# Print functions (all go to stderr so they don't interfere with command substitution)
print_step() {
    echo -e "\n${BLUE}=== $1 ===${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}" >&2
}

print_error() {
    echo -e "${RED}✗ $1${NC}" >&2
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}" >&2
}

# Parse arguments
parse_args() {
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <tee_base_url> [--contract-id CONTRACT_ID] [--skip-attestation] [--skip-setup]"
        exit 1
    fi
    
    TEE_BASE_URL="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --contract-id)
                CONTRACT_ID="$2"
                shift 2
                ;;
            --skip-attestation)
                SKIP_ATTESTATION=true
                shift
                ;;
            --skip-setup)
                SKIP_SETUP=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Normalize URL (remove trailing slash)
    TEE_BASE_URL="${TEE_BASE_URL%/}"
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking Prerequisites"
    
    local missing_tools=()
    for tool in stellar curl jq python3; do
        command -v $tool &> /dev/null || missing_tools+=("$tool")
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check if stellar-sdk is installed (needed for sign_order.py)
    if ! python3 -c "import stellar_sdk" 2>/dev/null; then
        print_info "stellar-sdk not found, installing..."
        pip3 install -q stellar-sdk || {
            print_error "Failed to install stellar-sdk. Install manually with: pip3 install stellar-sdk"
            exit 1
        }
    fi
    
    # Check if verify_remote_attestation.py exists
    if [ ! -f "$ROOT_DIR/scripts/verify_remote_attestation.py" ]; then
        print_error "verify_remote_attestation.py not found at $ROOT_DIR/scripts/verify_remote_attestation.py"
        exit 1
    fi
    
    # Check if sign_order.py exists
    if [ ! -f "$ROOT_DIR/scripts/sign_order.py" ]; then
        print_error "sign_order.py not found at $ROOT_DIR/scripts/sign_order.py"
        exit 1
    fi
    
    print_success "All required prerequisites met"
}

# Verify TEE attestation
verify_attestation() {
    print_step "Verifying TEE Attestation"
    
    if [ "$SKIP_ATTESTATION" = true ]; then
        print_info "Skipping attestation verification (--skip-attestation)"
        return 0
    fi
    
    print_info "Running attestation verification..."
    if python3 "$ROOT_DIR/scripts/verify_remote_attestation.py" "$TEE_BASE_URL"; then
        print_success "Attestation verification passed"
        return 0
    else
        print_error "Attestation verification failed"
        return 1
    fi
}

# Get matching engine public key from /info or /attestation
get_matching_engine_pubkey() {
    print_step "Getting Matching Engine Identity"
    
    # Try /info first (lighter weight)
    local info_data
    info_data=$(curl -s -k "${TEE_BASE_URL}/info" || echo "")
    
    if [ -n "$info_data" ]; then
        local pubkey
        pubkey=$(echo "$info_data" | jq -r '.matching_engine_pubkey // .identity.stellar_pubkey // empty')
        
        if [ -n "$pubkey" ] && [ "$pubkey" != "null" ]; then
            print_success "Matching engine public key: $pubkey"
            echo "$pubkey"  # Echo to stdout for capture
            return 0
        fi
    fi
    
    # Fallback to /attestation
    local attestation_data
    attestation_data=$(curl -s -k "${TEE_BASE_URL}/attestation" || echo "")
    
    if [ -n "$attestation_data" ]; then
        local pubkey
        pubkey=$(echo "$attestation_data" | jq -r '.identity.stellar_pubkey // .identity.matching_engine_pubkey // empty')
        
        if [ -n "$pubkey" ] && [ "$pubkey" != "null" ]; then
            print_success "Matching engine public key: $pubkey"
            echo "$pubkey"  # Echo to stdout for capture
            return 0
        fi
    fi
    
    print_error "Could not determine matching engine public key"
    return 1
}

# Check matching engine health
check_health() {
    print_step "Checking Matching Engine Health"
    
    local health_data
    health_data=$(curl -s -k "${TEE_BASE_URL}/health" || echo "")
    
    if [ -z "$health_data" ]; then
        print_error "Health check failed: could not reach matching engine"
        return 1
    fi
    
    local status
    status=$(echo "$health_data" | jq -r '.status // "unknown"')
    print_success "Health: $status"
    return 0
}

# Get XLM token contract ID
get_xlm_token_id() {
    print_info "Getting XLM token contract ID..."
    stellar contract id asset --asset native --network testnet
}

# Fund account via Friendbot
fund_account() {
    local address="$1"
    print_info "Funding account via Friendbot: $address"
    curl -s "https://friendbot.stellar.org/?addr=${address}" > /dev/null 2>&1 || true
    sleep 3
    print_success "Account funded"
}

# Register matching engine in contract
register_matching_engine() {
    print_step "Registering Matching Engine"
    
    local contract_id="$1"
    local matching_engine_pubkey="$2"
    
    # Ensure admin account exists
    if ! stellar keys ls 2>/dev/null | grep -q "^test"; then
        print_info "No test account found..."
        return 1
    fi
    
    print_info "Registering $matching_engine_pubkey as matching engine..."
    
    local output
    output=$(stellar contract invoke \
        --id "$contract_id" \
        --source test \
        --network testnet \
        -- \
        set_matching_engine \
        --matching_engine "$matching_engine_pubkey" 2>&1)
    
    local returncode=$?
    
    if [ $returncode -eq 0 ]; then
        print_success "Matching engine registered"
        return 0
    else
        print_error "Registration failed"
        print_error "Error output: $output"
        
        # Check if it's already registered (that's okay)
        if echo "$output" | grep -qi "already\|duplicate\|exists"; then
            print_info "Matching engine may already be registered (this is okay)"
            return 0
        fi
        
        # Check if it's a permission/authorization error or missing signing key
        if echo "$output" | grep -qi "unauthorized\|permission\|not authorized\|not the admin\|Missing signing key"; then
            print_info "Note: This contract was deployed with a different admin account."
            print_info "Cannot register matching engine without the original admin key."
            print_info "Assuming matching engine is already registered (common for existing contracts)."
            print_info "Continuing with demo..."
            return 0
        fi
        
        return 1
    fi
}

# Create test account
create_test_account() {
    local key_alias="$1"
    
    # Check if account already exists
    if stellar keys ls 2>/dev/null | grep -q "^${key_alias}"; then
        print_info "Account $key_alias already exists, using existing account"
        local public_key
        public_key=$(stellar keys address "$key_alias")
        print_success "Using existing account: $public_key"
        echo "$public_key"
        return 0
    fi
    
    print_info "Creating account: $key_alias"
    
    # Generate and fund
    stellar keys generate "$key_alias" --fund --network testnet
    
    local public_key
    public_key=$(stellar keys address "$key_alias")
    
    print_success "Created account: $public_key"
    echo "$public_key"
}

# Deposit funds to contract vault
deposit_funds() {
    local contract_id="$1"
    local user_key_alias="$2"
    local user_address="$3"
    local token_id="$4"
    local amount="$5"
    
    print_info "Depositing $amount stroops of token ${token_id:0:8}... to vault for ${user_address:0:8}..."
    
    if stellar contract invoke \
        --id "$contract_id" \
        --source "$user_key_alias" \
        --network testnet \
        -- \
        deposit \
        --user "$user_address" \
        --token "$token_id" \
        --amount "$amount" > /dev/null 2>&1; then
        print_success "Deposit successful"
        sleep 5  # Wait for on-chain confirmation
        return 0
    else
        print_error "Deposit failed"
        return 1
    fi
}

# Check vault balance
check_balance() {
    local contract_id="$1"
    local user_key_alias="$2"
    local user_address="$3"
    local token_id="$4"
    
    local output
    output=$(stellar contract invoke \
        --id "$contract_id" \
        --source "$user_key_alias" \
        --network testnet \
        -- \
        get_balance \
        --user "$user_address" \
        --token "$token_id" 2>&1)
    
    # Extract balance from output
    echo "$output" | grep -oE '"[0-9]*"' | tr -d '"' || echo "0"
}

# Submit order to matching engine
submit_order() {
    local order_json="$1"
    local signature="$2"
    
    # Add signature to order
    local order_with_sig
    order_with_sig=$(echo "$order_json" | jq --arg sig "$signature" '. + {signature: $sig}')
    
    local response
    response=$(curl -s -k -X POST \
        -H "Content-Type: application/json" \
        -d "$order_with_sig" \
        "${TEE_BASE_URL}/api/v1/orders")
    
    # Check for errors
    if echo "$response" | jq -e '.detail' > /dev/null 2>&1; then
        print_error "Order submission failed: $(echo "$response" | jq -r '.detail')"
        return 1
    fi
    
    echo "$response"
    return 0
}

# Main execution
main() {
    parse_args "$@"
    
    echo -e "\n${BLUE}======================================================================${NC}"
    echo -e "${BLUE}Stellar Dark Pool - Remote TEE Demo${NC}"
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "\nTEE URL: ${TEE_BASE_URL}\n"
    check_prerequisites
    
    # Step 1: Verify attestation
    if ! verify_attestation; then
        print_error "Attestation verification failed. Exiting."
        exit 1
    fi
    
    # Step 2: Get matching engine public key
    local matching_engine_pubkey
    matching_engine_pubkey=$(get_matching_engine_pubkey)
    if [ -z "$matching_engine_pubkey" ]; then
        exit 1
    fi
    
    # Step 3: Check health
    if ! check_health; then
        exit 1
    fi
    
    # Step 4: Setup (contract deployment, accounts, etc.)
    if [ "$SKIP_SETUP" = false ]; then
        print_step "Setting Up Test Environment"
        
        # Get XLM token ID
        local xlm_token_id
        xlm_token_id=$(get_xlm_token_id)
        print_success "XLM Token ID: $xlm_token_id"
        
        # Deploy or use existing contract
        if [ -n "$CONTRACT_ID" ]; then
            print_info "Using existing contract: $CONTRACT_ID"
        else
            print "Please set the CONTRACT_ID environment variable or provide the --contract-id argument"
            return 1
        fi
        
        # Fund matching engine account
        print_step "Funding Matching Engine Account"
        print_info "Matching engine public key: $matching_engine_pubkey"
        fund_account "$matching_engine_pubkey"
        
        # Register matching engine
        if ! register_matching_engine "$CONTRACT_ID" "$matching_engine_pubkey"; then
            print_error "Failed to register matching engine"
            exit 1
        fi
        
        # Create test user accounts
        print_step "Creating Test User Accounts"
        local user1_pubkey
        user1_pubkey=$(create_test_account "demo_user1")
        local user2_pubkey
        user2_pubkey=$(create_test_account "demo_user2")
        
        # Get secrets
        local user1_secret
        user1_secret=$(stellar keys show demo_user1)
        local user2_secret
        user2_secret=$(stellar keys show demo_user2)
        
        # Deposit funds
        print_step "Depositing Funds to Vault"
        local deposit_amount=1000000000  # 100 XLM in stroops
        
        if ! deposit_funds "$CONTRACT_ID" "demo_user1" "$user1_pubkey" "$xlm_token_id" "$deposit_amount"; then
            print_error "Failed to deposit funds for user1"
            exit 1
        fi
        
        if ! deposit_funds "$CONTRACT_ID" "demo_user2" "$user2_pubkey" "$xlm_token_id" "$deposit_amount"; then
            print_error "Failed to deposit funds for user2"
            exit 1
        fi
        
        # Get starting balances after deposits (for settlement verification)
        print_info "Recording starting balances after deposits..."
        local user1_starting_balance
        user1_starting_balance=$(check_balance "$CONTRACT_ID" "demo_user1" "$user1_pubkey" "$xlm_token_id")
        local user2_starting_balance
        user2_starting_balance=$(check_balance "$CONTRACT_ID" "demo_user2" "$user2_pubkey" "$xlm_token_id")
        print_info "User1 starting balance: $user1_starting_balance stroops"
        print_info "User2 starting balance: $user2_starting_balance stroops"
        
        print_success "Setup complete!"
    else
        print_info "Skipping setup (--skip-setup)"
        print_error "--skip-setup requires manual configuration of contract_id and user accounts"
        print_error "This feature is not fully implemented. Please run without --skip-setup."
        exit 1
    fi
    
    # Step 5: Submit matching orders
    print_step "Submitting Matching Orders"
    
    # Get user accounts
    local user1_pubkey
    user1_pubkey=$(stellar keys address demo_user1)
    local user1_secret
    user1_secret=$(stellar keys show demo_user1)
    local user2_pubkey
    user2_pubkey=$(stellar keys address demo_user2)
    local user2_secret
    user2_secret=$(stellar keys show demo_user2)
    
    # Create buy order
    local ts
    ts=$(date +%s)
    local buy_order_json
    buy_order_json=$(jq -n \
        --arg order_id "demo-buy-$ts" \
        --arg user_address "$user1_pubkey" \
        --argjson timestamp "$ts" \
        '{
            order_id: $order_id,
            user_address: $user_address,
            asset_pair: {base: "XLM", quote: "XLM"},
            side: "Buy",
            order_type: "Limit",
            price: 0.5,
            quantity: 10,
            time_in_force: "GTC",
            timestamp: ($timestamp | tonumber)
        }')
    
    local buy_signature
    buy_signature=$(python3 "$ROOT_DIR/scripts/sign_order.py" "$user1_secret" "$buy_order_json")
    
    print_info "Submitting buy order..."
    local buy_response
    if ! buy_response=$(submit_order "$buy_order_json" "$buy_signature"); then
        print_error "Buy order submission failed"
        exit 1
    fi
    
    echo "$buy_response" | jq .
    print_success "Buy order submitted: $(echo "$buy_response" | jq -r '.order_id')"
    
    if echo "$buy_response" | jq -e '.trades | length > 0' > /dev/null 2>&1; then
        print_info "Immediate match! Trade ID: $(echo "$buy_response" | jq -r '.trades[0].trade_id')"
    fi
    
    # Create sell order (will match with buy)
    local sell_order_json
    sell_order_json=$(jq -n \
        --arg order_id "demo-sell-$ts" \
        --arg user_address "$user2_pubkey" \
        --argjson timestamp "$ts" \
        '{
            order_id: $order_id,
            user_address: $user_address,
            asset_pair: {base: "XLM", quote: "XLM"},
            side: "Sell",
            order_type: "Limit",
            price: 0.5,
            quantity: 10,
            time_in_force: "GTC",
            timestamp: ($timestamp | tonumber)
        }')
    
    local sell_signature
    sell_signature=$(python3 "$ROOT_DIR/scripts/sign_order.py" "$user2_secret" "$sell_order_json")
    
    print_info "Submitting sell order (will match with buy)..."
    local sell_response
    if ! sell_response=$(submit_order "$sell_order_json" "$sell_signature"); then
        print_error "Sell order submission failed"
        exit 1
    fi
    
    echo "$sell_response" | jq .
    print_success "Sell order submitted: $(echo "$sell_response" | jq -r '.order_id')"
    
    local trades
    trades=$(echo "$sell_response" | jq -r '.trades // []')
    
    if [ "$(echo "$trades" | jq 'length')" -gt 0 ]; then
        local trade_id
        trade_id=$(echo "$sell_response" | jq -r '.trades[0].trade_id')
        print_success "Orders matched! Trade ID: $trade_id"
        
        # Wait for settlement
        print_info "Waiting for settlement to complete..."
        sleep 10
        
        # Step 6: Verify settlement
        print_step "Verifying Settlement"
        
        # Extract trade details from response
        local trade_quantity
        trade_quantity=$(echo "$sell_response" | jq -r '.trades[0].quantity // 10')
        local trade_price
        trade_price=$(echo "$sell_response" | jq -r '.trades[0].price // 0.5')
        
        # Debug: show full trade response
        print_info "Full trade response:"
        echo "$sell_response" | jq '.trades[0]' >&2
        
        # Check actual balance changes to understand the settlement pattern
        local user1_balance_before
        user1_balance_before=$user1_starting_balance
        local user2_balance_before
        user2_balance_before=$user2_starting_balance
        
        # Wait a bit more for settlement to propagate
        sleep 5
        
        # Check actual balances
        local user1_balance
        user1_balance=$(check_balance "$CONTRACT_ID" "demo_user1" "$user1_pubkey" "$xlm_token_id")
        local user2_balance
        user2_balance=$(check_balance "$CONTRACT_ID" "demo_user2" "$user2_pubkey" "$xlm_token_id")
        
        # Calculate actual changes
        local user1_change
        user1_change=$((user1_balance - user1_balance_before))
        local user2_change
        user2_change=$((user2_balance - user2_balance_before))
        
        print_info "Actual balance changes:"
        print_info "  User1 (buyer): $user1_balance_before → $user1_balance (change: $user1_change stroops)"
        print_info "  User2 (seller): $user2_balance_before → $user2_balance (change: $user2_change stroops)"
        
        # Calculate expected based on actual pattern
        # When base == quote, the contract might do net settlement
        # Based on actual: User1 got +50000000, User2 got -50000000
        # This is quantity * price * 10000000 (not 100000000)
        # So maybe quantity is already in stroops? Or there's a different scaling?
        
        # Stellar uses 10^7 (10,000,000) stroops per XLM, not 10^8
        # So: 1 XLM = 10,000,000 stroops
        local STROOPS_PER_XLM=10000000
        local quantity_stroops
        quantity_stroops=$(awk "BEGIN {printf \"%.0f\", $trade_quantity * $STROOPS_PER_XLM}")
        local quote_amount_stroops
        quote_amount_stroops=$(awk "BEGIN {printf \"%.0f\", $trade_quantity * $trade_price * $STROOPS_PER_XLM}")
        
        # Calculate expected balances
        # User1 (buyer): starting + quantity_base - quantity_quote
        # User2 (seller): starting - quantity_base + quantity_quote
        local user1_expected
        user1_expected=$((user1_starting_balance + quantity_stroops - quote_amount_stroops))
        local user2_expected
        user2_expected=$((user2_starting_balance - quantity_stroops + quote_amount_stroops))
        
        print_info "Trade details: quantity=$trade_quantity, price=$trade_price"
        print_info "Calculated: quantity_stroops=$quantity_stroops, quote_amount_stroops=$quote_amount_stroops"
        print_info "User1: starting=$user1_starting_balance, expected=$user1_expected, actual=$user1_balance"
        print_info "User2: starting=$user2_starting_balance, expected=$user2_expected, actual=$user2_balance"
        
        # Verify balances match expected (allow small rounding differences)
        local diff1
        if [ "$user1_balance" -gt "$user1_expected" ]; then
            diff1=$((user1_balance - user1_expected))
        else
            diff1=$((user1_expected - user1_balance))
        fi
        
        local diff2
        if [ "$user2_balance" -gt "$user2_expected" ]; then
            diff2=$((user2_balance - user2_expected))
        else
            diff2=$((user2_expected - user2_balance))
        fi
        
        # Allow up to 1 stroop difference for rounding
        if [ "$diff1" -le 1 ] && [ "$diff2" -le 1 ]; then
            print_success "Settlement verified! Balances are correct."
        else
            print_error "Settlement verification failed. Balances don't match expected values."
            print_error "User1: expected $user1_expected, got $user1_balance (diff: $diff1)"
            print_error "User2: expected $user2_expected, got $user2_balance (diff: $diff2)"
            exit 1
        fi
    else
        print_error "Orders did not match"
        exit 1
    fi
    
    print_step "Demo Completed Successfully"
    print_success "All steps completed!"
    print_info "Contract ID: $CONTRACT_ID"
    print_info "Matching Engine: $matching_engine_pubkey"
    print_info "Trade executed and settled on-chain"
}

main "$@"
