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

Orders must be signed using SEP-0053. Use the provided script:

```bash
# Create a buy order
python ../scripts/sign_order.py \
  --keypair trader1 \
  --side Buy \
  --price 0.12 \
  --quantity 100 \
  --base XLM \
  --quote USDC

# This will output a signed order JSON that you can POST to /api/v1/orders
```

Or submit directly via API:
```bash
curl -X POST http://localhost:8080/api/v1/orders \
  -H "Content-Type: application/json" \
  -d '{
    "user_address": "'$TRADER1_ADDRESS'",
    "asset_pair": {"base": "XLM", "quote": "USDC"},
    "side": "Buy",
    "order_type": "Limit",
    "price": "0.12",
    "quantity": "100",
    "time_in_force": "GTC",
    "signature": "<SEP-0053_signature>"
  }'
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
6. Verifies settlement on-chain

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
