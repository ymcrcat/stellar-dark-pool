"""
Unit tests for MatchingEngine.
"""
import pytest
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock

from src.types import Order, OrderSide, OrderType, TimeInForce, AssetPair
from src.engine import MatchingEngine


@pytest.mark.asyncio
async def test_engine_initialization(mock_stellar_service):
    """Test matching engine initialization."""
    engine = MatchingEngine()

    assert not engine._initialized

    await engine.initialize()

    assert engine._initialized
    assert engine.base_asset is not None
    assert engine.quote_asset is not None
    assert engine.orderbook is not None


@pytest.mark.asyncio
async def test_submit_order_with_balance_check(mock_stellar_service, user1_keypair):
    """Test submitting order with sufficient balance."""
    engine = MatchingEngine()
    await engine.initialize()

    order = Order(
        order_id="test-001",
        user_address=user1_keypair.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    trades = await engine.submit_order(order)

    # No matches expected for first order
    assert len(trades) == 0
    mock_stellar_service.get_vault_balance.assert_called()


@pytest.mark.asyncio
async def test_submit_order_insufficient_balance(mock_stellar_service, user1_keypair):
    """Test submitting order with insufficient balance."""
    # Mock insufficient balance
    mock_stellar_service.get_vault_balance = AsyncMock(return_value=0)

    engine = MatchingEngine()
    await engine.initialize()

    order = Order(
        order_id="test-001",
        user_address=user1_keypair.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    with pytest.raises(ValueError, match="Insufficient vault balance"):
        await engine.submit_order(order)


@pytest.mark.asyncio
async def test_submit_order_unsupported_asset_pair(mock_stellar_service, user1_keypair):
    """Test submitting order with unsupported asset pair."""
    engine = MatchingEngine()
    await engine.initialize()

    # Order with different asset pair
    order = Order(
        order_id="test-001",
        user_address=user1_keypair.public_key,
        asset_pair=AssetPair(base="BTC", quote="ETH"),
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    with pytest.raises(ValueError, match="Unsupported asset pair"):
        await engine.submit_order(order)


@pytest.mark.asyncio
async def test_submit_matching_orders(mock_stellar_service, user1_keypair, user2_keypair):
    """Test submitting two orders that match."""
    engine = MatchingEngine()
    await engine.initialize()

    # Buy order
    buy_order = Order(
        order_id="buy-001",
        user_address=user1_keypair.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    # Sell order
    sell_order = Order(
        order_id="sell-001",
        user_address=user2_keypair.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Sell,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567891,
        signature="sig"
    )

    # Submit buy order
    trades1 = await engine.submit_order(buy_order)
    assert len(trades1) == 0

    # Submit matching sell order
    trades2 = await engine.submit_order(sell_order)
    assert len(trades2) == 1

    trade = trades2[0]
    assert trade.quantity == Decimal("100")
    assert trade.price == Decimal("1.5")
    assert trade.buy_user == buy_order.user_address
    assert trade.sell_user == sell_order.user_address


@pytest.mark.asyncio
async def test_balance_update_after_trade(mock_stellar_service, user1_keypair, user2_keypair):
    """Test that internal balances are updated after trade."""
    engine = MatchingEngine()
    await engine.initialize()

    # Cache initial balances
    base_contract = engine.base_asset
    quote_contract = engine.quote_asset

    buyer_quote_key = f"{user1_keypair.public_key}:{quote_contract}"
    seller_base_key = f"{user2_keypair.public_key}:{base_contract}"

    # Set initial cached balances
    engine.vault_balances[buyer_quote_key] = 2000000000  # 200 XLM
    engine.vault_balances[seller_base_key] = 2000000000  # 200 XLM

    # Buy order
    buy_order = Order(
        order_id="buy-001",
        user_address=user1_keypair.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    # Sell order
    sell_order = Order(
        order_id="sell-001",
        user_address=user2_keypair.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Sell,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567891,
        signature="sig"
    )

    await engine.submit_order(buy_order)
    await engine.submit_order(sell_order)

    # Check that balances were updated
    # Buyer should have less quote asset (paid 100 * 1.5 = 150)
    expected_buyer_quote_decrease = int(Decimal("150") * Decimal("10000000"))
    assert engine.vault_balances[buyer_quote_key] == 2000000000 - expected_buyer_quote_decrease

    # Seller should have less base asset (sold 100)
    expected_seller_base_decrease = int(Decimal("100") * Decimal("10000000"))
    assert engine.vault_balances[seller_base_key] == 2000000000 - expected_seller_base_decrease


@pytest.mark.asyncio
async def test_cancel_order(mock_stellar_service, user1_keypair):
    """Test canceling an order."""
    engine = MatchingEngine()
    await engine.initialize()

    order = Order(
        order_id="test-001",
        user_address=user1_keypair.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    await engine.submit_order(order)

    await engine.cancel_order(
        order.order_id,
        order.user_address,
        AssetPair(base="XLM", quote="USDC")
    )

    # Verify order is cancelled
    retrieved = await engine.get_order(order.order_id, order.asset_pair)
    assert retrieved is not None
    assert retrieved.status.value == "Cancelled"


@pytest.mark.asyncio
async def test_get_orderbook_snapshot(mock_stellar_service, user1_keypair):
    """Test getting orderbook snapshot."""
    engine = MatchingEngine()
    await engine.initialize()

    # Add some orders
    for i in range(3):
        order = Order(
            order_id=f"order-{i}",
            user_address=user1_keypair.public_key,
            asset_pair=AssetPair(base="XLM", quote="USDC"),
            side=OrderSide.Buy,
            order_type=OrderType.Limit,
            price=Decimal(f"{1.0 + i * 0.1}"),
            quantity=Decimal("100"),
            time_in_force=TimeInForce.GTC,
            timestamp=1234567890 + i,
            signature="sig"
        )
        await engine.submit_order(order)

    snapshot = await engine.get_orderbook_snapshot(AssetPair(base="XLM", quote="USDC"))

    assert len(snapshot.bids) == 3
    assert len(snapshot.asks) == 0
    assert snapshot.timestamp > 0


@pytest.mark.asyncio
async def test_buy_order_balance_check_quote_asset(mock_stellar_service, user1_keypair):
    """Test that buy orders check quote asset balance."""
    engine = MatchingEngine()
    await engine.initialize()

    # For buy order at price 1.5 and quantity 100, needs 150 quote asset
    # Set quote balance to insufficient (100 stroops = 0.00001 XLM)
    mock_stellar_service.get_vault_balance = AsyncMock(return_value=100)

    order = Order(
        order_id="buy-001",
        user_address=user1_keypair.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    with pytest.raises(ValueError, match="Insufficient vault balance"):
        await engine.submit_order(order)


@pytest.mark.asyncio
async def test_sell_order_balance_check_base_asset(mock_stellar_service, user1_keypair):
    """Test that sell orders check base asset balance."""
    engine = MatchingEngine()
    await engine.initialize()

    # For sell order, needs base asset
    mock_stellar_service.get_vault_balance = AsyncMock(return_value=100)

    order = Order(
        order_id="sell-001",
        user_address=user1_keypair.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Sell,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    with pytest.raises(ValueError, match="Insufficient vault balance"):
        await engine.submit_order(order)
