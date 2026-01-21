# Dark Pool Architecture: Off-Chain Matching with On-Chain Settlement

## Executive Summary

This document describes the architecture and technical design for a dark pool trading system built on Stellar that performs order matching off-chain for privacy and efficiency, while settling all trades on-chain for transparency and finality.

## Design Philosophy

### Core Principles
1.  **Privacy**: Order details remain private until settlement.
2.  **Efficiency**: Minimize on-chain operations and gas costs.
3.  **Transparency**: All settlements are on-chain and auditable.
4.  **Trust Minimization**: Trusted Execution Environments (TEE) ensure matching integrity (see `TEE.md`).
5.  **Scalability**: Off-chain matching enables high throughput.

## System Architecture

### High-Level Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    Client Layer                              │
│  ┌──────────────┐  ┌──────────────┐                          │
│  │  Mobile App  │  │  SDK/API     │                          │
│  └──────────────┘  └──────────────┘                          │
└────────────────────────────┬─────────────────────────────────┘
                             │
                             │ HTTPS/WebSocket
                             ▼
┌─────────────────────────────────────────────────────────────┐
│              Off-Chain Matching Layer (TEE)                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  API Server (REST + WebSocket)                       │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Matching Engine                                      │  │
│  │  - Order Book Manager                                 │  │
│  │  - Matching Algorithm                                 │  │
│  │  - Trade Generator                                    │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  TEE Attestation Service                             │   │
│  │  - Remote Attestation                                │   │
│  │  - Key Binding                                       │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────────────────┬────────────────────────────────┘
                             │
                             │ Stellar Transaction
                             ▼
┌─────────────────────────────────────────────────────────────┐
│              On-Chain Settlement Layer                      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Soroban Smart Contract                              │   │
│  │  - Settlement Verification                           │   │
│  │  - Vault Balance Management                          │   │
│  │  - Asset Transfers (from vault)                      │   │
│  │  - State Management                                  │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Stellar Network                                     │   │
│  │  - Native Asset Support                              │   │
│  │  - Fast Settlement (3-5s)                            │   │
│  │  - Low Fees                                          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### System Flow Diagram

```
┌──────────────┐
│   Trader A   │
│  (Buy Order) │
└──────┬───────┘
       │
       │ 1. Deposit to Contract Vault
       ▼
┌─────────────────────────────────────────────────┐
│      Stellar Network (On-Chain)                  │
│  ┌──────────────────────────────────────────┐   │
│  │  Settlement Contract Vault               │   │
│  │  - User balances tracked                 │   │
│  └──────────────────────────────────────────┘   │
└──────┬──────────────────────────────────────────┘
       │
       │ 2. Submit Order (SEP-0053 Signed)
       ▼
┌─────────────────────────────────────────────────┐
│         Off-Chain Matching Engine               │
│  ┌──────────────────────────────────────────┐   │
│  │  Order Reception & Validation            │   │
│  └──────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────┐   │
│  │  Private Order Book                      │   │
│  │  - Buy Orders                            │   │
│  │  - Sell Orders                           │   │
│  └──────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────┐   │
│  │  Matching Algorithm                      │   │
│  │  - Price-Time Priority                   │   │
│  │  - Continuous Matching                   │   │
│  └──────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────┐   │
│  │  Trade Generation                        │   │
│  │  - Create Trade Records                  │   │
│  └──────────────────────────────────────────┘   │
└──────┬──────────────────────────────────────────┘
       │
       │ 3. Call settle_trade() (Authorized)
       ▼
┌─────────────────────────────────────────────────┐
│      Stellar Network (On-Chain)                 │
│  ┌──────────────────────────────────────────┐   │
│  │  Settlement Smart Contract               │   │
│  │  - Check Vault Balances                  │   │
│  │  - Update Vault Balances                 │   │
│  │  - Emit Events                           │   │
│  └──────────────────────────────────────────┘   │
│                                                 │
│  Vault Balance Updates:                         │
│  Trader A: -quote_asset, +base_asset            │
│  Trader B: -base_asset, +quote_asset            │
└─────────────────────────────────────────────────┘
       │
       │ 4. Settlement Confirmation
       ▼
┌──────────────┐
│   Trader B   │
│ (Sell Order) │
└──────────────┘
```

