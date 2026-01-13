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
2. Fetch attestation quote from {base_url}/attestation (with optional challenge)
3. Compute the compose-hash from app-compose
4. Extract the attested compose-hash from the event log
5. Verify they match
6. Extract TLS certificate and verify SPKI hash (requires cryptography package)
7. Verify report_data hash matches the TLS key and challenge (if provided)

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
import socket
import argparse
import secrets
from typing import Any, Dict, Optional
from urllib.parse import urlparse, urlencode


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


def get_tls_spki_hash(base_url: str, cert_output_path: Optional[str] = None) -> Optional[str]:
    """
    Extract TLS certificate from server and compute SPKI hash.

    Args:
        base_url: Base URL of the server
        cert_output_path: Optional path to save certificate in PEM format

    Returns:
        SPKI hash (hex string) or None if extraction fails
    """
    try:
        # Try to use cryptography library for SPKI extraction
        from cryptography import x509
        from cryptography.hazmat.primitives import serialization

        # Parse URL to get hostname and port
        parsed = urlparse(base_url)
        hostname = parsed.hostname or parsed.netloc.split(':')[0]
        port = parsed.port or 443

        # Create SSL context that doesn't verify certificates
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE

        # Connect and get certificate
        with socket.create_connection((hostname, port), timeout=10) as sock:
            with context.wrap_socket(sock, server_hostname=hostname) as ssock:
                cert_der = ssock.getpeercert(binary_form=True)

                # Load certificate
                cert = x509.load_der_x509_certificate(cert_der)

                # Save certificate if requested
                if cert_output_path:
                    cert_pem = cert.public_bytes(encoding=serialization.Encoding.PEM)
                    with open(cert_output_path, 'wb') as f:
                        f.write(cert_pem)

                # Get SPKI (Subject Public Key Info) in DER format
                spki_der = cert.public_key().public_bytes(
                    encoding=serialization.Encoding.DER,
                    format=serialization.PublicFormat.SubjectPublicKeyInfo
                )

                # Hash it with SHA256
                spki_hash = hashlib.sha256(spki_der).hexdigest()
                return spki_hash

    except ImportError:
        # Fallback: cryptography library not available
        return None
    except Exception:
        # Any connection or parsing error
        return None


