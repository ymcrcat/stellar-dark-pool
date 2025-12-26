from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from typing import List, Optional
import time
import uuid
import logging
from decimal import Decimal

from .types import (
    Order, OrderSide, OrderType, TimeInForce, OrderStatus, AssetPair,
    Trade, OrderBookSnapshot, SettlementInstruction
)
from .engine import engine, MatchingEngine
from .stellar import stellar_service
from .config import settings

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("api")

app = FastAPI(title="Stellar Dark Pool Matching Engine")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request Models
from pydantic import BaseModel

class SubmitOrderRequest(BaseModel):
    order_id: Optional[str] = None
    user_address: str
    asset_pair: AssetPair
    side: OrderSide
    order_type: OrderType
    price: Optional[Decimal] = None
    quantity: Decimal
    time_in_force: TimeInForce
    timestamp: Optional[int] = None
    expiration: Optional[int] = None
    signature: str

class SubmitOrderResponse(BaseModel):
    order_id: str
    status: str
    trades: List[Trade]

# Dependency
def get_engine():
    return engine

@app.post("/api/v1/orders", response_model=SubmitOrderResponse)
async def submit_order(req: SubmitOrderRequest, eng: MatchingEngine = Depends(get_engine)):
    # Validate
    if req.quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be positive")
    if req.price is not None and req.price <= 0:
        raise HTTPException(status_code=400, detail="Price must be positive")

    order_id = req.order_id or str(uuid.uuid4())
    timestamp = req.timestamp or int(time.time())

    order = Order(
        order_id=order_id,
        user_address=req.user_address,
        asset_pair=req.asset_pair,
        side=req.side,
        order_type=req.order_type,
        price=req.price,
        quantity=req.quantity,
        time_in_force=req.time_in_force,
        timestamp=timestamp,
        expiration=req.expiration,
        signature=req.signature
    )

    # Verify Signature
    if not stellar_service.verify_order_signature(order, req.signature, req.user_address):
        raise HTTPException(status_code=401, detail="Invalid signature")
    
    order.signature = req.signature # Ensure set

    try:
        trades = await eng.submit_order(order)
        return SubmitOrderResponse(
            order_id=order_id,
            status="submitted",
            trades=trades
        )
    except ValueError as e:
        if "Insufficient" in str(e):
            raise HTTPException(status_code=402, detail=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v1/orders/{order_id}")
async def get_order(order_id: str, asset_pair: str, eng: MatchingEngine = Depends(get_engine)):
    # Parse asset pair string "BASE/QUOTE"
    parts = asset_pair.split("/")
    if len(parts) != 2:
        raise HTTPException(status_code=400, detail="Invalid asset_pair format")
    
    pair = AssetPair(base=parts[0], quote=parts[1])
    
    order = await eng.get_order(order_id, pair)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return order

@app.delete("/api/v1/orders/{order_id}")
async def cancel_order(order_id: str, user_address: str, asset_pair: str, eng: MatchingEngine = Depends(get_engine)):
    parts = asset_pair.split("/")
    if len(parts) != 2:
        raise HTTPException(status_code=400, detail="Invalid asset_pair format")
    
    pair = AssetPair(base=parts[0], quote=parts[1])
    
    try:
        await eng.cancel_order(order_id, user_address, pair)
        return {"status": "cancelled"}
    except ValueError as e:
        raise HTTPException(status_code=403, detail=str(e))

@app.get("/api/v1/orderbook/{pair:path}", response_model=OrderBookSnapshot)
async def get_order_book(pair: str, eng: MatchingEngine = Depends(get_engine)):
    # pair will catch "XLM/USDC" even if it contains slashes
    if "/" in pair:
        parts = pair.split("/")
    elif "-" in pair:
         parts = pair.split("-")
    else:
         raise HTTPException(status_code=400, detail="Invalid pair format")

    if len(parts) != 2:
        raise HTTPException(status_code=400, detail="Invalid pair format")

    ap = AssetPair(base=parts[0], quote=parts[1])
    return await eng.get_orderbook_snapshot(ap)

@app.get("/api/v1/balances")
async def get_balances(user_address: str, token: str):
    # Retrieve balance
    try:
        contract_id = stellar_service.get_contract_address(token)
        balance = await stellar_service.get_vault_balance(user_address, contract_id)
        
        return {
            "user_address": user_address,
            "asset": token,
            "contract_id": contract_id,
            "balance": str(balance),
            "balance_raw": balance,
            "cached": False
        }
    except Exception as e:
        logger.error(f"Balance check error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/settlement/submit")
async def submit_settlement(instruction: SettlementInstruction):
    try:
        tx_hash = await stellar_service.sign_and_submit_settlement(instruction)
        return {
            "status": "submitted",
            "transaction_hash": tx_hash,
            "message": "Settlement transaction signed and submitted successfully"
        }
    except Exception as e:
        logger.error(f"Settlement submission failed: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": int(time.time())}
