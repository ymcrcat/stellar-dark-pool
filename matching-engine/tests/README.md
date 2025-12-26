# Matching Engine Tests

Comprehensive pytest test suite for the Stellar Dark Pool matching engine.

## Test Coverage

### test_orderbook.py (12 tests)
Tests for the core order matching logic:
- Empty orderbook operations
- Adding buy/sell orders without matches
- Full and partial order matching
- Price-time priority matching algorithm
- Order cancellation (authorized and unauthorized)
- IOC (Immediate or Cancel) order behavior
- Limit order price checks
- Orderbook snapshot generation

### test_engine.py (10 tests)
Tests for the matching engine:
- Engine initialization with Stellar contract queries
- Order submission with balance checks
- Insufficient balance detection
- Asset pair validation
- Matching order execution
- Internal balance updates after trades
- Order cancellation
- Orderbook snapshot retrieval
- Buy/sell order balance requirements

### test_signature.py (6 tests)
Tests for cryptographic order signing (SEP-0053):
- Order message creation
- Order signing and verification
- Invalid signature rejection
- Wrong public key detection
- Order tampering detection

### test_api.py (9 tests)
Integration tests for REST API endpoints:
- Health check endpoint
- Order submission with validation
- Signature verification
- Input validation (quantity, price)
- Orderbook retrieval
- Settlement submission
- Balance queries

## Running Tests

### Run all tests:
```bash
source venv/bin/activate
pytest tests/
```

### Run with verbose output:
```bash
pytest tests/ -v
```

### Run specific test file:
```bash
pytest tests/test_orderbook.py -v
```

### Run specific test:
```bash
pytest tests/test_orderbook.py::test_full_match_buy_sell -v
```

### Run with coverage:
```bash
pytest tests/ --cov=src --cov-report=html
```

### Run tests in parallel:
```bash
pytest tests/ -n auto
```

## Test Results

```
======================== 37 passed, 2 warnings in 0.19s ========================
```

**Coverage:**
- Orderbook matching logic: ✓
- Engine initialization: ✓
- Balance checks: ✓
- Asset validation: ✓
- Order signing/verification: ✓
- API endpoints: ✓
- Error handling: ✓

## Test Fixtures

### Fixtures in conftest.py:
- `asset_pair`: Standard XLM/USDC asset pair
- `orderbook`: Fresh orderbook instance
- `matching_engine`: Matching engine instance
- `user1_keypair`, `user2_keypair`: Test keypairs
- `buy_order`, `sell_order`: Sample orders
- `mock_stellar_service`: Mocked Stellar blockchain calls

## Mocking Strategy

Tests use mocked Stellar service to avoid actual blockchain calls:
- Contract queries mocked
- Balance checks mocked with large balances
- Signature verification can be enabled/disabled
- Settlement submission mocked

This allows fast unit testing without testnet dependencies.

## Key Test Scenarios

### Order Matching
1. Price-time priority: Best price matched first, then earliest timestamp
2. Partial fills: Larger orders matched against multiple smaller orders
3. Immediate or Cancel: IOC orders don't stay in book
4. Limit price protection: Orders don't match at unfavorable prices

### Balance Validation
1. Buy orders check quote asset balance
2. Sell orders check base asset balance
3. Insufficient balance rejects order submission
4. Internal balance tracking after trades

### Signature Security
1. SEP-0053 compliant message signing
2. SHA-256 hash verification
3. Ed25519 signature validation
4. Tampering detection

### API Security
1. Signature verification before order acceptance
2. Input validation (positive quantities/prices)
3. Unauthorized cancellation prevention
4. Asset pair format validation

## Adding New Tests

1. Add test file in `tests/` directory with `test_` prefix
2. Use fixtures from `conftest.py`
3. Mark async tests with `@pytest.mark.asyncio`
4. Follow naming convention: `test_<feature>_<scenario>`
5. Include docstrings explaining test purpose

Example:
```python
@pytest.mark.asyncio
async def test_new_feature(orderbook, buy_order):
    """Test description here."""
    # Test implementation
    assert expected == actual
```

## Continuous Integration

These tests can be integrated into CI/CD pipelines:
```yaml
- name: Run tests
  run: |
    source venv/bin/activate
    pytest tests/ -v --junitxml=test-results.xml
```

## Troubleshooting

### Import errors
Ensure matching-engine directory is in PYTHONPATH:
```bash
export PYTHONPATH=/path/to/matching-engine:$PYTHONPATH
```

### Async test errors
Install pytest-asyncio:
```bash
pip install pytest-asyncio
```

### Mock not working
Check that fixtures are properly imported and used in test functions.
