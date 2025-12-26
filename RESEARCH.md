# Research: Existing On-Chain Order Book Solutions

## Overview
This document analyzes existing on-chain order book implementations to inform the design of a dark pool with off-chain matching and on-chain settlement.

## 1. Hyperliquid

### Architecture
- **Fully On-Chain CLOB**: HyperCore (Layer-1 matching layer) maintains complete order book state on-chain
- **No Off-Chain Component**: Every order, cancel, and fill is stored on the blockchain
- **External Services**: REST/WebSocket APIs only mirror on-chain data (read-only)

### Key Characteristics
- **State Management**: All order book state is on-chain
- **Matching Engine**: On-chain matching logic
- **Settlement**: Immediate on-chain settlement
- **Transparency**: Complete transparency of all orders and trades
- **Trade-offs**: Higher gas costs, potential latency issues

### Design Principles
- Single source of truth on-chain
- No trusted intermediaries
- Complete auditability

## 2. Serum/OpenBook (Solana)

### Architecture
- **On-Chain CLOB**: Central limit order book stored on Solana blockchain
- **Smart Contract Execution**: Orders executed directly with smart contracts
- **Flexibility**: Supports various pricing and order sizes
- **Market Makers**: Enables sophisticated market making strategies

### Key Characteristics
- **Order Book State**: Stored in program data accounts
- **Matching**: On-chain matching engine
- **Settlement**: On-chain settlement via Solana's native token transfers
- **Performance**: Leverages Solana's high throughput (though with some limitations)

### Design Principles
- Decentralized order matching
- Programmable order types
- Integration with Solana ecosystem

## 3. Econia (Aptos)

### Architecture
- **On-Chain LOB**: Limit order book implementation on Aptos
- **Move Smart Contracts**: Built using Move language
- **Integration**: Powers trading interfaces like Pontem's Gator

### Key Characteristics
- **State Management**: Order book state in Move resources
- **Matching**: On-chain matching logic
- **Settlement**: Native Aptos token transfers
- **Type Safety**: Move's type system ensures safety

### Design Principles
- Resource-oriented design
- Type-safe operations
- High throughput capabilities

## 4. DeepBook (Sui)

### Architecture
- **On-Chain LOB**: Order book implementation on Sui blockchain
- **Sui Objects**: Leverages Sui's object model
- **Parallel Execution**: Benefits from Sui's parallel transaction execution

### Key Characteristics
- **State Management**: Order book as Sui objects
- **Matching**: On-chain matching with parallel processing
- **Settlement**: Sui native transfers
- **Performance**: Parallel execution improves throughput

### Design Principles
- Object-oriented state management
- Parallel transaction processing
- Composability with Sui ecosystem

## Common Patterns Across Solutions

### Shared Characteristics
1. **On-Chain State**: All maintain order book state on-chain
2. **On-Chain Matching**: Matching logic executed on-chain
3. **Immediate Settlement**: Settlement happens as part of matching
4. **Transparency**: All orders and trades are visible on-chain
5. **No Off-Chain Matching**: None use off-chain matching with on-chain settlement

### Trade-offs
- **Pros**: Complete transparency, no trusted intermediaries, full auditability
- **Cons**: Higher gas costs, potential latency, limited privacy, scalability challenges

## Hybrid Approaches (Off-Chain Matching, On-Chain Settlement)

The following solutions use hybrid architectures that match orders off-chain but settle on-chain, similar to our proposed dark pool design.

## 5. Orderly Network

### Architecture
- **Hybrid Orderbook Model**: Combines centralized and decentralized exchange features
- **Off-Chain Matching**: Orders are matched off-chain by a centralized matching engine
- **On-Chain Settlement**: All trades are settled and stored on-chain
- **State Storage**: Trade history and settlement data stored on blockchain for transparency

### Key Characteristics
- **Matching**: Off-chain matching engine (centralized operator)
- **Settlement**: On-chain settlement via smart contracts
- **State Management**: Trade records stored on-chain, order book state off-chain
- **Transparency**: All settlements visible on-chain, but order book remains private
- **Performance**: High throughput matching off-chain, finality on-chain

### Design Principles
- Best of both worlds: CEX-like performance with DEX-like transparency
- Off-chain efficiency for matching
- On-chain finality for settlement
- Trade history auditable on-chain