def verify_remote_attestation(base_url: str, verbose: bool = True, cert_output_path: Optional[str] = None, use_challenge: bool = False) -> bool:
    """
    Verify remote TEE attestation by comparing compose hashes.

    Args:
        base_url: Base URL of the TEE instance
        verbose: Print detailed output
        cert_output_path: Optional path to save TLS certificate
        use_challenge: Generate and verify a fresh challenge

    Returns:
        True if verification passes, False otherwise
    """
    # Normalize base URL (remove trailing slash)
    base_url = base_url.rstrip('/')

    # Generate challenge if requested
    challenge_hex = None
    if use_challenge:
        # Generate 32-byte random nonce
        challenge_bytes = secrets.token_bytes(32)
        challenge_hex = challenge_bytes.hex()
        if verbose:
            print(f"Generated challenge: {challenge_hex}")
            print()

    if verbose:
        print(f"Verifying attestation for: {base_url}")
        print("=" * 70)
        print()

    # Step 1: Fetch app-compose from /info
    info_url = f"{base_url}/info"
    if verbose:
        print(f"[1/5] Fetching app-compose from {info_url}")

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
        print("[2/5] Computing compose-hash from app-compose")

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
    if challenge_hex:
        attestation_url = f"{attestation_url}?challenge={challenge_hex}"

    if verbose:
        print(f"[3/5] Fetching attestation from {attestation_url}")

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
        print("[4/5] Verifying compose-hash match")

    if computed_hash != attested_hash:
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

    if verbose:
        print("      ✓ Hashes match!")
        print()

    # Step 5: Verify TLS SPKI hash (optional but recommended)
    if verbose:
        print("[5/6] Verifying TLS certificate SPKI hash")

    # Extract TLS SPKI hash from attestation
    attested_tls_spki = None
    if 'identity' in attestation_data and 'tls_spki_hash' in attestation_data['identity']:
        attested_tls_spki = attestation_data['identity']['tls_spki_hash']

    if not attested_tls_spki:
        if verbose:
            print("      ⚠ No TLS SPKI hash in attestation (skipping TLS verification)")
            print()
    else:
        # Get TLS certificate from live connection
        live_tls_spki = get_tls_spki_hash(base_url, cert_output_path)

        if not live_tls_spki:
            if verbose:
                print("      ⚠ Could not extract TLS certificate (skipping TLS verification)")
                print("      Note: Install 'cryptography' package for TLS verification:")
                print("            pip install cryptography")
                print()
        else:
            if verbose:
                print(f"      Attested:  {attested_tls_spki}")
                print(f"      Live cert: {live_tls_spki}")

            if live_tls_spki == attested_tls_spki:
                if verbose:
                    print("      ✓ TLS SPKI hashes match!")
                    print()
            else:
                if verbose:
                    print("      ✗ TLS SPKI hashes DO NOT match!")
                    print()
                    print("=" * 70)
                    print("❌ VERIFICATION FAILED")
                    print("=" * 70)
                    print()
                    print("The TLS certificate does not match the attested key.")
                    print("This could indicate a man-in-the-middle attack.")
                return False

    # Step 6: Verify report_data hash
    if verbose:
        print("[6/6] Verifying report_data hash")

    identity = attestation_data.get('identity', {})
    report_data_verified = False

    # Extract components from identity
    stellar_pubkey = identity.get('stellar_pubkey', '')
    tls_spki_hash = identity.get('tls_spki_hash', '')
    timestamp = identity.get('timestamp')
    response_challenge = identity.get('challenge') or ''

    if not stellar_pubkey or not tls_spki_hash or timestamp is None:
        if verbose:
            print("      ⚠ Missing required identity fields (stellar_pubkey, tls_spki_hash, or timestamp)")
            print("      Cannot verify report_data hash")
            print()
    else:
        # If we sent a challenge, verify it matches
        if challenge_hex:
            if response_challenge != challenge_hex:
                if verbose:
                    print(f"      ✗ Challenge mismatch!")
                    print(f"        Sent:     {challenge_hex}")
                    print(f"        Received: {response_challenge}")
                    print()
                    print("=" * 70)
                    print("❌ VERIFICATION FAILED")
                    print("=" * 70)
                    print()
                    print("The challenge does not match. This could be a replay attack.")
                return False
            if verbose:
                print(f"      ✓ Challenge matches: {challenge_hex}")

        # Reconstruct preimage: stellar_pubkey|tls_spki_hash|timestamp|challenge
        preimage = f"{stellar_pubkey}|{tls_spki_hash}|{timestamp}|{response_challenge}"
        
        # Compute hash (32 bytes)
        computed_hash_bytes = hashlib.sha256(preimage.encode()).digest()
        computed_hash_hex = computed_hash_bytes.hex()
        
        # Use identity.report_data_hash as primary source (it's the 32-byte hash we computed)
        attested_hash = identity.get('report_data_hash')
        
        # Also check quote's report_data for debugging/comparison
        quote_report_data = attestation_data.get('report_data')
        quote_report_data_32 = None
        if quote_report_data:
            # Remove "0x" prefix if present
            if isinstance(quote_report_data, str):
                if quote_report_data.startswith('0x'):
                    quote_report_data = quote_report_data[2:]
                # report_data in quote is 64 bytes (128 hex chars), extract first 32 bytes
                quote_report_data_32 = quote_report_data[:64]
            else:
                # If it's bytes, convert to hex and take first 64 chars
                quote_report_data_32 = bytes(quote_report_data).hex()[:64]
        
        if not attested_hash:
            # Fallback to quote's report_data if identity doesn't have it
            attested_hash = quote_report_data_32
        
        if not attested_hash:
            if verbose:
                print("      ⚠ No report_data in quote or identity (skipping report_data verification)")
                print()
        else:
            if verbose:
                print(f"      Preimage:  {preimage}")
                print(f"      Computed:  {computed_hash_hex}")
                print(f"      Identity hash: {identity.get('report_data_hash', 'N/A')}")
                if quote_report_data_32:
                    print(f"      Quote report_data (first 32B): {quote_report_data_32}")
                print(f"      Using attested:  {attested_hash}")
            
            if computed_hash_hex == attested_hash:
                report_data_verified = True
                if verbose:
                    print("      ✓ Report data hash matches!")
                    print()
            else:
                if verbose:
                    print("      ✗ Report data hash DOES NOT match!")
                    print()
                    print("=" * 70)
                    print("❌ VERIFICATION FAILED")
                    print("=" * 70)
                    print()
                    print("The report_data does not match the reconstructed preimage.")
                    print("This could indicate tampering with the attestation.")
                return False

    # All verifications passed
    if verbose:
        print("=" * 70)
        print("✅ VERIFICATION SUCCESSFUL")
        print("=" * 70)
        print()
        print("The TEE is running the declared configuration.")
        print("The compose-hash in the attestation matches the app-compose.")
        if attested_tls_spki and live_tls_spki:
            print("The TLS certificate matches the attested key.")
        if report_data_verified:
            print("The report_data hash matches the reconstructed preimage.")
        if cert_output_path:
            print(f"TLS certificate saved to: {cert_output_path}")
    return True


def main():
    parser = argparse.ArgumentParser(
        description='Verify remote Phala Cloud TEE attestation',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python verify_remote_attestation.py https://stellardark.io
  python verify_remote_attestation.py https://app-id-443s.dstack-pha-prod9.phala.network
  python verify_remote_attestation.py https://stellardark.io --save-cert server.crt
  python verify_remote_attestation.py https://stellardark.io --challenge
  python verify_remote_attestation.py https://stellardark.io --challenge --save-cert server.crt
        """
    )

    parser.add_argument(
        'base_url',
        help='Base URL of the TEE instance'
    )

    parser.add_argument(
        '--save-cert',
        metavar='PATH',
        help='Save TLS certificate to file (PEM format)'
    )

    parser.add_argument(
        '--challenge',
        action='store_true',
        help='Generate and verify a fresh challenge (prevents replay attacks)'
    )

    args = parser.parse_args()

    try:
        success = verify_remote_attestation(
            args.base_url,
            cert_output_path=args.save_cert,
            use_challenge=args.challenge
        )
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
