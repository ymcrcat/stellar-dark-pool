#!/usr/bin/env python3
"""
Verify remote Phala Cloud TEE attestation.

This script fetches the app-compose configuration and attestation quote
from a remote TEE instance and verifies that the compose-hash matches.

Usage:
    python verify_remote_attestation.py <base_url>

Examples:
    python verify_remote_attestation.py https://stellardark.io
    python verify_remote_attestation.py https://c5d5291eef49362e-443s.dstack-pha-prod9.phala.network

The script will:
1. Fetch app-compose JSON from {base_url}/info
2. Fetch attestation quote from {base_url}/attestation
3. Compute the compose-hash from app-compose
4. Extract the attested compose-hash from the event log
5. Verify they match

Exit codes:
    0 - Verification successful
    1 - Verification failed or error occurred
"""

import hashlib
import json
import sys
import urllib.request
import urllib.error
import ssl
from typing import Any, Dict, Optional


def sort_object(obj: Any) -> Any:
    """Recursively sort object keys lexicographically."""
    if isinstance(obj, dict):
        return {k: sort_object(v) for k, v in sorted(obj.items())}
    elif isinstance(obj, list):
        return [sort_object(item) for item in obj]
    else:
        return obj


def to_deterministic_json(obj: Any) -> str:
    """Convert to deterministic JSON (compact, sorted keys)."""
    sorted_obj = sort_object(obj)
    return json.dumps(sorted_obj, separators=(",", ":"), ensure_ascii=False)


def get_compose_hash(app_compose: Dict[str, Any]) -> str:
    """
    Compute the compose-hash exactly as dstack does.

    Args:
        app_compose: The AppCompose dictionary

    Returns:
        32-byte hex hash (64 hex characters)
    """
    # Remove None values
    cleaned = {k: v for k, v in app_compose.items() if v is not None}

    # Create deterministic JSON
    manifest_str = to_deterministic_json(cleaned)

    # SHA256 hash
    return hashlib.sha256(manifest_str.encode("utf-8")).hexdigest()


def fetch_json(url: str, allow_self_signed: bool = True) -> Dict[str, Any]:
    """
    Fetch JSON from a URL.

    Args:
        url: URL to fetch
        allow_self_signed: Allow self-signed certificates (default: True)

    Returns:
        Parsed JSON as dictionary

    Raises:
        urllib.error.URLError: If request fails
        json.JSONDecodeError: If response is not valid JSON
    """
    # Create SSL context that allows self-signed certificates and older TLS versions
    if allow_self_signed:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        # Allow all TLS versions and ciphers to match curl's behavior
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.options &= ~ssl.OP_NO_SSLv3  # Be more permissive
    else:
        ctx = ssl.create_default_context()

    # Create request with timeout
    req = urllib.request.Request(url)
    req.add_header('User-Agent', 'Mozilla/5.0 (compatible; PhalaVerifier/1.0)')

    with urllib.request.urlopen(req, context=ctx, timeout=30) as response:
        data = response.read()
        return json.loads(data)


