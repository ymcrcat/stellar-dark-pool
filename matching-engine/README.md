# Stellar Dark Pool Matching Engine (Python)

A Python implementation of the matching engine for the Stellar Dark Pool, rewritten from the original Rust implementation. It provides a REST API for order submission, matching, and settlement integration with the Stellar Soroban contract.

## Features

- **Order Matching**: Supports Limit and Market orders with time-in-force policies (GTC, IOC, FOK).
- **Soroban Integration**: Directly interacts with the Settlement Contract on Soroban for vault balance checks and settlement submission.
- **No Horizon Dependency**: Uses Soroban RPC for all blockchain interactions.
- **SEP-0053 Support**: Implements Stellar Signed Messages for secure order authentication.
- **API Compatible**: Provides the same REST API endpoints as the Rust implementation.

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
   Edit `.env` and set your configuration:
   ```bash
   SETTLEMENT_CONTRACT_ID=<YOUR_CONTRACT_ID>
   MATCHING_ENGINE_SIGNING_KEY=<YOUR_SECRET_KEY>
   # Adjust other settings as needed
   ```

3. **Build and run with Docker Compose** (from project root):
   ```bash
   cd ..
   docker-compose up -d
   ```

4. **Check logs**:
   ```bash
   docker-compose logs -f matching-engine
   ```

5. **Stop the service**:
   ```bash
   docker-compose down
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

- `POST /api/v1/orders`: Submit an order
- `GET /api/v1/orders/{id}`: Get order status
- `DELETE /api/v1/orders/{id}`: Cancel an order
- `GET /api/v1/orderbook/{pair}`: Get order book snapshot
- `GET /api/v1/balances`: Check vault balance
- `POST /api/v1/settlement/submit`: Submit a settlement instruction