### Trade-offs
- **Pros**: High performance, lower gas costs, transparent settlements
- **Cons**: Requires trust in matching operator, order book not fully transparent

### Implementation Details
- Uses a centralized matching engine for order matching
- Settlement transactions posted to blockchain
- Trade data stored on-chain for auditability
- Supports multiple blockchains (Ethereum, NEAR, Arbitrum, etc.)

## 6. Polymarket

### Architecture
- **Hybrid-Decentralized CLOB**: Central limit order book with hybrid architecture
- **Off-Chain Operator**: Operator handles off-chain matching and ordering
- **Signed Order Messages**: Orders are signed messages that can be verified
- **On-Chain Settlement**: Settlement executed on-chain via signed order messages

### Key Characteristics
- **Matching**: Off-chain operator matches orders
- **Order Format**: Signed order messages (cryptographically verifiable)
- **Settlement**: On-chain execution via smart contracts
- **Verification**: Order signatures can be verified on-chain
- **Trust Model**: Operator handles matching, but orders are verifiable

### Design Principles
- Signed orders enable verification without full transparency
- Operator efficiency for matching
- On-chain verification of order authenticity
- Settlement finality on-chain

### Trade-offs
- **Pros**: Efficient matching, verifiable orders, on-chain settlement
- **Cons**: Requires trust in operator, order book not public
- **Use Case**: Particularly suited for prediction markets

### Implementation Details
- Operator maintains off-chain order book
- Orders are signed messages (EIP-712 style)
- Settlement contract verifies signatures and executes trades
- Focus on prediction market use case

## 7. KyberSwap Limit Order

### Architecture
- **Hybrid Limit Order System**: Limit orders stored off-chain, settled on-chain
- **Off-Chain Relay**: Limit orders stored on an off-chain relay service
- **On-Chain Settlement**: Only settled on-chain when matching order is found
- **On-Demand Settlement**: Settlement happens when counterparty order arrives

### Key Characteristics
- **Order Storage**: Off-chain relay maintains limit orders
- **Matching**: Matching occurs when counterparty order is found
- **Settlement**: Immediate on-chain settlement upon match
- **Gas Efficiency**: Only pay gas when order is actually filled
- **Order Types**: Focus on limit orders specifically

### Design Principles
- Store orders off-chain to save gas
- Settle only when matched (pay gas only for fills)
- Simple and efficient for limit orders
- No gas cost for unfilled orders

### Trade-offs
- **Pros**: Very gas efficient, no cost for unfilled orders, simple design
- **Cons**: Requires trust in relay service, limited to limit orders
- **Use Case**: Best for limit orders that may not fill immediately

### Implementation Details
- Relay service stores limit orders off-chain
- When matching order arrives, both orders settled on-chain
- Users can cancel orders off-chain (no gas cost)
- Settlement transaction includes both orders

## Comparison: Hybrid Approaches

| Feature | Orderly Network | Polymarket | KyberSwap Limit Order |
|---------|----------------|------------|----------------------|
| **Matching** | Off-chain (centralized) | Off-chain (operator) | Off-chain (relay) |
| **Settlement** | On-chain | On-chain | On-chain |
| **Order Visibility** | Private | Private (signed) | Private |
| **Trade Visibility** | Public (on-chain) | Public (on-chain) | Public (on-chain) |
| **Trust Model** | Trusted operator | Trusted operator | Trusted relay |
| **Order Types** | All types | CLOB | Limit orders only |
| **Gas Efficiency** | High (only settlement) | High (only settlement) | Very high (only fills) |
| **Use Case** | General trading | Prediction markets | Limit orders |

## Common Patterns in Hybrid Approaches

### Shared Characteristics
1. **Off-Chain Matching**: All use off-chain matching for efficiency
2. **On-Chain Settlement**: All settle trades on-chain for finality
3. **Private Order Books**: Order books remain private off-chain
4. **Public Settlements**: All settlements are visible on-chain
5. **Trusted Operators**: All require some level of trust in operator/relay
6. **Gas Efficiency**: Significant gas savings vs. fully on-chain

