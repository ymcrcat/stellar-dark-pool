# Stellar Dark Pool

A decentralized dark pool on Stellar, featuring privacy-preserving order matching and on-chain settlement.

## Overview

The Stellar Dark Pool is a prototype for privacy-presering trading on Stellar. Orders are first matched off-chain in a private matching engine, so trading intentions are not immediately visible on the blockchain. Once a match is found, trades are settled transparently on the Stellar network. Users deposit their funds into the contract ahead of time, which allows for instant settlement when a trade occurs.

## Project Structure

- **contracts/settlement**: Soroban smart contract for trade settlement and vault management
- **matching-engine**: Python-based off-chain matching engine with REST API
- **scripts**: Utility scripts for order signing and testing

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed system design.

## Prerequisites

### Required Tools
- **Stellar CLI**: `cargo install stellar-cli --locked`
- **Rust**: Install from [rustup.rs](https://rustup.rs) with wasm32 target
  ```bash
  rustup target add wasm32-unknown-unknown
  ```
- **Python 3.10+**: For the matching engine
- **curl & jq**: For testing and API interactions

### Verify Installation
```bash
stellar --version    # Should show stellar-cli version
rustc --version      # Should show Rust version
python3 --version    # Should show Python 3.10+
```

## Deployment Guide

### Step 1: Deploy Settlement Contract

#### 1.1 Build the Contract
```bash
cd contracts/settlement
stellar contract build --profile release-with-logs --optimize
```

The optimized WASM will be in `target/wasm32v1-none/release-with-logs/settlement.wasm`.

> **Note**: The `--optimize` flag reduces WASM size and gas costs, which is essential for deployment.

#### 1.2 Generate Admin Account (if needed)
```bash
stellar keys generate admin --network testnet
export ADMIN_ADDRESS=$(stellar keys address admin)

# Fund the account via Friendbot
curl "https://friendbot.stellar.org?addr=$ADMIN_ADDRESS"
```

#### 1.3 Get Token Contract IDs

You need two token contract IDs for the trading pair. For native assets (XLM):
```bash
# Get XLM contract ID
stellar contract id asset --asset native --network testnet
# Example output: CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC

# For other assets like USDC, you need the asset code and issuer:
stellar contract id asset --asset USDC:ISSUER_ADDRESS --network testnet
```

#### 1.4 Deploy Contract
```bash
stellar contract deploy \
  --wasm target/wasm32v1-none/release-with-logs/settlement.wasm \
  --source admin \
  --network testnet \
  -- \
  --admin $ADMIN_ADDRESS \
  --token_a <TOKEN_A_CONTRACT_ID> \
  --token_b <TOKEN_B_CONTRACT_ID>
```

Save the contract ID from the output:
```bash
export SETTLEMENT_CONTRACT_ID=<contract_id_from_output>
```

### Step 2: Configure Matching Engine

#### 2.1 Generate Matching Engine Keypair
```bash
stellar keys generate matching-engine --network testnet
export MATCHING_ENGINE_ADDRESS=$(stellar keys address matching-engine)

# Fund the account
curl "https://friendbot.stellar.org?addr=$MATCHING_ENGINE_ADDRESS"
```

#### 2.2 Authorize Matching Engine in Contract
```bash
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source admin \
  --network testnet \
  -- set_matching_engine \
  --matching_engine $MATCHING_ENGINE_ADDRESS
```

#### 2.3 Get Matching Engine Secret Key
```bash
export MATCHING_ENGINE_SECRET=$(stellar keys show matching-engine)
```

#### 2.4 Create Configuration File
```bash
cd matching-engine
cat > .env << EOF
# Stellar Network Configuration
STELLAR_NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
SOROBAN_RPC_URL="https://soroban-testnet.stellar.org"
HORIZON_URL="https://horizon-testnet.stellar.org"

# Contract Configuration
SETTLEMENT_CONTRACT_ID="$SETTLEMENT_CONTRACT_ID"

# Matching Engine Configuration
MATCHING_ENGINE_SIGNING_KEY="$MATCHING_ENGINE_SECRET"
REST_PORT=8080
EOF
```

### Step 3: Install Matching Engine Dependencies

```bash
cd matching-engine

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### Step 4: Run Matching Engine

```bash
# From matching-engine directory with venv activated
python -m src.main
```

The API will be available at `http://localhost:8080`.

Verify it's running:
```bash
curl http://localhost:8080/health
# Should return: {"status":"healthy","timestamp":...}
```

## Using the Dark Pool

### 1. Deposit Funds into Vault

Before trading, users must deposit funds into the settlement contract:

```bash
# Generate user account
stellar keys generate trader1 --network testnet
export TRADER1_ADDRESS=$(stellar keys address trader1)
curl "https://friendbot.stellar.org?addr=$TRADER1_ADDRESS"

# Deposit 100 XLM (in stroops: 100 * 10^7)
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source trader1 \
  --network testnet \
  -- deposit \
  --user $TRADER1_ADDRESS \
  --token <XLM_CONTRACT_ID> \
  --amount 1000000000
```

### 2. Check Vault Balance

```bash
# Via CLI
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source trader1 \
  --network testnet \
  -- get_balance \
  --user $TRADER1_ADDRESS \
  --token <XLM_CONTRACT_ID>

# Or via API
curl "http://localhost:8080/api/v1/balances?user_address=$TRADER1_ADDRESS&token=XLM"
```

### 3. Submit Orders

Orders must be signed using SEP-0053. First, create the order JSON and sign it:

```bash
# Get the trader's secret key
TRADER1_SECRET=$(stellar keys show trader1)

# Create order JSON
ORDER_JSON=$(cat <<EOF
{
  "order_id": "order-123",
  "user_address": "$TRADER1_ADDRESS",
  "asset_pair": {"base": "XLM", "quote": "USDC"},
  "side": "Buy",
  "order_type": "Limit",
  "price": 0.12,
  "quantity": 100,
  "time_in_force": "GTC",
  "timestamp": $(date +%s)
}
EOF
)

# Sign the order
SIGNATURE=$(python3 scripts/sign_order.py "$TRADER1_SECRET" "$ORDER_JSON")

# Submit the order
curl -X POST http://localhost:8080/api/v1/orders \
  -H "Content-Type: application/json" \
  -d "$(echo "$ORDER_JSON" | jq --arg sig "$SIGNATURE" '. + {signature: $sig}')"
```

### 4. View Order Book

```bash
curl http://localhost:8080/api/v1/orderbook/XLM/USDC
```

### 5. Withdraw Funds

```bash
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source trader1 \
  --network testnet \
  -- withdraw \
  --user $TRADER1_ADDRESS \
  --token <XLM_CONTRACT_ID> \
  --amount 500000000
```

## API Reference

### Endpoints

- `POST /api/v1/orders` - Submit a new order
- `GET /api/v1/orders/{id}` - Get order status
- `DELETE /api/v1/orders/{id}` - Cancel an order
- `GET /api/v1/orderbook/{pair}` - Get order book snapshot (top 20 levels)
- `GET /api/v1/balances` - Query vault balance
- `POST /api/v1/settlement/submit` - Submit settlement instruction (matching engine only)
- `GET /health` - Health check

See [matching-engine/README.md](matching-engine/README.md) for detailed API documentation.

## Testing

### Run End-to-End Test

```bash
# From project root
bash test_e2e_full.sh
```

This script:
1. Deploys test tokens
2. Builds and deploys the settlement contract
3. Sets up and starts the matching engine
4. Creates test accounts and deposits funds
5. Submits matching orders
6. Submits settlement transaction
7. Verifies vault balances changed correctly

### Run Contract Tests

```bash
cd contracts/settlement
cargo test
```

### Run Matching Engine Tests

```bash
cd matching-engine
source venv/bin/activate
pytest
```

## Manual Testing Demo

This section provides a complete step-by-step manual walkthrough to test the dark pool from scratch. Follow these steps to deploy the contract, start the matching engine, and execute a trade.

### Prerequisites

Ensure you have completed the [Deployment Guide](#deployment-guide) steps 1-4 above. You should have:
- ✅ Settlement contract deployed with `$SETTLEMENT_CONTRACT_ID` set
- ✅ Matching engine configured and running on port 8080
- ✅ Matching engine authorized in the contract

### Step 1: Verify Matching Engine is Running

```bash
curl http://localhost:8080/health
```

**Expected output:**
```json
{"status":"healthy","timestamp":1234567890}
```

If this fails, go back and start the matching engine (see Step 4 in Deployment Guide).

### Step 2: Create Test Trader Accounts

Create two trader accounts (one buyer, one seller):

```bash
# Create buyer account
stellar keys generate buyer --network testnet
export BUYER_ADDRESS=$(stellar keys address buyer)
curl "https://friendbot.stellar.org?addr=$BUYER_ADDRESS"

# Create seller account
stellar keys generate seller --network testnet
export SELLER_ADDRESS=$(stellar keys address seller)
curl "https://friendbot.stellar.org?addr=$SELLER_ADDRESS"

# Wait for funding to complete
sleep 5
```

### Step 3: Get Token Contract ID

```bash
# Get XLM contract ID (we'll use XLM for both base and quote in this demo)
export TOKEN_ID=$(stellar contract id asset --asset native --network testnet)
echo "Token ID: $TOKEN_ID"
```

### Step 4: Deposit Funds into Vault

Both traders need to deposit funds before trading:

```bash
# Buyer deposits 100 XLM (1,000,000,000 stroops)
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source buyer \
  --network testnet \
  -- deposit \
  --user $BUYER_ADDRESS \
  --token $TOKEN_ID \
  --amount 1000000000

# Seller deposits 100 XLM
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source seller \
  --network testnet \
  -- deposit \
  --user $SELLER_ADDRESS \
  --token $TOKEN_ID \
  --amount 1000000000
```

**Verification:** Check balances were deposited correctly:
```bash
# Check buyer balance
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source buyer \
  --network testnet \
  -- get_balance \
  --user $BUYER_ADDRESS \
  --token $TOKEN_ID

# Should output: 1000000000
```

You can also check via the API:
```bash
curl "http://localhost:8080/api/v1/balances?user_address=$BUYER_ADDRESS&token=XLM"
```

### Step 5: Get Secret Keys for Order Signing

```bash
export BUYER_SECRET=$(stellar keys show buyer)
export SELLER_SECRET=$(stellar keys show seller)
```

### Step 6: Create and Submit Buy Order

First, let's check the order book is empty:
```bash
curl http://localhost:8080/api/v1/orderbook/XLM/XLM | jq
```

**Expected output:**
```json
{
  "pair": "XLM/XLM",
  "bids": [],
  "asks": [],
  "timestamp": 1234567890
}
```

Now create a buy order JSON:
```bash
export BUY_ORDER=$(cat <<EOF
{
  "order_id": "buy-order-1",
  "user_address": "$BUYER_ADDRESS",
  "asset_pair": {"base": "XLM", "quote": "XLM"},
  "side": "Buy",
  "order_type": "Limit",
  "price": 1.0,
  "quantity": 10,
  "time_in_force": "GTC",
  "timestamp": $(date +%s)
}
EOF
)

echo "$BUY_ORDER" | jq
```

Sign and submit the buy order:
```bash
# Sign the order
BUY_SIGNATURE=$(python3 scripts/sign_order.py "$BUYER_SECRET" "$BUY_ORDER")

# Create request with signature
BUY_REQUEST=$(echo "$BUY_ORDER" | jq --arg sig "$BUY_SIGNATURE" '. + {signature: $sig}')

# Submit order
curl -X POST http://localhost:8080/api/v1/orders \
  -H "Content-Type: application/json" \
  -d "$BUY_REQUEST" | jq
```

**Expected output:**
```json
{
  "order_id": "buy-order-1",
  "status": "submitted",
  "trades": []
}
```

Verify the order is in the book:
```bash
curl http://localhost:8080/api/v1/orderbook/XLM/XLM | jq
```

You should now see your buy order in the `bids` array.

### Step 7: Create and Submit Sell Order (This Will Match!)

Create a matching sell order:
```bash
export SELL_ORDER=$(cat <<EOF
{
  "order_id": "sell-order-1",
  "user_address": "$SELLER_ADDRESS",
  "asset_pair": {"base": "XLM", "quote": "XLM"},
  "side": "Sell",
  "order_type": "Limit",
  "price": 1.0,
  "quantity": 10,
  "time_in_force": "GTC",
  "timestamp": $(date +%s)
}
EOF
)

echo "$SELL_ORDER" | jq
```

Sign and submit the sell order:
```bash
# Sign the order
SELL_SIGNATURE=$(python3 scripts/sign_order.py "$SELLER_SECRET" "$SELL_ORDER")

# Create request with signature
SELL_REQUEST=$(echo "$SELL_ORDER" | jq --arg sig "$SELL_SIGNATURE" '. + {signature: $sig}')

# Submit order - THIS WILL MATCH!
MATCH_RESPONSE=$(curl -X POST http://localhost:8080/api/v1/orders \
  -H "Content-Type: application/json" \
  -d "$SELL_REQUEST")

echo "$MATCH_RESPONSE" | jq
```

**Expected output (MATCH!):**
```json
{
  "order_id": "sell-order-1",
  "status": "submitted",
  "trades": [
    {
      "trade_id": "3c030378-c759-4930-b934-a7b2332df02a",
      "buy_order_id": "buy-order-1",
      "sell_order_id": "sell-order-1",
      "price": "1.0",
      "quantity": "10",
      "buy_user": "GA37GF6D...",
      "sell_user": "GCKPVLG6...",
      "asset_pair": {
        "base": "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC",
        "quote": "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
      },
      "timestamp": 1767657936
    }
  ]
}
```

🎉 **Orders matched!** The matching engine found the opposing orders and created a trade.

### Step 8: Submit Settlement to Blockchain

Extract the trade ID from the match response:
```bash
TRADE_ID=$(echo "$MATCH_RESPONSE" | jq -r '.trades[0].trade_id')
echo "Trade ID: $TRADE_ID"
```

Create settlement instruction:
```bash
# Note: Using different base_amount and quote_amount to demonstrate visible balance changes
# In production, amounts would match the actual trade price and quantity
SETTLEMENT=$(cat <<EOF
{
  "trade_id": "$TRADE_ID",
  "buy_user": "$BUYER_ADDRESS",
  "sell_user": "$SELLER_ADDRESS",
  "base_asset": "XLM",
  "quote_asset": "XLM",
  "base_amount": 100000000,
  "quote_amount": 50000000,
  "fee_base": 0,
  "fee_quote": 0,
  "timestamp": $(date +%s),
  "buy_order_signature": "$BUY_SIGNATURE",
  "sell_order_signature": "$SELL_SIGNATURE"
}
EOF
)
```

Submit settlement transaction:
```bash
SETTLEMENT_RESPONSE=$(curl -X POST http://localhost:8080/api/v1/settlement/submit \
  -H "Content-Type: application/json" \
  -d "$SETTLEMENT")

echo "$SETTLEMENT_RESPONSE" | jq
```

**Expected output:**
```json
{
  "status": "submitted",
  "transaction_hash": "7f32dbb3c0820234e519ed5ea00966a3f8a85b315b92a242db2f069c4edaa3ce",
  "message": "Settlement transaction signed and submitted successfully"
}
```

### Step 9: Verify Settlement on Blockchain

View the transaction on Stellar Expert:
```bash
TX_HASH=$(echo "$SETTLEMENT_RESPONSE" | jq -r '.transaction_hash')
echo "View transaction: https://stellar.expert/explorer/testnet/tx/$TX_HASH"
```

Open that URL in your browser to see the settlement transaction on-chain.

### Step 10: Verify Balances Changed

Check that vault balances updated correctly:
```bash
# Buyer balance (should be 1050000000 = 105 XLM)
# Started with 100 XLM, received 10 XLM base, paid 5 XLM quote = net +5 XLM
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source buyer \
  --network testnet \
  -- get_balance \
  --user $BUYER_ADDRESS \
  --token $TOKEN_ID

# Seller balance (should be 950000000 = 95 XLM)
# Started with 100 XLM, paid 10 XLM base, received 5 XLM quote = net -5 XLM
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source seller \
  --network testnet \
  -- get_balance \
  --user $SELLER_ADDRESS \
  --token $TOKEN_ID
```

**Expected changes:**
- Buyer: 1000000000 → 1050000000 (+50000000 stroops = +5 XLM)
- Seller: 1000000000 → 950000000 (-50000000 stroops = -5 XLM)

**Note:** We used unequal amounts (base=10 XLM, quote=5 XLM) to demonstrate visible balance changes. In production with proper price matching, if you trade XLM/XLM at 1:1, balances wouldn't change (buyer receives same amount they pay). For realistic balance changes, use different assets like XLM/USDC.

### Step 11: Check Order Book is Clear

```bash
curl http://localhost:8080/api/v1/orderbook/XLM/XLM | jq
```

The order book should be empty again since both orders were fully filled.

### Success! 🎉

You've successfully:
- ✅ Deployed the settlement contract
- ✅ Started the matching engine
- ✅ Created trader accounts and deposited funds
- ✅ Submitted buy and sell orders
- ✅ Matched orders off-chain
- ✅ Settled the trade on-chain
- ✅ Verified balances updated correctly

### Next Steps

- Try creating orders at different prices to see the order book build up
- Submit orders that partially fill
- Test order cancellation with `DELETE /api/v1/orders/{id}`
- Try different asset pairs (deploy custom tokens)
- Test withdrawal functionality

## Key Features

- **Soroban-native**: Uses only Soroban RPC (no Horizon dependency for matching engine)
- **Vault Model**: Users deposit assets into the contract; trades settle against vault balances
- **Order Integrity**: SEP-0053 signatures ensure orders cannot be forged
- **Instant Settlement**: Pre-locked funds enable instant, guaranteed settlement
- **Privacy**: Orders remain private until settlement
- **Price-Time Priority**: Fair matching with FIFO ordering at each price level

## Troubleshooting

### Contract Deployment Issues

**Error: "account not found"**
- Solution: Fund your account via Friendbot: `curl "https://friendbot.stellar.org?addr=YOUR_ADDRESS"`

**Error: "wasm validation failed"**
- Solution: Ensure you built with the correct profile: `stellar contract build --profile release-with-logs`

### Matching Engine Issues

**Error: "Settlement contract ID not configured"**
- Solution: Set `SETTLEMENT_CONTRACT_ID` in your `.env` file

**Error: "Failed to load matching engine account"**
- Solution: Ensure the matching engine account is funded and `MATCHING_ENGINE_SIGNING_KEY` is correct

**Error: "Insufficient vault balance"**
- Solution: Users must deposit funds before trading. Check balance with `get_balance`

### API Issues

**Connection refused on port 8080**
- Solution: Check if matching engine is running: `curl http://localhost:8080/health`

**401 Invalid signature**
- Solution: Ensure orders are properly signed using SEP-0053 format

## Production Readiness

⚠️ **This is experimental software. Use at your own risk.**

See [TODO.md](TODO.md) for the complete list of planned improvements and production checklist.

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed system architecture and design
- [TODO.md](TODO.md) - Planned features and production requirements
- [RESEARCH.md](RESEARCH.md) - Research on hybrid DEX approaches
- [contracts/settlement/README.md](contracts/settlement/README.md) - Contract details
- [matching-engine/README.md](matching-engine/README.md) - Matching engine details