### Security Layers

```
┌─────────────────────────────────────────────────┐
│  Layer 1: Order Signing                         │
│  - SEP-0053 Cryptographic signatures            │
│  - Prevents tampering                           │
└─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│  Layer 2: TEE Attestation (Planned)             │
│  - Phala Cloud / Intel TDX                      │
│  - Code Integrity & Key Binding                 │
│  - See TEE.md                                   │
└─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│  Layer 3: On-Chain Verification                 │
│  - Authorized Matcher Only                      │
│  - Vault balance checks                         │
│  - Atomic balance updates                       │
└─────────────────────────────────────────────────┘
```

## Component Details

### 1. Client Layer

#### Responsibilities
- Order management (create, cancel, modify)
- Trade history and portfolio tracking
- API/SDK for programmatic access

#### Order Submission Flow
1. User creates order (price, quantity, side, time-in-force)
2. Client signs order using **SEP-0053** (Stellar Signed Message)
3. Order sent to matching engine via secure channel (HTTPS)

### 2. Off-Chain Matching Layer

#### Matching Engine

**Architecture:**

The matching engine operates as a trusted service, ideally within a TEE:
- Single entity operates matching engine
- Faster implementation
- Trust established via TEE Attestation (see `TEE.md`)

**Core Functions:**
1. **Order Reception**
   - Receive signed orders
   - Validate SEP-0053 signatures
   - Check order constraints (price, quantity, time-in-force)
   - Store in private order book

2. **Order Book Management**
   - Maintain separate buy/sell order books
   - Price-time priority matching
   - Handle order modifications and cancellations

3. **Matching Algorithm**
   - Continuous matching (as orders arrive)
   - Price-time priority
   - Partial fills supported

4. **Trade Generation**
   - Create trade records for matched orders
   - Generate settlement instructions

#### TEE Integration
*See `TEE.md` for full implementation details.*

**Purpose**: Ensure matching integrity and that the code running is exactly what was audited.

**Components:**
1. **Remote Attestation**
   - Prove code identity and hardware authenticity
2. **Key Binding**
   - Bind TLS and Stellar signing keys to the TEE instance
   - Users can verify they are talking to the genuine enclave

### 3. On-Chain Settlement Layer

#### Stellar Smart Contract

**Responsibilities:**
1. **Settlement Verification**
   - Check user balances in vault
   - Verify caller is authorized matching engine

2. **Asset Transfers**
   - Update vault balances atomically
   - Support multi-asset settlements

3. **State Management**
   - Track settled trades
   - Maintain user balances
   - Emit events for indexing

## Settlement Model: Vault Architecture

### Overview

The dark pool uses a **deposit/vault model** where clients deposit funds into the contract before trading. This design enables instant, guaranteed settlement without requiring user signatures for each trade.

### Vault Flow

```
┌─────────────────────────────────────────────────────┐
│  1. SETUP PHASE                                     │
│                                                     │
│  User → Approve Contract (one-time per token)       │
│  User → Deposit(token, amount)                      │
│  Contract → Track balance in vault                  │
└─────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────┐
│  2. TRADING PHASE                                   │
│                                                     │
│  User → Submit Order (SEP-0053 signed, off-chain)   │
│  Matching Engine → Match orders (private)           │
│  Matching Engine → settle_trade() (authorized)      │
│  Contract → Update vault balances (atomic)          │
└─────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────┐
│  3. WITHDRAWAL PHASE                                │
│                                                     │
│  User → Withdraw(token, amount)                     │
│  Contract → Transfer from vault to user             │
│  Contract → Update vault balance                    │
└─────────────────────────────────────────────────────┘
```

### Contract Functions

#### Initialization
- **Constructor**: Initialize contract with admin address
- **Set Matching Engine**: Register authorized matching engine

#### Vault Operations
- **Deposit**: User deposits tokens into contract vault
- **Withdraw**: User withdraws tokens from vault
- **Get Balance**: Query user's vault balance

