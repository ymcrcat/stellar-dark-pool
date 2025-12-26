# Dark Pool Architecture: Off-Chain Matching with On-Chain Settlement

## Executive Summary

This document describes the architecture and technical design for a dark pool trading system built on Stellar that performs order matching off-chain for privacy and efficiency, while settling all trades on-chain for transparency and finality.

## Design Philosophy

### Core Principles
1. **Privacy**: Order details remain private until settlement
2. **Efficiency**: Minimize on-chain operations and gas costs
3. **Transparency**: All settlements are on-chain and auditable
4. **Trust Minimization**: Cryptographic proofs ensure matching integrity
5. **Scalability**: Off-chain matching enables high throughput

## System Architecture

### High-Level Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    Client Layer                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │  Web UI      │  │  Mobile App  │  │  SDK/API     │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
└────────────────────────────┬─────────────────────────────────┘
                             │
                             │ HTTPS/WebSocket
                             ▼
┌─────────────────────────────────────────────────────────────┐
│              Off-Chain Matching Layer                       │
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
│  │  Proof Generator                                     │   │
│  │  - Matching Proof Generation                         │   │
│  │  - Commitment Generation                             │   │
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
       │ 2. Submit Order (Signed)
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
│  │  - Generate Matching Proofs              │   │
│  └──────────────────────────────────────────┘   │
└──────┬──────────────────────────────────────────┘
       │
       │ 3. Call settle_trade() (Authorized)
       ▼
┌─────────────────────────────────────────────────┐
│      Stellar Network (On-Chain)                 │
│  ┌──────────────────────────────────────────┐   │
│  │  Settlement Smart Contract               │   │
│  │  - Verify Matching Proof                 │   │
│  │  - Verify Order Commitments              │   │
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

### Data Flow

```
┌─────────────────┐
│  Order Data     │
│  - Price        │
│  - Quantity     │
│  - Side         │
│  - Signature    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐      ┌─────────────────┐
│  Order Book     │      │  Commitments    │
│  (Private)      │      │  (On-Chain)     │
│  - Full Details │      │  - Hash Only    │
└────────┬────────┘      └─────────────────┘
         │
         ▼
┌─────────────────┐
│  Matched Trade  │
│  - Execution    │
│  - Proof        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Settlement     │
│  (On-Chain)     │
│  - Full Details │
│  - Public       │
│  - Vault Updates│
└─────────────────┘
```

### Security Layers

```
┌─────────────────────────────────────────────────┐
│  Layer 1: Order Signing                         │
│  - Cryptographic signatures                     │
│  - Prevents tampering                           │
└─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│  Layer 2: Order Commitments                     │
│  - Hash-based commitments                       │
│  - Non-repudiation                              │
└─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│  Layer 3: Matching Proofs                       │
│  - Order commitments                            │
│  - Execution records                            │
│  - Future: TEE attestation                      │
└─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│  Layer 4: On-Chain Verification                 │
│  - Proof verification                           │
│  - Vault balance checks                         │
│  - Atomic balance updates                       │
└─────────────────────────────────────────────────┘
```

## Component Details

### 1. Client Layer

#### Responsibilities
- User interface for order submission
- Order management (create, cancel, modify)
- Trade history and portfolio tracking
- API/SDK for programmatic access

#### Order Submission Flow
1. User creates order (price, quantity, side, time-in-force)
2. Client signs order with user's private key
3. Order sent to matching engine via encrypted channel
4. Order commitment hash posted on-chain (optional, for non-repudiation)

### 2. Off-Chain Matching Layer

#### Matching Engine

**Architecture:**

The matching engine operates as a trusted service:
- Single entity operates matching engine
- Faster implementation
- Requires trust in operator
- Can be made transparent through open-source code and audits

**Core Functions:**
1. **Order Reception**
   - Receive encrypted/signed orders
   - Validate order signatures
   - Check order constraints (price, quantity, time-in-force)
   - Store in private order book

2. **Order Book Management**
   - Maintain separate buy/sell order books
   - Price-time priority matching
   - Handle order modifications and cancellations
   - Expire orders based on time-in-force

3. **Matching Algorithm**
   - Continuous matching (as orders arrive)
   - Periodic batching (match at intervals)
   - Price-time priority
   - Partial fills supported

4. **Trade Generation**
   - Create trade records for matched orders
   - Calculate execution prices
   - Generate settlement instructions

#### Cryptographic Proofs

**Purpose**: Ensure matching integrity without revealing order details

**Components:**
1. **Order Commitments**
   - Hash of order details (price, quantity, side, timestamp)
   - Posted on-chain for non-repudiation
   - Revealed only when trade is settled

