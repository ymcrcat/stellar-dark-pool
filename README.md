# Stellar Dark Pool

A decentralized dark pool on Stellar, featuring privacy-preserving order matching and on-chain settlement.

## Project Structure

- **contracts/settlement**: Soroban smart contract for trade settlement and vault management.
- **matching-engine**: Python-based off-chain matching engine.

## Prerequisites

- Python 3.10+
- Rust & Soroban CLI (for contract development)

## Getting Started

### Matching Engine (Python)

```bash
cd matching-engine
pip install -r requirements.txt
python -m src.main
```

See [matching-engine/README.md](matching-engine/README.md) for details.

### Settlement Contract

```bash
cd contracts/settlement
stellar contract build
```

## Architecture

1. **Orders**: Users sign orders (SEP-0053) and submit them to the Matching Engine.
2. **Matching**: The engine matches orders off-chain.
3. **Settlement**: The engine submits matched trades to the Soroban contract.
4. **Vaults**: The contract manages user balances (vaults) and settles trades atomically.

## Key Features

- **Soroban-only**: No dependency on Horizon API for the matching engine.
- **Vault Model**: Users deposit assets into the contract; trades settle against these balances.
- **Order Integrity**: SEP-0053 signatures ensure orders cannot be forged.