#### Settlement
- **Settle Trade**: Authorized matching engine only. Verifies balances, updates them atomically. Emits `SettlementEvent`.

### Matching Engine Authorization

The matching engine must be registered before it can settle trades:

```bash
# Admin registers matching engine (one-time)
soroban contract invoke \
  --id $CONTRACT_ID \
  --source-account $ADMIN \
  -- set_matching_engine \
  --matching_engine $MATCHING_ENGINE_ADDRESS
```

### Settlement Process Detail

When orders match, the matching engine:

1. **Prepares Settlement Instruction**
   - Creates settlement instruction with trade ID, buyer/seller addresses, asset addresses, amounts.

2. **Calls Contract via Soroban RPC**
   ```python
   # Matching engine submits transaction
   response = soroban_server.prepare_transaction(
       build_settle_trade_tx(instruction)
   )
   ```

3. **Contract Executes Settlement**
   - Checks vault balances
   - Updates balances atomically
   - Emits settlement event

### Trade-offs

**Advantages:**
- ✅ Instant settlement
- ✅ Guaranteed execution
- ✅ Simplified matching engine logic
- ✅ Atomic balance updates

**Disadvantages:**
- ❌ Users must trust contract custody
- ❌ Funds locked until withdrawal
- ❌ Requires trusted or TEE-verified matcher

## Data Structures

### Order Structure

An order contains:
- Unique order identifier
- User's Stellar account address
- Asset pair (base and quote assets)
- Side (Buy or Sell)
- Order type (Limit, Market)
- Price
- Quantity
- Time in force
- Timestamp
- SEP-0053 Signature

### Trade Structure

A trade record contains:
- Trade ID
- Buy and sell order IDs
- Execution price and quantity
- Buyer and seller addresses
- Asset pair
- Timestamp

### Settlement Instruction

A settlement instruction contains:
- Trade ID
- Buyer and seller addresses
- Base and quote asset addresses
- Base and quote amounts
- Timestamp

## Matching Engine Design

### Order Book Data Structure

The order book maintains price-time priority:
- Buy orders sorted by descending price
- Sell orders sorted by ascending price
- Orders at the same price sorted by time (FIFO)

## API Design

### REST API Endpoints

```
POST   /api/v1/orders              # Submit order
DELETE /api/v1/orders/:id          # Cancel order
GET    /api/v1/orders/:id          # Get order status
GET    /api/v1/orderbook/:pair     # Get order book snapshot
GET    /health                     # Health check
GET    /api/v1/attestation         # (Planned) Get TEE Attestation
```

## Security

### Order Signing

Orders are cryptographically signed using **SEP-0053 (Stellar Signed Message)**.
- Prevents replay attacks and tampering.
- Ensures non-repudiation.

### Security Measures

1. **SEP-0053 Signatures**: Standardized off-chain signing.
2. **TEE (Planned)**: Hardware-enforced code integrity (see `TEE.md`).
3. **On-Chain Verification**: Settlements controlled by authorized address (which is bound to TEE).

## Technology Stack

**Off-Chain Matching:**
- Language: Python (FastAPI)
- Cryptography: SEP-0053 via stellar-sdk
- Transaction Submission: Soroban RPC

**On-Chain Settlement:**
- Smart Contract: Soroban (Rust)

**Client Layer:**
- SDK: TypeScript/JavaScript, Python

## Comparison with Existing Solutions

| Feature | Hyperliquid/Serum/Econia | Proposed Dark Pool |
|---------|--------------------------|-------------------|
| Order Visibility | Public (on-chain) | Private (off-chain) |
| Matching Location | On-chain | Off-chain (TEE) |
| Settlement | On-chain | On-chain |
| Privacy | None | High |
| Gas Costs | High | Low |
| Throughput | Limited by chain | High |

## Future Enhancements

1. **TEE Integration**
   - See `TEE.md` for the detailed implementation plan using Phala Cloud.

2. **Advanced Order Types**
   - Iceberg orders
   - TWAP/VWAP orders

3. **Cross-Chain Settlement**
   - Atomic swaps for cross-chain trades