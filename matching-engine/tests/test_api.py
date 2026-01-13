"""
Integration tests for API endpoints.
"""
import pytest
from fastapi.testclient import TestClient
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock, patch
from stellar_sdk import Keypair

from src.api import app
from src.types import AssetPair


@pytest.fixture
def client():
    """Create test client."""
    return TestClient(app)


@pytest.fixture
def mock_engine():
    """Mock matching engine."""
    with patch('src.api.engine') as mock:
        mock._initialized = True
        mock.base_asset = "CXLMCONTRACT"
        mock.quote_asset = "CUSDCCONTRACT"
        mock.submit_order = AsyncMock(return_value=[])
        mock.get_order = AsyncMock(return_value=None)
        mock.cancel_order = AsyncMock()
        mock.get_orderbook_snapshot = AsyncMock(return_value={
            "asset_pair": {"base": "XLM", "quote": "USDC"},
            "bids": [],
            "asks": [],
            "timestamp": 1234567890
        })
        yield mock


@pytest.fixture
def mock_stellar():
    """Mock stellar service."""
    with patch('src.api.stellar_service') as mock:
        mock.verify_order_signature = MagicMock(return_value=True)
        mock.get_contract_address = MagicMock(side_effect=lambda x: f"C{x}CONTRACT")
        mock.get_vault_balance = AsyncMock(return_value=1000000000)
        yield mock


def test_health_check(client):
    """Test health check endpoint."""
    response = client.get("/health")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "timestamp" in data


def test_submit_order_valid(client, mock_engine, mock_stellar):
    """Test submitting a valid order."""
    keypair = Keypair.random()

    order_data = {
        "user_address": keypair.public_key,
        "asset_pair": {"base": "XLM", "quote": "USDC"},
        "side": "Buy",
        "order_type": "Limit",
        "price": 1.5,
        "quantity": 100,
        "time_in_force": "GTC",
        "timestamp": 1234567890,
        "signature": "test-signature"
    }

    response = client.post("/api/v1/orders", json=order_data)

    assert response.status_code == 200
    data = response.json()
    assert "order_id" in data
    assert data["status"] == "submitted"
    assert "trades" in data


def test_submit_order_invalid_signature(client, mock_engine, mock_stellar):
    """Test submitting order with invalid signature."""
    mock_stellar.verify_order_signature = MagicMock(return_value=False)

    keypair = Keypair.random()

    order_data = {
        "user_address": keypair.public_key,
        "asset_pair": {"base": "XLM", "quote": "USDC"},
        "side": "Buy",
        "order_type": "Limit",
        "price": 1.5,
        "quantity": 100,
        "time_in_force": "GTC",
        "timestamp": 1234567890,
        "signature": "invalid-signature"
    }

    response = client.post("/api/v1/orders", json=order_data)

    assert response.status_code == 401
    assert "Invalid signature" in response.json()["detail"]


def test_submit_order_invalid_quantity(client, mock_engine, mock_stellar):
    """Test submitting order with invalid quantity."""
    keypair = Keypair.random()

    order_data = {
        "user_address": keypair.public_key,
        "asset_pair": {"base": "XLM", "quote": "USDC"},
        "side": "Buy",
        "order_type": "Limit",
        "price": 1.5,
        "quantity": -100,
        "time_in_force": "GTC",
        "timestamp": 1234567890,
        "signature": "test-signature"
    }

    response = client.post("/api/v1/orders", json=order_data)

    assert response.status_code == 400
    assert "Quantity must be positive" in response.json()["detail"]


def test_submit_order_invalid_price(client, mock_engine, mock_stellar):
    """Test submitting order with invalid price."""
    keypair = Keypair.random()

    order_data = {
        "user_address": keypair.public_key,
        "asset_pair": {"base": "XLM", "quote": "USDC"},
        "side": "Buy",
        "order_type": "Limit",
        "price": -1.5,
        "quantity": 100,
        "time_in_force": "GTC",
        "timestamp": 1234567890,
        "signature": "test-signature"
    }

    response = client.post("/api/v1/orders", json=order_data)

    assert response.status_code == 400
    assert "Price must be positive" in response.json()["detail"]


def test_get_orderbook(client, mock_engine, mock_stellar):
    """Test getting orderbook."""
    response = client.get("/api/v1/orderbook/XLM/USDC")

    assert response.status_code == 200
    data = response.json()
    assert "bids" in data
    assert "asks" in data
    assert "timestamp" in data


def test_get_orderbook_invalid_format(client, mock_engine, mock_stellar):
    """Test getting orderbook with invalid format."""
    response = client.get("/api/v1/orderbook/INVALID")

    assert response.status_code == 400


def test_get_balances(client, mock_engine, mock_stellar):
    """Test getting user balance."""
    keypair = Keypair.random()

    response = client.get(
        f"/api/v1/balances?user_address={keypair.public_key}&token=XLM"
    )

    assert response.status_code == 200
    data = response.json()
    assert "balance" in data
    assert "user_address" in data
    assert data["user_address"] == keypair.public_key


def test_attestation_no_tee(client):
    """Test attestation endpoint when TEE is not available (normal local case)."""
    response = client.get("/attestation")
    
    assert response.status_code == 503
    assert "TEE attestation not available" in response.json()["detail"]


def test_attestation_with_challenge_no_tee(client):
    """Test attestation endpoint with challenge when TEE is not available."""
    response = client.get("/attestation?challenge=deadbeef")
    
    assert response.status_code == 503
    assert "TEE attestation not available" in response.json()["detail"]


def test_info_no_tee(client):
    """Test info endpoint when TEE is not available."""
    response = client.get("/info")
    
    assert response.status_code == 503
    assert "TEE info not available" in response.json()["detail"]