def extract_app_compose_from_info(info_data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Extract app-compose configuration from /info endpoint response.

    Args:
        info_data: Response from /info endpoint

    Returns:
        App-compose dictionary or None if not found
    """
    # Try different possible locations for app_compose in the response
    # Some APIs return it directly, others nest it under tcb_info
    if 'app_compose' in info_data:
        app_compose = info_data['app_compose']
    elif 'tcb_info' in info_data and 'app_compose' in info_data['tcb_info']:
        app_compose = info_data['tcb_info']['app_compose']
    else:
        return None

    # If it's a string, parse it as JSON
    if isinstance(app_compose, str):
        return json.loads(app_compose)

    return app_compose


def extract_compose_hash_from_attestation(attestation_data: Dict[str, Any]) -> Optional[str]:
    """
    Extract compose-hash from attestation event log.

    Args:
        attestation_data: Response from /attestation endpoint

    Returns:
        Compose-hash string or None if not found
    """
    event_log_str = attestation_data.get('event_log')
    if not event_log_str:
        return None

    # Parse event log if it's a string
    if isinstance(event_log_str, str):
        event_log = json.loads(event_log_str)
    else:
        event_log = event_log_str

    # Find compose-hash event
    for event in event_log:
        if event.get('event') == 'compose-hash':
            return event.get('event_payload')

    return None


def verify_remote_attestation(base_url: str, verbose: bool = True) -> bool:
    """
    Verify remote TEE attestation by comparing compose hashes.

    Args:
        base_url: Base URL of the TEE instance
        verbose: Print detailed output

    Returns:
        True if verification passes, False otherwise
    """
    # Normalize base URL (remove trailing slash)
    base_url = base_url.rstrip('/')

    if verbose:
        print(f"Verifying attestation for: {base_url}")
        print("=" * 70)
        print()

    # Step 1: Fetch app-compose from /info
    info_url = f"{base_url}/info"
    if verbose:
        print(f"[1/4] Fetching app-compose from {info_url}")

    try:
        info_data = fetch_json(info_url)
        if verbose:
            print("      ✓ Successfully fetched /info")
    except urllib.error.URLError as e:
        print(f"      ✗ Error fetching /info: {e}")
        return False
    except json.JSONDecodeError as e:
        print(f"      ✗ Invalid JSON from /info: {e}")
        return False

    # Extract app-compose from response
    app_compose = extract_app_compose_from_info(info_data)
    if not app_compose:
        print("      ✗ Could not find app_compose in /info response")
        return False

    if verbose:
        print("      ✓ Extracted app-compose configuration")
        print()

    # Step 2: Compute compose-hash
    if verbose:
        print("[2/4] Computing compose-hash from app-compose")

    try:
        computed_hash = get_compose_hash(app_compose)
        if verbose:
            print(f"      ✓ Computed: {computed_hash}")
            print()
    except Exception as e:
        print(f"      ✗ Error computing hash: {e}")
        return False

    # Step 3: Fetch attestation from /attestation
    attestation_url = f"{base_url}/attestation"
    if verbose:
        print(f"[3/4] Fetching attestation from {attestation_url}")

    try:
        attestation_data = fetch_json(attestation_url)
        if verbose:
            print("      ✓ Successfully fetched /attestation")
    except urllib.error.URLError as e:
        print(f"      ✗ Error fetching /attestation: {e}")
        return False
    except json.JSONDecodeError as e:
        print(f"      ✗ Invalid JSON from /attestation: {e}")
        return False

    # Extract compose-hash from event log
    attested_hash = extract_compose_hash_from_attestation(attestation_data)
    if not attested_hash:
        print("      ✗ Could not find compose-hash in attestation event log")
        return False

    if verbose:
        print(f"      ✓ Attested:  {attested_hash}")
        print()

    # Step 4: Compare hashes
    if verbose:
        print("[4/4] Verifying compose-hash match")

    if computed_hash == attested_hash:
        if verbose:
            print("      ✓ Hashes match!")
            print()
            print("=" * 70)
            print("✅ VERIFICATION SUCCESSFUL")
            print("=" * 70)
            print()
            print("The TEE is running the declared configuration.")
            print("The compose-hash in the attestation matches the app-compose.")
        return True
    else:
        if verbose:
            print("      ✗ Hashes DO NOT match!")
            print()
            print("=" * 70)
            print("❌ VERIFICATION FAILED")
            print("=" * 70)
            print()
            print(f"  Expected (computed): {computed_hash}")
            print(f"  Got (attested):      {attested_hash}")
            print()
            print("The TEE may be running a different configuration than declared.")
        return False


def main():
    if len(sys.argv) < 2:
        print("Usage: python verify_remote_attestation.py <base_url>")
        print()
        print("Examples:")
        print("  python verify_remote_attestation.py https://stellardark.io")
        print("  python verify_remote_attestation.py https://app-id-443s.dstack-pha-prod9.phala.network")
        sys.exit(1)

    base_url = sys.argv[1]

    try:
        success = verify_remote_attestation(base_url)
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\nUnexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