2. **Matching Proofs**
   - Matching record with order commitments
   - Verifies price-time priority was respected
   - Records execution details for auditability
   - Future: TEE will provide additional integrity guarantees

3. **Settlement Instructions**
   - Settlement details for on-chain contract
   - Includes asset transfers, fees, participants

### 3. On-Chain Settlement Layer

#### Stellar Smart Contract

**Responsibilities:**
1. **Settlement Verification**
   - Verify matching proofs
   - Validate order commitments
   - Check user balances and allowances
   - Verify asset permissions

2. **Asset Transfers**
   - Execute asset swaps via Stellar's native asset system
   - Handle Stellar Asset Contract (SAC) tokens
   - Support multi-asset settlements

3. **State Management**
   - Track settled trades
   - Maintain user balances
   - Record fees and distributions
   - Emit events for indexing

4. **Dispute Resolution**
   - Handle settlement failures
   - Process refunds if needed
   - Maintain audit trail

## Settlement Model: Vault Architecture

### Overview

The dark pool uses a **deposit/vault model** where clients deposit funds into the contract before trading. This design enables instant, guaranteed settlement without requiring user signatures for each trade.

### Architecture Benefits

**Simplicity:**
- No complex transaction construction per trade
- No payment operations in settlement transactions
- Contract handles all balance updates internally

**Security:**
- On-chain balance verification before matching
- Atomic settlement (all-or-nothing)
- No failed settlements due to insufficient balance

**Performance:**
- Instant settlement (no waiting for user signatures)
- Guaranteed execution (funds already locked in vault)
- Higher throughput (matching engine calls contract directly)

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
│  User → Submit Order (signed, off-chain)            │
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
- **Constructor**: Initialize contract with admin address (called once during deployment)
- **Set Matching Engine**: Register authorized matching engine (admin-only function). Only the registered matching engine can call `settle_trade()`

#### Vault Operations
- **Deposit**: User deposits tokens into contract vault. User must approve contract first. Updates user's vault balance and emits `DepositEvent`
- **Withdraw**: User withdraws tokens from vault. Transfers tokens from contract to user, updates vault balance, and emits `WithdrawEvent`
- **Get Balance**: Query user's vault balance for specific asset (read-only, no state changes)

#### Settlement
- **Settle Trade**: Authorized callers only (matching engine or users). Verifies proofs and signatures, checks vault balances (not account balances), updates vault balances atomically. No external transfers during settlement. Emits `SettlementEvent` and returns settlement confirmation

#### Query Functions
- **Get Settlement**: Query settlement details by trade ID
- **Get Trade History**: Query user's trade history with pagination
- **Post Commitment**: Optional function to post order commitment for non-repudiation

### User Journey

#### 1. Setup (One-Time)
1. Approve contract to spend tokens
   ```typescript
   await tokenContract.approve(settlementContract, amount);
   ```
2. Deposit funds into vault
   ```typescript
   await settlementContract.deposit(token, amount);
   ```
3. Check balance
   ```typescript
   const balance = await settlementContract.get_balance(user, token);
   ```

#### 2. Trading (Automatic)
1. Submit signed order to matching engine
   ```typescript
   const order = await createSignedOrder(keypair, orderData);
   await fetch('/api/v1/orders', { method: 'POST', body: JSON.stringify(order) });
   ```
2. Matching engine matches orders off-chain (private)
3. Matching engine calls `settle_trade()` on contract (authorized)
4. Contract updates vault balances atomically
5. User receives trade notification with settlement hash

#### 3. Withdrawal (Anytime)
1. Withdraw unused funds
   ```typescript
   await settlementContract.withdraw(token, amount);
   ```

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

Once registered, the matching engine can:
- Call `settle_trade()` directly
- Update vault balances
- Process settlements without user interaction

### Settlement Process Detail

When orders match, the matching engine:

1. **Prepares Settlement Instruction**
   - Creates settlement instruction with trade ID, buyer/seller addresses, asset addresses, amounts, and matching proof

2. **Calls Contract via Soroban RPC**
   ```python
   # Matching engine submits transaction
   response = soroban_server.prepare_transaction(
       build_settle_trade_tx(instruction)
   )
   ```

3. **Contract Executes Settlement**
   - Verifies matching proof and signatures
   - Checks vault balances (buyer must have sufficient quote asset, seller must have sufficient base asset)
   - Updates balances atomically (buyer receives base asset and pays quote asset, seller receives quote asset and pays base asset)
   - Emits settlement event
   - Returns transaction hash

4. **Settlement Complete**
   - All changes finalized on-chain
   - Trade history recorded
   - Users can query settlement details

### Trade-offs