### Key Design Patterns
1. **Signed Orders**: Cryptographic signatures for order verification (Polymarket)
2. **Commitment Schemes**: Order commitments for non-repudiation
3. **Batch Settlement**: Group multiple trades for efficiency
4. **Event Emission**: Emit events for indexing and transparency
5. **Operator Verification**: Verify operator behavior through on-chain data

### Trade-offs
- **Pros**: 
  - High performance (off-chain matching)
  - Lower gas costs (only settlement on-chain)
  - Privacy for orders
  - Transparency for settlements
- **Cons**: 
  - Requires trust in operator/relay
  - Order book not fully transparent
  - Potential for operator manipulation
  - Less decentralized than fully on-chain

## Implications for Dark Pool Design

### Key Differences Needed
1. **Off-Chain Matching**: Match orders off-chain for privacy and efficiency
2. **On-Chain Settlement**: Only post matched trades on-chain
3. **Privacy**: Order details remain private until settlement
4. **Efficiency**: Reduce on-chain operations and gas costs
5. **Trust Model**: Requires trusted matching service (or decentralized matching network)

### Lessons from Hybrid Approaches

#### From Orderly Network
- **State Storage**: Store trade history on-chain for auditability
- **Multi-Chain**: Consider supporting multiple blockchains
- **Performance**: Off-chain matching enables high throughput
- **Transparency**: Balance privacy with transparency through on-chain settlements

#### From Polymarket
- **Signed Orders**: Use cryptographic signatures for order verification
- **Verification**: Enable on-chain verification of order authenticity
- **Operator Model**: Centralized operator can be efficient if properly designed
- **Use Case Focus**: Consider specific use cases (e.g., dark pool for large trades)

#### From KyberSwap Limit Order
- **Gas Efficiency**: Only pay gas when orders are filled
- **Simple Design**: Keep design simple and focused
- **Relay Model**: Off-chain relay can be efficient for specific order types
- **Cancellation**: Enable free cancellation of unfilled orders

### Design Challenges
- How to ensure matching service integrity without revealing orders
- How to prevent front-running while maintaining privacy
- How to handle disputes and ensure fair matching
- How to scale matching while maintaining decentralization
- How to balance trust in operator with decentralization
- How to provide cryptographic guarantees of fair matching

---

## Key Learnings from Hybrid Approaches

This section summarizes key learnings from existing hybrid order book solutions (Orderly Network, Polymarket, KyberSwap Limit Order) and how they inform our dark pool design.

### Design Recommendations

#### 1. Order Signing (from Polymarket)
- **Implement**: Cryptographic signatures for all orders
- **Format**: Use Stellar's signature scheme
- **Verification**: Enable on-chain signature verification
- **Benefit**: Non-repudiation and order authenticity

#### 2. Trade History Storage (from Orderly)
- **Implement**: Store comprehensive trade data on-chain
- **Format**: Structured event data
- **Indexing**: Enable easy indexing and querying
- **Benefit**: Complete auditability

#### 3. Simplicity (from KyberSwap)
- **Implement**: Keep design simple and focused
- **Avoid**: Over-engineering
- **Focus**: Dark pool use case specifically
- **Benefit**: Easier to build, maintain, and audit

#### 4. Gas Optimization (from All)
- **Implement**: Minimize on-chain operations
- **Method**: Only settlement on-chain
- **Optimization**: Batch settlements when possible
- **Benefit**: Lower costs for users

#### 5. Operator Transparency (from All)
- **Implement**: Open-source code
- **Audits**: Regular security audits
- **Monitoring**: Public monitoring and metrics
- **Benefit**: Builds trust in operator

### Common Patterns Across All Hybrid Approaches

1. **Off-Chain Matching, On-Chain Settlement**: Universal pattern we adopt
2. **Private Order Books**: All keep order books private
3. **Trusted Operator Model**: All require some trust in operator
4. **Gas Efficiency**: All optimize for gas efficiency

### What We're Adding

| Feature | Orderly | Polymarket | KyberSwap | **Our Dark Pool** |
|---------|---------|------------|-----------|------------------|
| **TEE Integration** | No | No | No | **Yes (future)** |
| **Dark Pool Focus** | No | No | No | **Yes** |
| **Stellar Native** | No | No | No | **Yes** |
| **Vault Model** | No | No | No | **Yes** |
