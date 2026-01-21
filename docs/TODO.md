# TODO List

This document tracks planned improvements, features, and production requirements for the Stellar Dark Pool.

## Smart Contract Enhancements

- [ ] **Order Signature Verification**: Implement SEP-0053 signature verification in `settle_trade()` function
- [ ] **Multi-Asset Settlement**: Optimize contract to support additional trading pairs beyond token_a/token_b
- [ ] **Emergency Pause**: Add admin capability to pause trading in emergency situations
- [ ] **Upgradability**: Consider implementing contract upgrade mechanism (CAP-0054 or similar)
- [ ] **Gas Optimization**: Profile and optimize contract functions to reduce transaction costs

## Matching Engine Features

### Order Types
- [ ] **Iceberg Orders**: Implement hidden quantity orders
- [ ] **TWAP Orders**: Time-weighted average price orders
- [ ] **VWAP Orders**: Volume-weighted average price orders
- [ ] **Stop-Loss/Stop-Limit**: Conditional order execution
- [ ] **Post-Only Orders**: Orders that only add liquidity (maker-only)

### API Enhancements
- [ ] **WebSocket API**: Real-time order book and trade updates
  - [ ] `/ws/orders` - Order updates
  - [ ] `/ws/trades` - Trade feed
  - [ ] `/ws/orderbook/:pair` - Order book snapshots
- [ ] **GraphQL API**: Alternative to REST for complex queries
- [ ] **API Authentication**: JWT/API key authentication for users
- [ ] **List User Orders**: Implement `GET /api/v1/orders` endpoint with filtering

### Performance
- [ ] **Order Book Persistence**: Implement checkpoint/restore for order book state
- [ ] **Trade History API**: Implement `GET /api/v1/trades` endpoint
- [ ] **Batch Settlements**: Group multiple trades into single on-chain transaction
- [ ] **Caching Layer**: Add Redis for balance caching and session management

### Testing
- [ ] **Load Testing**: Benchmark matching engine throughput and latency
- [ ] **Chaos Engineering**: Test system resilience under failure conditions
- [ ] **Security Testing**: Penetration testing and vulnerability scanning

## Future Enhancements

### Privacy & Security
- [ ] **TEE Integration**: Trusted Execution Environment (Intel SGX/AMD SEV) for matching integrity
  - [ ] Attestation generation for matching proofs
  - [ ] Secure enclave for private key storage
- [ ] **Zero-Knowledge Proofs**: Explore ZK proofs for order commitments
- [ ] **MPC Settlement**: Multi-party computation for distributed matching engine

### Cross-Chain
- [ ] **Cross-Chain Settlement**: Support assets on other chains
- [ ] **Atomic Swaps**: Implement cross-chain atomic swaps
- [ ] **Bridge Integration**: Connect to Ethereum, Polygon, or other chains

### Liquidity & Market Making
- [ ] **Liquidity Aggregation**: Aggregate liquidity from other DEXs
- [ ] **Best Execution Routing**: Smart order routing across venues
- [ ] **Market Maker API**: Specialized API for high-frequency market makers
- [ ] **Liquidity Mining**: Incentive programs for liquidity providers

### User Experience
- [ ] **Web UI**: Build React/Next.js web interface
- [ ] **Mobile App**: Native iOS/Android applications
- [ ] **SDK Libraries**: Client SDKs for TypeScript, Python, Rust
- [ ] **Order Templates**: Save and reuse order configurations
- [ ] **Portfolio Dashboard**: Track positions, P&L, and trade history

### Analytics & Reporting
- [ ] **Trade Analytics**: Historical data analysis and reporting
- [ ] **Market Data API**: OHLCV, volume, and market statistics
- [ ] **Event Indexer**: Index blockchain events for fast querying
- [ ] **Audit Reports**: Generate compliance and audit reports

### Governance
- [ ] **DAO Structure**: Decentralized governance for protocol parameters
- [ ] **Parameter Voting**: Community voting on fees, limits, etc.
- [ ] **Upgrade Proposals**: Governance-controlled contract upgrades

## Documentation

- [ ] **API Documentation**: OpenAPI/Swagger specification
- [ ] **Integration Guide**: Step-by-step guide for integrating with the dark pool
- [ ] **Security Best Practices**: Document security considerations for users
- [ ] **Runbook**: Operational procedures for running the matching engine
- [ ] **Add License**: Choose and add appropriate open-source license
- [ ] **Contributing Guidelines**: Document contribution process and coding standards

## Completed ✓

- ✓ HTTPS via Uvicorn TLS with Phala cloud TLS passthrough
- ✓ Vault-based settlement contract
- ✓ Python matching engine with REST API
- ✓ SEP-0053 order signing
- ✓ Price-time priority matching algorithm
- ✓ Deposit/withdraw functionality
- ✓ Balance checking
- ✓ Order book snapshots (top 20 levels)
- ✓ End-to-end testing script
- ✓ Comprehensive deployment documentation
- ✓ Authorization enforced in `settle_trade()`
- ✓ Fee collection during settlement
