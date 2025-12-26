#!/usr/bin/env python3
"""
Helper script to sign orders using Stellar account keys.
This ensures signature compatibility with stellar-sdk.
"""

import sys
import json
import base64

try:
    from stellar_sdk import Keypair
except ImportError:
    print("Error: stellar-sdk not installed", file=sys.stderr)
    print("Install with: pip install stellar-sdk", file=sys.stderr)
    sys.exit(1)


def sign_order(secret_key_strkey: str, order_json: str) -> str:
    """
    Sign an order using a Stellar secret key.
    
    Args:
        secret_key_strkey: Stellar secret key in StrKey format (starts with 'S')
        order_json: JSON string of the order to sign
    """
    # Parse order
    order = json.loads(order_json)
    
    # Create order message (matching Rust format)
    parts = []
    parts.append(f"order_id:{order['order_id']}")
    parts.append(f"user:{order['user_address']}")
    parts.append(f"pair:{order['asset_pair']['base']}/{order['asset_pair']['quote']}")
    parts.append(f"side:{order['side']}")
    parts.append(f"type:{order['order_type']}")
    
    if order.get('price') is not None:
        parts.append(f"price:{order['price']}")
    
    parts.append(f"quantity:{order['quantity']}")
    parts.append(f"tif:{order['time_in_force']}")
    parts.append(f"timestamp:{order['timestamp']}")
    
    if order.get('expiration') is not None:
        parts.append(f"expiration:{order['expiration']}")
    
    order_message = "|".join(parts)
    
    # SEP-0053: Prefix message
    sep0053_prefix = "Stellar Signed Message:\n"
    payload = sep0053_prefix.encode() + order_message.encode()
    
    # Hash payload (SHA-256)
    import hashlib
    digest = hashlib.sha256(payload).digest()
    
    # Create keypair from secret
    keypair = Keypair.from_secret(secret_key_strkey)
    
    # Sign the hash (SEP-0053)
    signature_bytes = keypair.sign(digest)
    
    # Return base64-encoded signature
    return base64.b64encode(signature_bytes).decode('ascii')


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 sign_order.py <secret_key_strkey> <order_json>", file=sys.stderr)
        print("\nExample:", file=sys.stderr)
        print("  python3 sign_order.py S... '{\"order_id\":\"123\",...}'", file=sys.stderr)
        sys.exit(1)
    
    secret_key = sys.argv[1]
    order_json = sys.argv[2]
    
    try:
        signature = sign_order(secret_key, order_json)
        print(signature)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
