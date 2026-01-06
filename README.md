# Stellar Dark Pool

A decentralized dark pool on Stellar, featuring privacy-preserving order matching and on-chain settlement.

## Overview

The Stellar Dark Pool is a prototype for privacy-preserving trading on Stellar. Orders are matched off-chain in a private matching engine, keeping trading intentions hidden until execution. Once matched, trades settle transparently on the Stellar network. Users deposit funds into the contract ahead of time, enabling instant settlement.

## Key Features

- **Privacy**: Orders remain private until settlement
- **Automatic Settlement**: Trades settle on-chain immediately after matching
- **Vault Model**: Users deposit assets into the contract; trades settle against vault balances
- **Order Integrity**: SEP-0053 signatures ensure orders cannot be forged
- **Instant Settlement**: Pre-locked funds enable guaranteed settlement
- **Price-Time Priority**: Fair matching with FIFO ordering at each price level
- **Soroban-native**: Uses only Soroban RPC (no Horizon dependency)

## Project Structure

- **contracts/settlement**: Soroban smart contract for trade settlement and vault management
- **matching-engine**: Python-based off-chain matching engine with REST API
- **scripts**: Utility scripts for order signing and testing

## Quick Start

### Prerequisites

```bash
# Install Stellar CLI
cargo install stellar-cli --locked

# Add Rust wasm target
rustup target add wasm32-unknown-unknown

# Verify installations
stellar --version && rustc --version && python3 --version
```

### Deploy Contract

```bash
cd contracts/settlement
stellar contract build --profile release-with-logs --optimize

# Generate and fund admin account
stellar keys generate admin --network testnet
curl "https://friendbot.stellar.org?addr=$(stellar keys address admin)"

# Deploy (replace TOKEN_IDs with actual contract IDs)
stellar contract deploy \
  --wasm target/wasm32v1-none/release-with-logs/settlement.wasm \
  --source admin \
  --network testnet \
  -- \
  --admin $(stellar keys address admin) \
  --token_a <TOKEN_A_CONTRACT_ID> \
  --token_b <TOKEN_B_CONTRACT_ID>
```

### Start Matching Engine

```bash
cd matching-engine
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Configure .env (see matching-engine/README.md)
python -m src.main
```

For a complete step-by-step walkthrough, see **[TUTORIAL.md](TUTORIAL.md)**.

## Usage

### Deposit Funds

```bash
stellar contract invoke \
  --id $SETTLEMENT_CONTRACT_ID \
  --source trader1 \
  --network testnet \
  -- deposit \
  --user $TRADER_ADDRESS \
  --token $TOKEN_ID \
  --amount 1000000000
```

### Submit Orders

Orders must be signed using SEP-0053:

```bash
# Sign order
SIGNATURE=$(python3 scripts/sign_order.py "$SECRET_KEY" "$ORDER_JSON")

# Submit to matching engine
curl -X POST http://localhost:8080/api/v1/orders \
  -H "Content-Type: application/json" \
  -d "$ORDER_WITH_SIGNATURE"
```

### View Order Book

```bash
curl http://localhost:8080/api/v1/orderbook/XLM/USDC
```

## API Reference

| Endpoint | Description |
|----------|-------------|
| `POST /api/v1/orders` | Submit order (auto-settles on match) |
| `GET /api/v1/orders/{id}` | Get order status |
| `DELETE /api/v1/orders/{id}` | Cancel order |
| `GET /api/v1/orderbook/{pair}` | Get order book (top 20 levels) |
| `GET /api/v1/balances` | Query vault balance |
| `GET /health` | Health check |

See [matching-engine/README.md](matching-engine/README.md) for detailed API documentation.

## Testing

### End-to-End Tests

Two E2E test scripts are available:

**Docker-based (Recommended)**:
```bash
./test_e2e_docker.sh
```
- Uses Docker container for matching engine
- No Python environment setup required
- Automatic keypair generation
- Matches production deployment pattern

**Python-based**:
```bash
./test_e2e_full.sh
```
- Runs matching engine as local Python process
- Requires Python venv setup
- Uses Stellar CLI key aliases

### Unit Tests

```bash
# Contract tests
cd contracts/settlement && cargo test

# Matching engine tests
cd matching-engine && source venv/bin/activate && pytest
```

## Troubleshooting

| Error | Solution |
|-------|----------|
| "account not found" | Fund via Friendbot: `curl "https://friendbot.stellar.org?addr=ADDRESS"` |
| "wasm validation failed" | Build with correct profile: `stellar contract build --profile release-with-logs` |
| "Settlement contract ID not configured" | Set `SETTLEMENT_CONTRACT_ID` in `.env` |
| "Insufficient vault balance" | Deposit funds before trading |
| Connection refused on 8080 | Start matching engine: `python -m src.main` |
| "401 Invalid signature" | Ensure orders use SEP-0053 signing format |

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - System design and architecture
- [TUTORIAL.md](TUTORIAL.md) - Complete step-by-step walkthrough
- [TODO.md](TODO.md) - Planned features and production checklist
- [RESEARCH.md](RESEARCH.md) - Research on hybrid DEX approaches
- [contracts/settlement/README.md](contracts/settlement/README.md) - Contract details
- [matching-engine/README.md](matching-engine/README.md) - Matching engine API docs

---

**This is experimental software. Use at your own risk.** See [TODO.md](TODO.md) for production requirements.
