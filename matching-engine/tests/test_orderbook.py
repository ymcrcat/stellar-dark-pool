"""
Unit tests for OrderBook matching logic.
"""
import pytest
from decimal import Decimal

from src.types import Order, OrderSide, OrderType, TimeInForce, OrderStatus, AssetPair


@pytest.mark.asyncio
async def test_empty_orderbook_snapshot(orderbook):
    """Test getting snapshot of empty orderbook."""
    snapshot = await orderbook.get_snapshot()

    assert snapshot.asset_pair == orderbook.asset_pair
    assert len(snapshot.bids) == 0
    assert len(snapshot.asks) == 0
    assert snapshot.timestamp > 0


@pytest.mark.asyncio
async def test_add_buy_order_no_match(orderbook, buy_order):
    """Test adding a buy order when no matching sell orders exist."""
    trades = await orderbook.match_order(buy_order)

    assert len(trades) == 0
    assert buy_order.status == OrderStatus.Pending
    assert buy_order.filled_quantity == Decimal("0")
    assert len(orderbook.bids) == 1
    assert orderbook.bids[buy_order.price][0] == buy_order


@pytest.mark.asyncio
async def test_add_sell_order_no_match(orderbook, sell_order):
    """Test adding a sell order when no matching buy orders exist."""
    trades = await orderbook.match_order(sell_order)

    assert len(trades) == 0
    assert sell_order.status == OrderStatus.Pending
    assert sell_order.filled_quantity == Decimal("0")
    assert len(orderbook.asks) == 1
    assert orderbook.asks[sell_order.price][0] == sell_order


@pytest.mark.asyncio
async def test_full_match_buy_sell(orderbook, buy_order, sell_order):
    """Test full match between buy and sell orders."""
    # Add buy order first
    await orderbook.match_order(buy_order)

    # Add matching sell order
    trades = await orderbook.match_order(sell_order)

    assert len(trades) == 1
    trade = trades[0]

    assert trade.quantity == Decimal("100")
    assert trade.price == buy_order.price
    assert trade.buy_user == buy_order.user_address
    assert trade.sell_user == sell_order.user_address

    assert buy_order.status == OrderStatus.Filled
    assert sell_order.status == OrderStatus.Filled
    assert buy_order.filled_quantity == Decimal("100")
    assert sell_order.filled_quantity == Decimal("100")


