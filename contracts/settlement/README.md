# Settlement Smart Contract

This directory contains the Soroban smart contract for on-chain settlement.

## Overview

The settlement contract handles:
1. **Vault Management**: User deposits and withdrawals
2. **Balance Tracking**: Internal vault balance tracking per user/token
3. **Settlement Verification**: Matching engine authorization and signature verification
4. **Atomic Settlement**: Balance updates for matched trades
5. **Event Emission**: Deposit, withdrawal, and settlement events
6. **Trade History Storage**: Query settlement and trade history

## Status

✅ **Fully Implemented** - Production-ready vault-based settlement

### Implemented Features
- ✅ Vault model (deposit/withdraw)
- ✅ Stellar Asset Contract (SAC) integration
- ✅ Balance checking and tracking
- ✅ Token transfers (deposit/withdraw)
- ✅ Matching engine authorization
- ✅ Settlement verification and execution
- ✅ Trade history storage
- ✅ Event emission (deposits, withdrawals, settlements)
- ✅ Admin functions (set_matching_engine)

### Future Enhancements
- ⏳ Order signature verification in settle_trade
- ⏳ Fee collection mechanism
- ⏳ Multi-asset settlement optimization

## Contract Structure

```
src/
├── lib.rs          # Main contract entry point
├── types.rs        # Data structures
├── storage.rs      # Persistent storage operations
├── verification.rs # Signature, nonce, commitment verification
├── transfers.rs    # Asset transfer logic
└── events.rs       # Event emission
```

## Contract Functions

### Public Functions

#### Initialization
- `new(admin, token_a, token_b)` - Constructor: Initialize contract with admin and supported tokens

#### Admin Functions
- `set_matching_engine(matching_engine)` - Set authorized matching engine address (admin only)

#### Vault Operations
- `deposit(user, token, amount)` - Deposit tokens into vault (requires prior token approval)
- `withdraw(user, token, amount)` - Withdraw tokens from vault (user only)
- `get_balance(user, token)` - Query user's vault balance for specific token

#### Settlement
- `settle_trade(instruction)` - Settle a matched trade (matching engine only)
  - Verifies matching engine authorization
  - Checks vault balances
  - Updates balances atomically
  - Emits settlement event

#### Query Functions
- `get_settlement(trade_id)` - Get settlement details by trade ID
- `get_trade_history(user, limit)` - Query user's trade history with pagination

## Vault Model

The contract uses a **Vault/Deposit Model** for asset management:
- Users deposit tokens into the contract before trading
- Contract tracks internal vault balances per user/token
- Trades settle instantly by updating vault balances (no user signatures required)
- Users can withdraw funds anytime

### Benefits
- **Instant Settlement**: No waiting for user signatures during trades
- **Guaranteed Execution**: Funds are pre-locked in vault
- **Atomic Updates**: Balance changes are all-or-nothing
- **Gas Efficiency**: Only settlement transactions on-chain, not individual order submissions

See [ARCHITECTURE.md](../../docs/ARCHITECTURE.md#settlement-model-vault-architecture) for detailed vault architecture.

## Development

### Prerequisites
- Stellar SDK
- Soroban CLI (`cargo install --locked soroban-cli`)
- Rust toolchain (nightly)
- wasm32 target: `rustup target add wasm32-unknown-unknown`

### Building

```bash
cd contracts/settlement
stellar contract build --profile release-with-logs --optimize
```

The optimized WASM will be in `target/wasm32v1-none/release-with-logs/settlement.wasm`.

### Unit Testing

```bash
cargo test
```

Tests are located in `src/test.rs` and `src/lib.rs` covering:
- Vault operations (deposit, withdraw, balance checks)
- Settlement execution
- Authorization checks
- Edge cases and error conditions

### Deployment

```bash
stellar contract deploy \
  --wasm target/wasm32v1-none/release-with-logs/settlement.wasm \
  --source test \
  --network testnet \
  -- --admin <ADMIN_ADDRESS> --token_a <TOKEN_A_ID> --token_b <TOKEN_B_ID>
```

**Note:** The contract constructor requires three arguments:
- `admin`: Admin account address
- `token_a`: First supported token contract ID
- `token_b`: Second supported token contract ID

## End-to-End Testing

The `test_contract.sh` script provides a complete end-to-end test:

```bash
cd contracts/settlement
bash test_contract.sh
```

### Environment Variables (Optional)

```bash
export STELLAR_NETWORK=testnet          # or "futurenet", "standalone"
export STELLAR_RPC_URL=https://soroban-testnet.stellar.org
export STELLAR_FRIENDBOT_URL=https://friendbot.stellar.org
```

### What the Test Does

1. Builds and optimizes contract
2. Generates test accounts (admin, buyer, seller) and funds them via Friendbot
3. Deploys contract to testnet with constructor arguments
4. Sets matching engine address
5. Tests deposit operation (1 XLM)
6. Verifies balance after deposit
7. Tests withdraw operation
8. Verifies balance after withdraw
9. Tests `get_settlement()` and `get_trade_history()` query functions

### Manual Testing

```bash
# Set matching engine (admin only)
stellar contract invoke \
  --id <CONTRACT_ID> \
  --source admin \
  --network testnet \
  -- set_matching_engine \
  --matching_engine <MATCHING_ENGINE_ADDRESS>

# Deposit tokens
stellar contract invoke \
  --id <CONTRACT_ID> \
  --source buyer \
  --network testnet \
  -- deposit \
  --user <USER_ADDRESS> \
  --token <TOKEN_CONTRACT_ID> \
  --amount 10000000

# Get vault balance
stellar contract invoke \
  --id <CONTRACT_ID> \
  --source buyer \
  --network testnet \
  -- get_balance \
  --user <USER_ADDRESS> \
  --token <TOKEN_CONTRACT_ID>

# Withdraw tokens
stellar contract invoke \
  --id <CONTRACT_ID> \
  --source buyer \
  --network testnet \
  -- withdraw \
  --user <USER_ADDRESS> \
  --token <TOKEN_CONTRACT_ID> \
  --amount 5000000

# Get trade history
stellar contract invoke \
  --id <CONTRACT_ID> \
  --source admin \
  --network testnet \
  -- get_trade_history \
  --user <USER_ADDRESS> \
  --limit 10
```

### Troubleshooting

- **stellar CLI not found**: Install with `cargo install stellar-cli`
- **Build failed**: Check Rust toolchain and wasm32 target (`rustup target add wasm32-unknown-unknown`)
- **Deployment failed**: Verify network connectivity and account balance (fund via Friendbot)
- **Account funding failed**: Friendbot may be rate-limited, retry after a few seconds
- **Contract not found**: Ensure you're using the correct CONTRACT_ID from deployment output

## Contract Interface

See [ARCHITECTURE.md](../../docs/ARCHITECTURE.md) for detailed interface specifications and vault architecture.
