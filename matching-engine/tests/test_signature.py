"""
Unit tests for order signature verification.
"""
import pytest
import json
import base64
import hashlib
from decimal import Decimal
from stellar_sdk import Keypair

from src.stellar import StellarService
from src.types import Order, OrderSide, OrderType, TimeInForce, AssetPair


def test_create_order_message():
    """Test order message creation matches expected format."""
    stellar_service = StellarService()

    order = Order(
        order_id="test-123",
        user_address="GAXYZ...",
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        expiration=None,
        signature="sig"
    )

    message = stellar_service.create_order_message(order)

    expected = "order_id:test-123|user:GAXYZ...|pair:XLM/USDC|side:Buy|type:Limit|price:1.5|quantity:100|tif:GTC|timestamp:1234567890"
    assert message == expected


def test_create_order_message_with_expiration():
    """Test order message creation with expiration."""
    stellar_service = StellarService()

    order = Order(
        order_id="test-123",
        user_address="GAXYZ...",
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Sell,
        order_type=OrderType.Limit,
        price=Decimal("2.0"),
        quantity=Decimal("50"),
        time_in_force=TimeInForce.IOC,
        timestamp=1234567890,
        expiration=1234577890,
        signature="sig"
    )

    message = stellar_service.create_order_message(order)

    assert "expiration:1234577890" in message


def test_sign_and_verify_order():
    """Test signing an order and verifying the signature."""
    stellar_service = StellarService()
    keypair = Keypair.random()

    order = Order(
        order_id="test-456",
        user_address=keypair.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature=""
    )

    # Create message and sign
    message = stellar_service.create_order_message(order)
    prefix = "Stellar Signed Message:\n"
    full_message = (prefix + message).encode("utf-8")
    message_hash = hashlib.sha256(full_message).digest()

    signature_bytes = keypair.sign(message_hash)
    signature = base64.b64encode(signature_bytes).decode('ascii')

    # Verify
    is_valid = stellar_service.verify_order_signature(order, signature, keypair.public_key)

    assert is_valid


def test_verify_invalid_signature():
    """Test that invalid signatures are rejected."""
    stellar_service = StellarService()
    keypair = Keypair.random()

    order = Order(
        order_id="test-789",
        user_address=keypair.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature=""
    )

    # Use wrong signature
    fake_signature = base64.b64encode(b"fake" * 16).decode('ascii')

    is_valid = stellar_service.verify_order_signature(order, fake_signature, keypair.public_key)

    assert not is_valid


def test_verify_signature_wrong_public_key():
    """Test that signature verification fails with wrong public key."""
    stellar_service = StellarService()
    keypair1 = Keypair.random()
    keypair2 = Keypair.random()

    order = Order(
        order_id="test-999",
        user_address=keypair1.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature=""
    )

    # Sign with keypair1
    message = stellar_service.create_order_message(order)
    prefix = "Stellar Signed Message:\n"
    full_message = (prefix + message).encode("utf-8")
    message_hash = hashlib.sha256(full_message).digest()

    signature_bytes = keypair1.sign(message_hash)
    signature = base64.b64encode(signature_bytes).decode('ascii')

    # Verify with keypair2 (wrong key)
    is_valid = stellar_service.verify_order_signature(order, signature, keypair2.public_key)

    assert not is_valid


def test_signature_tampering_detection():
    """Test that signature verification detects order tampering."""
    stellar_service = StellarService()
    keypair = Keypair.random()

    order = Order(
        order_id="test-tamper",
        user_address=keypair.public_key,
        asset_pair=AssetPair(base="XLM", quote="USDC"),
        side=OrderSide.Buy,
        order_type=OrderType.Limit,
        price=Decimal("1.5"),
        quantity=Decimal("100"),
        time_in_force=TimeInForce.GTC,
        timestamp=1234567890,
        signature=""
    )

    # Sign order
    message = stellar_service.create_order_message(order)
    prefix = "Stellar Signed Message:\n"
    full_message = (prefix + message).encode("utf-8")
    message_hash = hashlib.sha256(full_message).digest()

    signature_bytes = keypair.sign(message_hash)
    signature = base64.b64encode(signature_bytes).decode('ascii')

    # Tamper with order (change quantity)
    order.quantity = Decimal("200")

    # Verify should fail
    is_valid = stellar_service.verify_order_signature(order, signature, keypair.public_key)

    assert not is_valid