@pytest.mark.asyncio
async def test_partial_match(orderbook, asset_pair, user1_keypair, user2_keypair):
    """Test partial order fill."""
    # Large buy order
    buy = Order(
        order_id="buy-large",
        user_address=user1_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("2.0"),
        quantity=Decimal("200"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    # Small sell order
    sell = Order(
        order_id="sell-small",
        user_address=user2_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Sell,
        order_type=OrderType.Limit,
        price=Decimal("2.0"),
        quantity=Decimal("50"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567891,
        signature="sig"
    )

    await orderbook.match_order(buy)
    trades = await orderbook.match_order(sell)

    assert len(trades) == 1
    assert trades[0].quantity == Decimal("50")

    assert buy.status == OrderStatus.PartiallyFilled
    assert buy.filled_quantity == Decimal("50")
    assert sell.status == OrderStatus.Filled
    assert sell.filled_quantity == Decimal("50")

    # Buy order should still be in book
    assert len(orderbook.bids) == 1
    assert orderbook.bids[buy.price][0].order_id == buy.order_id


@pytest.mark.asyncio
async def test_price_priority(orderbook, asset_pair, user1_keypair, user2_keypair):
    """Test that best price is matched first."""
    # Add multiple sell orders at different prices
    sell_low = Order(
        order_id="sell-low",
        user_address=user1_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Sell,
        order_type=OrderType.Limit,
        price=Decimal("1.0"),
        quantity=Decimal("50"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    sell_high = Order(
        order_id="sell-high",
        user_address=user1_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Sell,
        order_type=OrderType.Limit,
        price=Decimal("2.0"),
        quantity=Decimal("50"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567891,
        signature="sig"
    )

    await orderbook.match_order(sell_high)
    await orderbook.match_order(sell_low)

    # Now submit buy order that can match both
    buy = Order(
        order_id="buy-001",
        user_address=user2_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("2.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567892,
        signature="sig"
    )

    trades = await orderbook.match_order(buy)

    # Should match with sell_low first (better price)
    assert len(trades) == 2
    assert trades[0].price == Decimal("1.0")
    assert trades[1].price == Decimal("2.0")


@pytest.mark.asyncio
async def test_time_priority(orderbook, asset_pair, user1_keypair, user2_keypair):
    """Test that earlier orders are matched first at same price."""
    # Add two sell orders at same price
    sell_first = Order(
        order_id="sell-first",
        user_address=user1_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Sell,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("50"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    sell_second = Order(
        order_id="sell-second",
        user_address=user1_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Sell,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("50"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567891,
        signature="sig"
    )

    await orderbook.match_order(sell_first)
    await orderbook.match_order(sell_second)

    # Submit buy order matching only first
    buy = Order(
        order_id="buy-001",
        user_address=user2_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("50"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567892,
        signature="sig"
    )

    trades = await orderbook.match_order(buy)

    # Should match with sell_first
    assert len(trades) == 1
    assert trades[0].sell_order_id == "sell-first"
    assert sell_first.status == OrderStatus.Filled
    assert sell_second.status == OrderStatus.Pending


@pytest.mark.asyncio
async def test_cancel_order(orderbook, buy_order):
    """Test canceling an order."""
    await orderbook.match_order(buy_order)

    await orderbook.cancel_order(buy_order.order_id, buy_order.user_address)

    assert buy_order.status == OrderStatus.Cancelled
    assert len(orderbook.bids) == 0


@pytest.mark.asyncio
async def test_cancel_unauthorized(orderbook, buy_order, user2_keypair):
    """Test that users can't cancel other users' orders."""
    await orderbook.match_order(buy_order)

    with pytest.raises(ValueError, match="Unauthorized"):
        await orderbook.cancel_order(buy_order.order_id, user2_keypair.public_key)


@pytest.mark.asyncio
async def test_ioc_order_partial_fill(orderbook, asset_pair, user1_keypair, user2_keypair):
    """Test IOC (Immediate or Cancel) order behavior."""
    # Add small sell order
    sell = Order(
        order_id="sell-small",
        user_address=user1_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Sell,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("50"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    await orderbook.match_order(sell)

    # IOC buy order for more than available
    buy_ioc = Order(
        order_id="buy-ioc",
        user_address=user2_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.IOC,
        timestamp=1234567891,
        signature="sig"
    )

    trades = await orderbook.match_order(buy_ioc)

    # Should match 50 but not add remainder to book
    assert len(trades) == 1
    assert trades[0].quantity == Decimal("50")
    assert buy_ioc.filled_quantity == Decimal("50")
    assert buy_ioc.status == OrderStatus.PartiallyFilled
    assert len(orderbook.bids) == 0  # IOC not added to book


@pytest.mark.asyncio
async def test_limit_order_price_check(orderbook, asset_pair, user1_keypair, user2_keypair):
    """Test that limit orders don't match at unfavorable prices."""
    # Add sell order at 2.0
    sell = Order(
        order_id="sell-001",
        user_address=user1_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Sell,
        order_type=OrderType.Limit,
        price=Decimal("2.0"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature="sig"
    )

    await orderbook.match_order(sell)

    # Buy order with limit price below sell price
    buy = Order(
        order_id="buy-001",
        user_address=user2_keypair.public_key,
        asset_pair=asset_pair,
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567891,
        signature="sig"
    )

    trades = await orderbook.match_order(buy)

    # Should not match
    assert len(trades) == 0
    assert len(orderbook.bids) == 1
    assert len(orderbook.asks) == 1


@pytest.mark.asyncio
async def test_orderbook_snapshot_with_orders(orderbook, asset_pair, user1_keypair, user2_keypair):
    """Test orderbook snapshot with multiple price levels."""
    # Add multiple orders
    for i in range(5):
        buy = Order(
            order_id=f"buy-{i}",
            user_address=user1_keypair.public_key,
            asset_pair=asset_pair,
            side=OrderSide.Buy,
            order_type=OrderType.Limit,
            price=Decimal(f"{1.0 + i * 0.1}"),
            quantity=Decimal("100"),
            time_in_force=TimeInForce.GTC,
            timestamp=1234567890 + i,
            signature="sig"
        )
        await orderbook.match_order(buy)

        sell = Order(
            order_id=f"sell-{i}",
            user_address=user2_keypair.public_key,
            asset_pair=asset_pair,
            side=OrderSide.Sell,
            order_type=OrderType.Limit,
            price=Decimal(f"{2.0 + i * 0.1}"),
            quantity=Decimal("50"),
            time_in_force=TimeInForce.GTC,
            timestamp=1234567890 + i,
            signature="sig"
        )
        await orderbook.match_order(sell)

    snapshot = await orderbook.get_snapshot()

    assert len(snapshot.bids) == 5
    assert len(snapshot.asks) == 5

    # Bids should be in descending order
    for i in range(len(snapshot.bids) - 1):
        assert snapshot.bids[i].price > snapshot.bids[i + 1].price

    # Asks should be in ascending order
    for i in range(len(snapshot.asks) - 1):
        assert snapshot.asks[i].price < snapshot.asks[i + 1].price
