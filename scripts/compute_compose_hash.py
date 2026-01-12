#!/usr/bin/env python3
"""
Compute the compose-hash from app-compose.json.

This script computes the SHA256 hash of the app-compose configuration
using deterministic JSON serialization (sorted keys, compact format).

The hash can be compared against the attested compose-hash in the
attestation quote to verify the TEE is running the expected configuration.

Usage:
    python compute_compose_hash.py [app-compose-file] [attestation-file]

Examples:
    # Compute hash only
    python compute_compose_hash.py

    # Compute and verify against attestation
    python compute_compose_hash.py app-compose.json attestation.json
"""

import hashlib
import json
import sys
from typing import Any, Dict


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
    # Compact JSON with no extra whitespace
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


def main():
    # Parse command line arguments
    compose_file = sys.argv[1] if len(sys.argv) > 1 else 'app-compose.json'
    attestation_file = sys.argv[2] if len(sys.argv) > 2 else None

    # Read app-compose.json
    try:
        with open(compose_file, 'r') as f:
            app_compose = json.load(f)
    except FileNotFoundError:
        print(f"Error: File '{compose_file}' not found")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in '{compose_file}': {e}")
        sys.exit(1)

    # Compute hash
    computed_hash = get_compose_hash(app_compose)
    print(f"Computed compose-hash: {computed_hash}")

    # If attestation file provided, verify against it
    if attestation_file:
        try:
            with open(attestation_file, 'r') as f:
                attestation = json.load(f)

            event_log = json.loads(attestation['event_log'])
            attested_hash = next(
                e['event_payload']
                for e in event_log
                if e.get('event') == 'compose-hash'
            )

            print(f"Attested compose-hash: {attested_hash}")
            print()

            if computed_hash == attested_hash:
                print("✅ MATCH! The compose-hash matches the attestation.")
                sys.exit(0)
            else:
                print("❌ MISMATCH! The hashes do not match.")
                print(f"  Expected: {computed_hash}")
                print(f"  Got:      {attested_hash}")
                sys.exit(1)

        except FileNotFoundError:
            print(f"Error: File '{attestation_file}' not found")
            sys.exit(1)
        except (json.JSONDecodeError, KeyError, StopIteration) as e:
            print(f"Error: Failed to parse attestation file: {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
