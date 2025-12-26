from enum import Enum
from typing import Optional, List
from decimal import Decimal
from pydantic import BaseModel, Field

class OrderSide(str, Enum):
    Buy = "Buy"
    Sell = "Sell"

class OrderType(str, Enum):
    Limit = "Limit"
    Market = "Market"

class TimeInForce(str, Enum):
    GTC = "GTC"  # Good Till Cancel
    IOC = "IOC"  # Immediate Or Cancel
    FOK = "FOK"  # Fill Or Kill

class OrderStatus(str, Enum):
    Pending = "Pending"
    PartiallyFilled = "PartiallyFilled"
    Filled = "Filled"
    Cancelled = "Cancelled"
    Expired = "Expired"
    Rejected = "Rejected"

class AssetPair(BaseModel):
    base: str
    quote: str

    class Config:
        frozen = True  # Make it hashable

class Order(BaseModel):
    order_id: str
    user_address: str
    asset_pair: AssetPair
    side: OrderSide
    order_type: OrderType
    price: Optional[Decimal] = None
    quantity: Decimal
    filled_quantity: Decimal = Field(default_factory=lambda: Decimal("0"))
    time_in_force: TimeInForce
    timestamp: int
    expiration: Optional[int] = None
    signature: str = ""
    status: OrderStatus = OrderStatus.Pending

class Trade(BaseModel):
    trade_id: str
    buy_order_id: str
    sell_order_id: str
    price: Decimal
    quantity: Decimal
    buy_user: str
    sell_user: str
    asset_pair: AssetPair
    timestamp: int

class SettlementInstruction(BaseModel):
    trade_id: str
    buy_user: str
    sell_user: str
    base_asset: str
    quote_asset: str
    base_amount: int  # i128
    quote_amount: int
    fee_base: int = 0
    fee_quote: int = 0
    timestamp: int

class PriceLevel(BaseModel):
    price: Decimal
    quantity: Decimal

class OrderBookSnapshot(BaseModel):
    asset_pair: AssetPair
    bids: List[PriceLevel]
    asks: List[PriceLevel]
    timestamp: int