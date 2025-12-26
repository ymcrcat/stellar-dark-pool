# Stellar Dark Pool Matching Engine (Python)

A Python implementation of the matching engine for the Stellar Dark Pool, rewritten from the original Rust implementation. It provides a REST API for order submission, matching, and settlement integration with the Stellar Soroban contract.

## Features

- **Order Matching**: Supports Limit and Market orders with time-in-force policies (GTC, IOC, FOK).
- **Soroban Integration**: Directly interacts with the Settlement Contract on Soroban for vault balance checks and settlement submission.
- **No Horizon Dependency**: Uses Soroban RPC for all blockchain interactions.
- **SEP-0053 Support**: Implements Stellar Signed Messages for secure order authentication.
- **API Compatible**: Provides the same REST API endpoints as the Rust implementation.

## Setup

1. **Install Dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

2. **Configuration**:
   Create a `.env` file or set environment variables:
   ```bash
   STELLAR_NETWORK_PASSPHRASE="Test SDF Network ; September 2015"
   SOROBAN_RPC_URL="https://soroban-testnet.stellar.org"
   SETTLEMENT_CONTRACT_ID="<YOUR_CONTRACT_ID>"
   MATCHING_ENGINE_SIGNING_KEY="<YOUR_SECRET_KEY>"
   REST_PORT=8080
   ```

3. **Run**:
   ```bash
   python -m src.main
   ```

## API Endpoints

- `POST /api/v1/orders`: Submit an order
- `GET /api/v1/orders/{id}`: Get order status
- `DELETE /api/v1/orders/{id}`: Cancel an order
- `GET /api/v1/orderbook/{pair}`: Get order book snapshot
- `GET /api/v1/balances`: Check vault balance
- `POST /api/v1/settlement/submit`: Submit a settlement instruction