**Advantages:**
- ✅ Instant settlement (no user signature delay)
- ✅ Guaranteed execution (funds pre-locked)
- ✅ Simplified matching engine logic
- ✅ Atomic balance updates (no partial failures)
- ✅ Higher throughput (direct contract calls)

**Disadvantages:**
- ❌ Users must trust contract custody
- ❌ Funds locked until withdrawal
- ❌ Requires initial deposit step
- ❌ Contract security critical (holds user funds)

### Security Considerations

1. **Contract Custody**: Users must trust contract security
   - Mitigation: Thorough audits, open-source code, battle-tested patterns

2. **Matching Engine Authorization**: Only authorized engine can settle
   - Mitigation: Admin controls, transparent registration process

3. **Balance Verification**: Contract checks balances before settlement
   - Mitigation: Atomic operations, no partial updates

4. **Withdrawal Security**: Users can withdraw anytime
   - Mitigation: Standard access control, user-only withdrawals

### Events

All vault and settlement operations emit events for off-chain indexing:

- **DepositEvent**: Contains user address, token address, and deposit amount
- **WithdrawEvent**: Contains user address, token address, and withdrawal amount
- **SettlementEvent**: Contains trade ID, buyer/seller addresses, asset addresses, amounts, execution price/quantity, and timestamp

These events enable:
- Real-time trade monitoring
- Portfolio tracking
- Historical analysis
- Audit trails

## Data Structures

### Order Structure

An order contains:
- Unique order identifier
- User's Stellar account address
- Asset pair (base and quote assets)
- Side (Buy or Sell)
- Order type (Limit, Market, etc.)
- Price (for limit orders)
- Quantity
- Filled quantity
- Time in force (GTC, IOC, FOK)
- Creation timestamp
- Optional expiration time
- Cryptographic signature

### Trade Structure

A trade record contains:
- Trade ID
- Buy and sell order IDs
- Execution price and quantity
- Buyer and seller addresses
- Asset pair
- Timestamp
- Matching proof

### Matching Proof

A matching proof contains:
- Buy and sell order commitments (hashes)
- Execution price and quantity
- Timestamp
- Future: TEE attestation will be added here

### Settlement Instruction

A settlement instruction contains:
- Trade ID
- Buy and sell order commitments
- Buyer and seller addresses
- Base and quote asset addresses
- Base and quote amounts
- Fee amounts (base and quote)
- Matching proof
- Timestamp

## Matching Engine Design

### Order Book Data Structure

The order book maintains price-time priority:
- Separate buy orders (bids) and sell orders (asks)
- Buy orders sorted by descending price
- Sell orders sorted by ascending price
- Orders at the same price sorted by time (FIFO)

### Matching Algorithm

The matching algorithm:
- Processes orders continuously as they arrive
- Matches buy orders against sell orders (asks) and vice versa
- Respects price-time priority
- Supports partial fills
- Generates trade records for matched orders

### Matching Engine API

The matching engine provides the following operations:
- Submit order: Add a new order to the order book
- Cancel order: Remove an order from the order book
- Get order status: Query the current status of an order
- Get order book snapshot: Retrieve current state of the order book for an asset pair

## On-Chain Settlement Contract

### Soroban Smart Contract Interface

The settlement contract's `settle_trade` function performs the following steps:

1. **Verify matching proof**: Validates that the matching proof is correct
2. **Verify order commitments**: Checks that order commitments match the settlement instruction
3. **Check balances**: Verifies that both users have sufficient vault balances
4. **Execute transfers**: Updates vault balances atomically (buyer receives base asset, seller receives quote asset)
5. **Collect fees**: Processes any applicable fees
6. **Emit settlement event**: Records the settlement on-chain for indexing and auditability

The function returns a success result if all steps complete successfully.

## Data Flow

### Order Submission Flow

```
1. User → Client: Create order
2. Client → Matching Engine: Submit signed order
3. Matching Engine: Validate & store in order book
4. Matching Engine → On-Chain: Post order commitment (optional)
5. Matching Engine: Attempt to match order
```

### Matching & Settlement Flow

```
1. Matching Engine: Match orders (off-chain)
2. Matching Engine: Generate matching proof
3. Matching Engine → On-Chain: Submit settlement transaction
   - Settlement instructions
   - Matching proof
   - Order commitments
4. On-Chain Contract: Verify proof & commitments
5. On-Chain Contract: Execute asset transfers
6. On-Chain Contract: Emit settlement event
7. Client: Query settlement status
```

## API Design

### REST API Endpoints

```
POST   /api/v1/orders              # Submit order
DELETE /api/v1/orders/:id          # Cancel order
GET    /api/v1/orders/:id          # Get order status
GET    /api/v1/orders               # List user orders
GET    /api/v1/orderbook/:pair      # Get order book snapshot
GET    /api/v1/trades               # Get trade history
POST   /api/v1/settlement/submit   # Sign and submit settlement
GET    /health                      # Health check
```

