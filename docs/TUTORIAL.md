# Stellar Dark Pool Tutorial

A complete step-by-step walkthrough to deploy and test the dark pool from scratch.

## Prerequisites

Before starting, ensure you have completed the basic setup:

- **Stellar CLI** installed: `stellar --version`
- **Rust** with wasm32 target: `rustup target add wasm32-unknown-unknown`
- **Python 3.10+** with venv
- **curl & jq** for API interactions

## Step 1: Deploy the Settlement Contract

### 1.1 Build the Contract

```bash
cd contracts/settlement
stellar contract build --profile release-with-logs --optimize
```

### 1.2 Generate Admin Account

```bash
stellar keys generate admin --network testnet
export ADMIN_ADDRESS=$(stellar keys address admin)
curl "https://friendbot.stellar.org?addr=$ADMIN_ADDRESS"
```

### 1.3 Get Token Contract ID

```bash
export TOKEN_ID=$(stellar contract id asset --asset native --network testnet)
echo "Token ID: $TOKEN_ID"
```

### 1.4 Deploy Contract

```bash
stellar contract deploy \
  --wasm target/wasm32v1-none/release-with-logs/settlement.wasm \
  --source admin \
  --network testnet \
  -- \
  --admin $ADMIN_ADDRESS \
  --token_a $TOKEN_ID \
  --token_b $TOKEN_ID

# Save the contract ID from output
export SETTLEMENT_CONTRACT_ID=<contract_id_from_output>
```

## Step 2: Configure the Matching Engine

### 2.1 Generate Matching Engine Keypair

```bash
stellar keys generate matching-engine --network testnet
export MATCHING_ENGINE_ADDRESS=$(stellar keys address matching-engine)
curl "https://friendbot.stellar.org?addr=$MATCHING_ENGINE_ADDRESS"
```

### 2.2 Authorize in Contract

```bash
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source admin \
  --network testnet \
  -- set_matching_engine \
  --matching_engine $MATCHING_ENGINE_ADDRESS
```

### 2.3 Create Configuration

```bash
cd matching-engine
export MATCHING_ENGINE_SECRET=$(stellar keys show matching-engine)

cat > .env << EOF
STELLAR_NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
SOROBAN_RPC_URL="https://soroban-testnet.stellar.org"
SETTLEMENT_CONTRACT_ID="$SETTLEMENT_CONTRACT_ID"
MATCHING_ENGINE_SIGNING_KEY="$MATCHING_ENGINE_SECRET"
REST_PORT=8080
EOF
```

### 2.4 Install Dependencies and Start

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python -m src.main
```

## Step 3: Verify Setup

```bash
curl http://localhost:8080/health
```

**Expected output:**
```json
{"status":"healthy","timestamp":1234567890}
```

## Step 4: Create Test Trader Accounts

```bash
# Create buyer account
stellar keys generate buyer --network testnet
export BUYER_ADDRESS=$(stellar keys address buyer)
curl "https://friendbot.stellar.org?addr=$BUYER_ADDRESS"

# Create seller account
stellar keys generate seller --network testnet
export SELLER_ADDRESS=$(stellar keys address seller)
curl "https://friendbot.stellar.org?addr=$SELLER_ADDRESS"

# Wait for funding
sleep 5
```

## Step 5: Deposit Funds into Vault

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

**Verify deposits:**
```bash
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source buyer \
  --network testnet \
  -- get_balance \
  --user $BUYER_ADDRESS \
  --token $TOKEN_ID
# Should output: 1000000000
```

## Step 6: Submit a Buy Order

Get secret keys and check the order book:

```bash
export BUYER_SECRET=$(stellar keys show buyer)
export SELLER_SECRET=$(stellar keys show seller)

# Verify order book is empty
curl http://localhost:8080/api/v1/orderbook/XLM/XLM | jq
```

Create and submit a buy order:

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

# Sign and submit
BUY_SIGNATURE=$(python3 scripts/sign_order.py "$BUYER_SECRET" "$BUY_ORDER")
BUY_REQUEST=$(echo "$BUY_ORDER" | jq --arg sig "$BUY_SIGNATURE" '. + {signature: $sig}')

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

## Step 7: Submit a Matching Sell Order

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

# Sign and submit
SELL_SIGNATURE=$(python3 scripts/sign_order.py "$SELLER_SECRET" "$SELL_ORDER")
SELL_REQUEST=$(echo "$SELL_ORDER" | jq --arg sig "$SELL_SIGNATURE" '. + {signature: $sig}')

curl -X POST http://localhost:8080/api/v1/orders \
  -H "Content-Type: application/json" \
  -d "$SELL_REQUEST" | jq
```

**Expected output (orders matched!):**
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
      ...
    }
  ]
}
```

Settlement happens automatically! Check the matching engine logs for the transaction hash.

## Step 8: Verify Settlement

Wait for settlement to complete:
```bash
sleep 10
```

Check balances changed:
```bash
# Buyer balance (should show change)
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source buyer \
  --network testnet \
  -- get_balance \
  --user $BUYER_ADDRESS \
  --token $TOKEN_ID

# Seller balance (should show change)
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source seller \
  --network testnet \
  -- get_balance \
  --user $SELLER_ADDRESS \
  --token $TOKEN_ID
```

Verify the order book is cleared:
```bash
curl http://localhost:8080/api/v1/orderbook/XLM/XLM | jq
```

## Success!

You've successfully:
- Deployed the settlement contract
- Started the matching engine
- Created trader accounts and deposited funds
- Submitted buy and sell orders
- Matched orders off-chain
- Automatically settled the trade on-chain
- Verified balances updated correctly

## Next Steps

- Try creating orders at different prices to see the order book build up
- Submit orders that partially fill
- Test order cancellation with `DELETE /api/v1/orders/{id}`
- Try different asset pairs (deploy custom tokens)
- Test withdrawal functionality
