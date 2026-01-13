# Stellar Dark Pool Matching Engine (Python)

A Python implementation of the matching engine for the Stellar Dark Pool, rewritten from the original Rust implementation. It provides a REST API for order submission, matching, and settlement integration with the Stellar Soroban contract.

## Features

- **Order Matching**: Supports Limit and Market orders with time-in-force policies (GTC, IOC, FOK).
- **Soroban Integration**: Directly interacts with the Settlement Contract on Soroban for vault balance checks and settlement submission.
- **SEP-0053 Support**: Implements Stellar Signed Messages for secure order authentication.

## Docker Deployment (Recommended)

### Prerequisites
- Docker Engine 20.10+
- Docker Compose 2.0+

### Quick Start

1. **Copy environment template**:
   ```bash
   cp .env.example .env
   ```

2. **Configure environment variables**:
   Edit `.env` and set your settlement contract ID:
   ```bash
   SETTLEMENT_CONTRACT_ID=<YOUR_CONTRACT_ID>
   # Other settings use sensible defaults
   ```

3. **Build and run with Docker Compose** (from project root):
   ```bash
   cd ..
   docker-compose up -d
   ```

4. **Check logs to see the generated keypair**:
   ```bash
   docker-compose logs matching-engine
   ```
   The container automatically generates a new Stellar keypair on startup and displays the public key.

5. **Stop the service**:
   ```bash
   docker-compose down
   ```

### Automatic Key Generation

**When running in Docker**, the matching engine ALWAYS generates an ephemeral Stellar keypair at container startup. This keypair is:

- ✅ **Ephemeral**: Regenerated on each container restart
- ✅ **Automatic**: No manual key management needed
- ✅ **Logged**: Public key displayed in container logs for funding/authorization

**Important Notes:**
- Keys are automatically generated and cannot be overridden
- Perfect for **development, testing, and stateless deployments**
- Each container restart generates a new keypair
- Don't forget to **fund** and **authorize** the generated address in your settlement contract

**To fund and authorize the auto-generated key:**
```bash
# 1. Get the public key from logs
docker-compose logs matching-engine | grep "Public Key"

# 2. Fund via Friendbot (testnet)
curl "https://friendbot.stellar.org/?addr=<PUBLIC_KEY>"

# 3. Authorize in settlement contract
stellar contract invoke --id $SETTLEMENT_CONTRACT_ID \
  --source admin --network testnet -- \
  set_matching_engine --matching_engine <PUBLIC_KEY>
```

### Docker Commands

**Build image manually**:
```bash
docker build -t stellar-darkpool-matching-engine:latest .
```

**Run container manually**:
```bash
docker run -d \
  --name matching-engine \
  -p 8080:8080 \
  --env-file .env \
  stellar-darkpool-matching-engine:latest
```

**View logs**:
```bash
docker logs -f matching-engine
```

**Access container shell** (for debugging):
```bash
docker exec -it matching-engine bash
```

## Local Development Setup

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

- `POST /api/v1/orders`: Submit an order (automatically settles if matched)
- `GET /api/v1/orders/{id}`: Get order status
- `DELETE /api/v1/orders/{id}`: Cancel an order
- `GET /api/v1/orderbook/{pair}`: Get order book snapshot
- `GET /api/v1/balances`: Check vault balance
- `GET /health`: Health check

**Note:** Settlement happens automatically when orders match - no manual settlement endpoint.
