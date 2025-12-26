import time
import uuid
import logging
import hashlib
from decimal import Decimal
from typing import Dict, List, Optional, Tuple
from sortedcontainers import SortedDict

from .types import (
    Order, OrderSide, OrderType, TimeInForce, OrderStatus, 
    Trade, PriceLevel, OrderBookSnapshot, AssetPair
)

logger = logging.getLogger(__name__)

class OrderBook:
    def __init__(self, asset_pair: AssetPair):
        self.asset_pair = asset_pair
        # Bids: Descending price (highest buy price first)
        self.bids: SortedDict = SortedDict() 
        self.asks: SortedDict = SortedDict() 
        self.orders: Dict[str, Order] = {}

    async def match_order(self, order: Order) -> List[Trade]:
        trades = []
        remaining_quantity = order.quantity - order.filled_quantity

        if order.side == OrderSide.Buy:
            # Match against Asks (lowest sell price first)
            while remaining_quantity > 0:
                if not self.asks:
                    break
                
                # Get best ask (lowest price)
                best_price, orders_at_price = self.asks.peekitem(0)
                
                if order.price is not None and order.price < best_price:
                    break # Limit price < best ask, can't match
                
                # Match against orders at this price level
                while orders_at_price and remaining_quantity > 0:
                    sell_order = orders_at_price[0]
                    
                    trade_quantity = min(remaining_quantity, sell_order.quantity - sell_order.filled_quantity)
                    
                    if trade_quantity > 0:
                        trade = self._create_trade(order, sell_order, best_price, trade_quantity)
                        trades.append(trade)
                        
                        remaining_quantity -= trade_quantity
                        order.filled_quantity += trade_quantity
                        sell_order.filled_quantity += trade_quantity
                        
                        self._update_order_status(sell_order)
                        
                        if sell_order.filled_quantity >= sell_order.quantity:
                            orders_at_price.pop(0) # Remove filled order
                        else:
                            pass
                    else:
                        break
                
                if not orders_at_price:
                    self.asks.popitem(0) # Remove empty price level
                
        else: # Sell Order
            # Match against Bids (highest buy price first)
            while remaining_quantity > 0:
                if not self.bids:
                    break
                
                # Get best bid (highest price) -> last item in SortedDict
                best_price, orders_at_price = self.bids.peekitem(-1)
                
                if order.price is not None and order.price > best_price:
                    break # Limit price > best bid, can't match
                
                while orders_at_price and remaining_quantity > 0:
                    buy_order = orders_at_price[0]
                    
                    trade_quantity = min(remaining_quantity, buy_order.quantity - buy_order.filled_quantity)
                    
                    if trade_quantity > 0:
                        trade = self._create_trade(buy_order, order, best_price, trade_quantity)
                        trades.append(trade)
                        
                        remaining_quantity -= trade_quantity
                        order.filled_quantity += trade_quantity
                        buy_order.filled_quantity += trade_quantity
                        
                        self._update_order_status(buy_order)
                        
                        if buy_order.filled_quantity >= buy_order.quantity:
                            orders_at_price.pop(0)
                        else:
                            pass
                    else:
                        break
                        
                if not orders_at_price:
                    self.bids.popitem(-1)

        # Update incoming order status
        self._update_order_status(order)
        self.orders[order.order_id] = order
        
        # Add to book if not filled and not IOC/FOK
        if remaining_quantity > 0 and order.time_in_force not in [TimeInForce.IOC, TimeInForce.FOK]:
            self._add_order_to_book(order)

        return trades

    def _create_trade(self, buy_order: Order, sell_order: Order, price: Decimal, quantity: Decimal) -> Trade:
        trade_id = str(uuid.uuid4())
        timestamp = int(time.time())
        
        return Trade(
            trade_id=trade_id,
            buy_order_id=buy_order.order_id,
            sell_order_id=sell_order.order_id,
            price=price,
            quantity=quantity,
            buy_user=buy_order.user_address,
            sell_user=sell_order.user_address,
            asset_pair=self.asset_pair,
            timestamp=timestamp
        )

    def _add_order_to_book(self, order: Order):
        if order.price is None:
            return

        price = order.price
        if order.side == OrderSide.Buy:
            if price not in self.bids:
                self.bids[price] = []
            self.bids[price].append(order)
        else:
            if price not in self.asks:
                self.asks[price] = []
            self.asks[price].append(order)

    def _update_order_status(self, order: Order):
        if order.filled_quantity >= order.quantity:
            order.status = OrderStatus.Filled
        elif order.filled_quantity > 0:
            order.status = OrderStatus.PartiallyFilled
        
        if order.order_id in self.orders:
             self.orders[order.order_id] = order

    async def cancel_order(self, order_id: str, user_address: str):
        if order_id in self.orders:
            order = self.orders[order_id]
            if order.user_address != user_address:
                raise ValueError("Unauthorized")
            
            order.status = OrderStatus.Cancelled
            
            # Remove from book
            if order.price:
                target_book = self.bids if order.side == OrderSide.Buy else self.asks
                if order.price in target_book:
                    orders_at_price = target_book[order.price]
                    target_book[order.price] = [o for o in orders_at_price if o.order_id != order_id]
                    if not target_book[order.price]:
                        del target_book[order.price]

    async def get_snapshot(self) -> OrderBookSnapshot:
        # Top 20 bids (descending)
        bids_list = []
        for price in reversed(self.bids):
            orders = self.bids[price]
            total_qty = sum(o.quantity - o.filled_quantity for o in orders)
            bids_list.append(PriceLevel(price=price, quantity=total_qty))
            if len(bids_list) >= 20: break
            
        # Top 20 asks (ascending)
        asks_list = []
        for price in self.asks:
            orders = self.asks[price]
            total_qty = sum(o.quantity - o.filled_quantity for o in orders)
            asks_list.append(PriceLevel(price=price, quantity=total_qty))
            if len(asks_list) >= 20: break
            
        return OrderBookSnapshot(
            asset_pair=self.asset_pair,
            bids=bids_list,
            asks=asks_list,
            timestamp=int(time.time())
        )

    def get_order(self, order_id: str) -> Optional[Order]:
        return self.orders.get(order_id)