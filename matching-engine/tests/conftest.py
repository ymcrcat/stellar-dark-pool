"""
Pytest configuration and fixtures for matching engine tests.
"""
import pytest
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock
from stellar_sdk import Keypair

from src.types import Order, OrderSide, OrderType, TimeInForce, OrderStatus, AssetPair
from src.orderbook import OrderBook
from src.engine import MatchingEngine


@pytest.fixture
def asset_pair():
    """Standard asset pair for testing."""
    return AssetPair(base="XLM", quote="USDC")


@pytest.fixture
def orderbook(asset_pair):
    """Create a fresh orderbook."""
    return OrderBook(asset_pair)


@pytest.fixture
def matching_engine():
    """Create a matching engine instance."""
    return MatchingEngine()


@pytest.fixture
def sample_keypair():
    """Generate a test keypair."""
    return Keypair.random()


@pytest.fixture
def user1_keypair():
    """User 1 keypair."""
    return Keypair.random()


@pytest.fixture
def user2_keypair():
    """User 2 keypair."""
    return Keypair.random()


@pytest.fixture
def buy_order(asset_pair, user1_keypair):
    """Create a sample buy limit order."""
    return Order(
        order_id="buy-001",
        user_address=user1_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        filled_quantity=Decimal("0"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="test-sig",
        status=OrderStatus.Pending
    )


@pytest.fixture
def sell_order(asset_pair, user2_keypair):
    """Create a sample sell limit order."""
    return Order(
        order_id="sell-001",
        user_address=user2_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Sell,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        filled_quantity=Decimal("0"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567891,
        signature="test-sig",
        status=OrderStatus.Pending
    )


@pytest.fixture
def mock_stellar_service(monkeypatch):
    """Mock stellar service for testing without blockchain calls."""
    from src import stellar
    from src import engine as engine_module

    mock = MagicMock()
    mock.get_asset_a = AsyncMock(return_value="CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC")
    mock.get_asset_b = AsyncMock(return_value="CBGTJ2FVGKZRQX4OVKWFLU3LBVXO5DSJFHZXFXMZFQZNVXPZMQWXLM7A")

    # Mock get_contract_address to return contract IDs
    def mock_get_contract_address(asset_str):
        if asset_str == "XLM":
            return "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
        elif asset_str == "USDC":
            return "CBGTJ2FVGKZRQX4OVKWFLU3LBVXO5DSJFHZXFXMZFQZNVXPZMQWXLM7A"
        else:
            return f"C{asset_str}CONTRACT"

    mock.get_contract_address = MagicMock(side_effect=mock_get_contract_address)
    mock.get_vault_balance = AsyncMock(return_value=1000000000000)  # Large balance
    mock.verify_order_signature = MagicMock(return_value=True)
    mock.sign_and_submit_settlement = AsyncMock(return_value="tx-hash-123")

    monkeypatch.setattr(stellar, "stellar_service", mock)
    monkeypatch.setattr(engine_module, "stellar_service", mock)
    return mock
