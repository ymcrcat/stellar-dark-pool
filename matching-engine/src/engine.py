import logging
import time
import asyncio
from typing import Dict, List, Optional
from decimal import Decimal

from .types import Order, OrderSide, Trade, AssetPair, SettlementInstruction, OrderBookSnapshot
from .orderbook import OrderBook
from .stellar import stellar_service
from .config import settings

logger = logging.getLogger(__name__)

class MatchingEngine:
    def __init__(self):
        self.orderbook: Optional[OrderBook] = None
        self.base_asset: Optional[str] = None
        self.quote_asset: Optional[str] = None
        # Vault Balances: user:contract_id -> amount (i128)
        self.vault_balances: Dict[str, int] = {} 
        self._initialized = False

    async def initialize(self):
        if self._initialized:
            return
            
        try:
            # Fetch supported assets from contract
            self.base_asset = await stellar_service.get_asset_a()
            self.quote_asset = await stellar_service.get_asset_b()
            
            self.orderbook = OrderBook(AssetPair(base=self.base_asset, quote=self.quote_asset))
            self._initialized = True
            logger.info(f"Matching Engine initialized for {self.base_asset}/{self.quote_asset}")
        except Exception as e:
            logger.error(f"Failed to initialize Matching Engine: {e}")
            # Fallback to defaults from environment if possible, or wait
            pass

    async def submit_order(self, order: Order) -> List[Trade]:
        if not self._initialized:
            await self.initialize()

        # 1. Validate assets - convert to contract addresses for comparison
        order_base_contract = stellar_service.get_contract_address(order.asset_pair.base)
        order_quote_contract = stellar_service.get_contract_address(order.asset_pair.quote)

        if order_base_contract != self.base_asset or order_quote_contract != self.quote_asset:
             # Try reverse? Or just reject
             if order_base_contract == self.quote_asset and order_quote_contract == self.base_asset:
                 pass # Could handle reverse pairs but let's keep it simple
             else:
                 raise ValueError(f"Unsupported asset pair: {order.asset_pair.base}/{order.asset_pair.quote} (contracts: {order_base_contract}/{order_quote_contract} vs {self.base_asset}/{self.quote_asset})")

        # 2. Check Vault Balance
        await self._check_balance(order)

        # 3. Match
        trades = await self.orderbook.match_order(order)
        
        # 4. Update internal balances
        for trade in trades:
            await self._process_trade(trade)
            
        return trades

    async def _check_balance(self, order: Order):
        # Determine required asset
        if order.side == OrderSide.Buy:
            asset_addr = self.quote_asset
            if order.price:
                req_amount = order.quantity * order.price
            else:
                req_amount = Decimal("0")
        else:
            asset_addr = self.base_asset
            req_amount = order.quantity

        try:
            cache_key = f"{order.user_address}:{asset_addr}"
            
            # Get balance (cache or fetch)
            if cache_key in self.vault_balances:
                balance = self.vault_balances[cache_key]
            else:
                balance = await stellar_service.get_vault_balance(order.user_address, asset_addr)
                self.vault_balances[cache_key] = balance
            
            # req_amount to stroops (scaled 10^7)
            req_i128 = int(req_amount * Decimal("10000000"))
            
            if balance < req_i128:
                raise ValueError(f"Insufficient vault balance: {balance} < {req_i128}")
                
        except ValueError as e:
            raise e
        except Exception as e:
            logger.warning(f"Balance check failed for {order.user_address}: {e}")

    async def _process_trade(self, trade: Trade):
        try:
            base_amt = int(trade.quantity * Decimal("10000000"))
            quote_amt = int(trade.quantity * trade.price * Decimal("10000000"))
            
            # Buyer: +Base, -Quote
            self._update_local_balance(trade.buy_user, self.base_asset, base_amt)
            self._update_local_balance(trade.buy_user, self.quote_asset, -quote_amt)
            
            # Seller: -Base, +Quote
            self._update_local_balance(trade.sell_user, self.base_asset, -base_amt)
            self._update_local_balance(trade.sell_user, self.quote_asset, quote_amt)
            
            # Trigger settlement in background or return for API to handle
            # For this simple implementation, we'll let the client trigger settlement
            # via the /api/v1/settlement/submit endpoint
            
        except Exception as e:
            logger.error(f"Error updating local balances: {e}")

    def _update_local_balance(self, user: str, asset_addr: str, delta: int):
        key = f"{user}:{asset_addr}"
        if key in self.vault_balances:
            self.vault_balances[key] += delta

    async def cancel_order(self, order_id: str, user_address: str, asset_pair: AssetPair):
        if not self._initialized: await self.initialize()
        await self.orderbook.cancel_order(order_id, user_address)

    async def get_order(self, order_id: str, asset_pair: AssetPair) -> Optional[Order]:
        if not self._initialized: await self.initialize()
        return self.orderbook.get_order(order_id)

    async def get_orderbook_snapshot(self, asset_pair: AssetPair) -> OrderBookSnapshot:
        if not self._initialized: await self.initialize()
        return await self.orderbook.get_snapshot()

engine = MatchingEngine()