### WebSocket API (Planned)

```
ws://api/ws/orders      # Subscribe to order updates
ws://api/ws/trades      # Subscribe to trade updates
ws://api/ws/orderbook/:pair  # Subscribe to order book updates
```

## Security

### Order Signing

Orders are cryptographically signed using the user's private key:
- Order data is serialized into a message format
- The message is signed with the user's private key
- Signatures are verified by checking the message against the signature and user's public key
- This ensures order authenticity and prevents tampering

### Security Measures

1. **Order Signatures**: Cryptographic signatures prevent tampering
2. **Rate Limiting**: Per-user and per-IP limits
3. **Input Validation**: Price bounds, quantity validation, asset pair validation
4. **Cryptographic Proofs**: Matching proofs ensure fair execution
5. **On-Chain Verification**: All settlements verified on-chain
6. **Audit Trail**: Complete settlement history on-chain

### Attack Mitigation

- **Front-Running**: Matching proofs prevent manipulation
- **Order Manipulation**: Cryptographic signatures prevent tampering
- **Settlement Failures**: On-chain validation prevents invalid settlements
- **DoS Protection**: Rate limiting and spam prevention

## Technology Stack

**Off-Chain Matching:**
- Language: Python (FastAPI framework)
- REST API: FastAPI with Uvicorn server
- Storage: In-memory (for privacy and performance)
- Cryptography: stellar-sdk (Ed25519 for signatures, SHA-256 for commitments)
- Transaction Submission: Soroban RPC via stellar-sdk

**On-Chain Settlement:**
- Smart Contract: Soroban (Rust)
- Stellar SDK: Python stellar-sdk for transaction submission
- Event Indexing: Stellar Horizon API

**Client Layer:**
- Web Interface: React/Next.js (planned)
- SDK: TypeScript/JavaScript, Python, Rust

## Performance & Scalability

### Matching Performance
- **Throughput**: 10,000+ orders/second (off-chain)
- **Latency**: <10ms matching latency
- **Order Book**: In-memory for speed

### Settlement Performance
- **Stellar Network**: 3-5 second settlement
- **Batch Settlements**: Group multiple trades per transaction
- **Parallel Processing**: Process independent settlements concurrently

## Comparison with Existing Solutions

| Feature | Hyperliquid/Serum/Econia/DeepBook | Proposed Dark Pool |
|---------|-----------------------------------|-------------------|
| Order Visibility | Public (on-chain) | Private (off-chain) |
| Matching Location | On-chain | Off-chain |
| Settlement | On-chain | On-chain |
| Privacy | None | High |
| Gas Costs | High (all operations on-chain) | Low (only settlement) |
| Throughput | Limited by blockchain | High (off-chain matching) |
| Trust Model | Trustless | Requires trusted matcher |

## Learnings from Hybrid Approaches

This architecture is informed by analysis of existing hybrid solutions:

### Orderly Network
- **Lesson**: Store comprehensive trade history on-chain for auditability
- **Adoption**: Emit detailed events with full trade data
- **Benefit**: Complete transparency of all settlements

### Polymarket
- **Lesson**: Use cryptographic signatures for order verification
- **Adoption**: All orders signed with Stellar keypairs
- **Benefit**: Non-repudiation and order authenticity verification

### KyberSwap Limit Order
- **Lesson**: Keep design simple and focused
- **Adoption**: Focus on dark pool use case, avoid over-engineering
- **Benefit**: Easier to build, maintain, and audit

### Common Patterns
- **Off-chain matching, on-chain settlement**: Universal pattern we adopt
- **Private order books, public settlements**: Balance privacy with transparency
- **Trusted operator with transparency**: Open-source code and audits provide transparency
- **Gas optimization**: Only settle on-chain, minimize operations

## Future Enhancements

1. **Advanced Order Types**
   - Iceberg orders
   - TWAP/VWAP orders
   - Conditional orders

2. **Cross-Chain Settlement**
   - Support for assets on other chains
   - Atomic swaps for cross-chain trades

3. **Liquidity Aggregation**
   - Aggregate liquidity from multiple sources
   - Best execution routing

4. **TEE Integration**
   - Trusted Execution Environment for matching integrity
   - Additional cryptographic guarantees

## Open Questions

1. **TEE Integration**: When and how to integrate TEE for matching integrity?
2. **Order Commitment**: Always post commitments or only on settlement?
3. **Dispute Resolution**: How to handle matching disputes?
4. **Regulatory Compliance**: KYC/AML requirements?
