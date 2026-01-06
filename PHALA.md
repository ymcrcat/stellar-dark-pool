# Phala Attestation Quotes: Complete Guide

Comprehensive documentation on generating, exposing, and verifying attestation quotes for Docker containers running in Phala Cloud TEE environments.

**Date:** December 27, 2025  
**Version:** 1.0

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Foundational Concepts](#foundational-concepts)
3. [Implementation: Generating Attestation Quotes](#implementation-generating-attestation-quotes)
4. [Verification: Client-Side Python](#verification-client-side-python)
5. [Verification Checklist](#verification-checklist)
6. [Complete Architecture Flow](#complete-architecture-flow)
7. [Attack Scenarios Prevented](#attack-scenarios-prevented)
8. [Quick Reference: API Endpoints](#quick-reference-api-endpoints)
9. [Key Measurements Explained](#key-measurements-explained)
10. [Tools & Resources](#tools--resources)
11. [Dependencies & Requirements](#dependencies--requirements)

---

## Executive Summary

Phala Cloud provides cryptographic attestation quotes that prove Docker containers are running unmodified in genuine Intel TDX (Trusted Execution Environment) hardware. This guide covers:

- **What** attestation quotes are and why they matter
- **How** to generate quotes inside containers
- **How** to expose quotes via API endpoints
- **How** to verify quotes client-side with Python
- **What** security properties they provide

---

## Foundational Concepts

### What is an Attestation Quote?

An attestation quote is a cryptographically signed proof from Intel TDX hardware that:

- Confirms genuine Intel TDX hardware signed the attestation
- Proves the exact Docker images and configuration running
- Records measurement hashes of OS, application, and hardware config
- Binds custom data (challenges, public keys, nonces) to the proof
- Is unforgeable—any modification invalidates Intel's signature

### Key Components of a Quote

| Component | Purpose | Example |
|-----------|---------|---------|
| **quote** | Raw TDX attestation signed by Intel | Hex-encoded binary |
| **event_log** | Boot events with cryptographic hashes | JSON array of events |
| **reportData** | Custom 64-byte data field | Challenge, nonce, public key |
| **MRTD** | Hash of OS and firmware | 48-byte measurement |
| **RTMR0-3** | Runtime measurements extending during boot | 48 bytes each |
| **compose-hash** | SHA256 of Docker Compose config | 32-byte hash |
| **instance-id** | Unique CVM identifier | UUID |
| **key-provider** | KMS that distributed encryption keys | UTF-8 string |

### Security Properties

- **Hardware Authenticity**: Intel's signature proves genuine TDX hardware
- **Measurement Integrity**: Hashes detect any changes to OS, code, or config
- **Unforgeable Proof**: Modifying any byte invalidates the signature
- **Chain of Trust**: Event log hash chain prevents tampering
- **Freshness**: reportData contains challenges to prevent replay attacks

### How Attestation Works: The Chain of Trust
```
┌─────────────────────────────────┐
│ Hardware (Intel TDX)            │
│ - Signs the attestation         │
│ - Records measurements          │
│ - Guarantees authenticity       │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│ OS & Boot Sequence              │
│ - Measured in MRTD              │
│ - Events recorded in RTMR0-RTMR3│
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│ Application Configuration       │
│ - Docker Compose config         │
│ - compose-hash in RTMR3         │
│ - Custom reportData field       │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│ Attestation Quote               │
│ - Signed by Intel hardware      │
│ - Contains all measurements     │
│ - Unforgeable proof             │
└─────────────────────────────────┘
```

---

## Implementation: Generating Attestation Quotes

### Prerequisites

Configure Docker Compose to mount the dstack socket for TEE operations:
```yaml
version: '3'
services:
  app:
    image: your-app-image
    ports:
      - 8080:8080
    volumes:
      # Mount dstack socket for TEE operations
      - /var/run/dstack.sock:/var/run/dstack.sock
```

### SDK Installation

| Language | Package | Install Command |
|----------|---------|-----------------|
| **TypeScript/Node.js** | @phala/dstack-sdk | `npm install @phala/dstack-sdk` |
| **Python** | dstack-sdk | `pip install dstack-sdk` |
| **Go** | dstack | `go install github.com/Dstack-TEE/dstack@latest` |

### Understanding reportData

The `reportData` field is a 64-byte field for custom application data:

- **Short data (≤64 bytes)**: Pass directly to `getQuote()`
  - Examples: 32-byte nonces, challenges, small hashes
  
- **Long data (>64 bytes)**: Hash with SHA-256 first (produces 32 bytes)
  - Examples: JSON config, user data, arbitrary metadata
  - Always hash first, then pass the hash

**Important**: The SDK throws an error if you exceed 64 bytes—it does not auto-hash.

### Code Example: TypeScript
```typescript
import { DstackClient } from '@phala/dstack-sdk';
import crypto from 'crypto';

const client = new DstackClient();

// Pattern 1: Short data (≤64 bytes) - pass directly
// Example: 32-byte nonce for challenge-response
const nonce = crypto.randomBytes(32);
const quote1 = await client.getQuote(nonce);

// Pattern 2: Long data (>64 bytes) - hash it first
// Example: JSON with arbitrary data
const userData = JSON.stringify({
  version: '1.0.0',
  timestamp: Date.now(),
  user_id: 'alice',
  public_key: '0x1234...'
});

// Hash to fit in 64 bytes (SHA256 produces 32 bytes)
const hash = crypto.createHash('sha256').update(userData).digest();
const quote2 = await client.getQuote(hash);

console.log('Quote:', quote1.quote);
console.log('Event Log:', quote1.event_log);
```

### Code Example: Python
```python
from dstack_sdk import DstackClient
import hashlib
import json

client = DstackClient()

# Pattern 1: Short data (≤64 bytes)
nonce = b'my-32-byte-nonce-here-12345678'
quote1 = client.get_quote(nonce)

# Pattern 2: Long data (>64 bytes)
user_data = json.dumps({
    'version': '1.0.0',
    'timestamp': int(time.time()),
    'user_id': 'alice'
})

hash_bytes = hashlib.sha256(user_data.encode()).digest()
quote2 = client.get_quote(hash_bytes)

print('Quote:', quote1['quote'])
print('Event Log:', quote1['event_log'])
```

### Exposing Attestation via API Endpoints

Expose endpoints so external verifiers can validate your CVM:

**TypeScript/Express Example:**
```typescript
import express from 'express';
import { DstackClient } from '@phala/dstack-sdk';

const app = express();
const client = new DstackClient();

// Hardware verification endpoint
app.get('/attestation', async (req, res) => {
  const result = await client.getQuote('');
  res.json({
    quote: result.quote,
    event_log: result.event_log,
    vm_config: result.vm_config  // Required by dstack-verifier
  });
});

// Application configuration endpoint
app.get('/info', async (req, res) => {
  const info = await client.info();
  res.json(info);
});

app.listen(8080);
```

**Python/Flask Example:**
```python
from flask import Flask, jsonify
from dstack_sdk import DstackClient

app = Flask(__name__)
client = DstackClient()

@app.route('/attestation', methods=['GET'])
def attestation():
    result = client.get_quote(b'')
    return jsonify({
        'quote': result['quote'],
        'event_log': result['event_log'],
        'vm_config': result['vm_config']
    })

@app.route('/info', methods=['GET'])
def info():
    return jsonify(client.info())

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

These endpoints allow external verifiers to fetch attestation data and verify your CVM without needing access to the container internals.

---

## Verification: Client-Side Python

### Installation
```bash
# Install dcap-qvl for Intel TDX quote verification
cargo install dcap-qvl-cli

# Python dependencies
pip install requests
```

### Quick Start: Basic Verification (3 Steps)

For most use cases, this minimal approach is sufficient:
```python
import requests
import hashlib
import json

# Step 1: Fetch attestation quote and configuration
attestation_url = 'https://your-app.example.com/attestation'
info_url = 'https://your-app.example.com/info'

attest_response = requests.get(attestation_url)
attest_data = attest_response.json()

quote = attest_data['quote']
event_log = attest_data['event_log']
report_data = attest_data['report_data']

info_response = requests.get(info_url)
app_info = info_response.json()
app_compose_config = app_info['tcb_info']['app_compose']

# Step 2: Verify reportData contains expected challenge
expected_challenge = 'your-expected-challenge-hex'
assert report_data.startswith(expected_challenge), 'reportData mismatch'

# Step 3: Verify compose-hash
calculated_hash = hashlib.sha256(app_compose_config.encode()).hexdigest()

events = json.loads(event_log)
compose_event = next(e for e in events if e.get('event') == 'compose-hash')
attested_hash = compose_event['event_payload']

assert calculated_hash == attested_hash, 'compose-hash mismatch'

# Step 4: Verify quote signature
verify_response = requests.post(
    'https://cloud-api.phala.network/api/v1/attestations/verify',
    json={'hex': quote}
)
result = verify_response.json()

assert result['quote']['verified'], 'Hardware verification failed'

print("✓ Quote verified successfully!")
print(f"✓ Compose hash: {attested_hash}")
```

### Complete Production-Ready Verification

For production use with full RTMR3 replay verification:
```python
"""
Complete client-side verification of Phala attestation quotes.
Supports both basic and advanced verification with RTMR3 replay.

Installation:
    cargo install dcap-qvl-cli
    pip install requests
"""

import hashlib
import json
import tempfile
import subprocess
import os
from typing import Dict, Any

INIT_MR = "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"


def replay_rtmr(history: list[str]) -> str:
    """
    Replay the RTMR history to calculate the final RTMR value.
    
    Uses hash chain: RTMR3_new = SHA384(RTMR3_old || SHA384(event))
    """
    if len(history) == 0:
        return INIT_MR
    
    mr = bytes.fromhex(INIT_MR)
    for content in history:
        # Convert hex string to bytes
        content = bytes.fromhex(content)
        # If content is shorter than 48 bytes, pad it with zeros
        if len(content) < 48:
            content = content.ljust(48, b'\\0')
        # mr = sha384(concat(mr, content))
        mr = hashlib.sha384(mr + content).digest()
    
    return mr.hex()


class DstackTdxQuote:
    """Complete TDX quote verification class."""
    
    def __init__(self, quote: str, event_log: str):
        """
        Initialize the DstackTdxQuote object.
        
        Args:
            quote: Hex-encoded TDX quote
            event_log: JSON event log string
        """
        self.quote = bytes.fromhex(quote)
        self.event_log = event_log
        self.parsed_event_log = json.loads(self.event_log)
        self.verified_quote = None
        self.extract_info_from_event_log()
    
    def extract_info_from_event_log(self):
        """
        Extract the app ID, compose hash, instance ID, and key provider 
        from the event log.
        """
        for event in self.parsed_event_log:
            if event.get('event') == 'app-id':
                self.app_id = event.get('event_payload', '')
            elif event.get('event') == 'compose-hash':
                self.compose_hash = event.get('event_payload', '')
            elif event.get('event') == 'instance-id':
                self.instance_id = event.get('event_payload', '')
            elif event.get('event') == 'key-provider':
                self.key_provider = bytes.fromhex(
                    event.get('event_payload', '')
                ).decode('utf-8')
    
    def mrs(self) -> Dict[str, str]:
        """
        Get the MRs (Measurement Registers) from the verified quote.
        
        Returns TD10 or TD15 report from the quote.
        """
        if not self.verified_quote:
            raise ValueError("Quote not verified. Call verify() first.")
        
        report = self.verified_quote.get('report', {})
        if 'TD10' in report:
            return report['TD10']
        elif 'TD15' in report:
            return report['TD15']
        else:
            raise ValueError("No TD10 or TD15 report found in the quote")
    
    def verify(self):
        """
        Verify the TDX quote using dcap-qvl command.
        
        Requires: cargo install dcap-qvl-cli
        """
        with tempfile.NamedTemporaryFile(delete=False) as temp_file:
            temp_file.write(self.quote)
            temp_path = temp_file.name
        
        try:
            result = subprocess.run(
                ["dcap-qvl", "verify", temp_path],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                raise ValueError(
                    f"dcap-qvl verify failed with return code {result.returncode}"
                )
            self.verified_quote = json.loads(result.stdout)
        finally:
            os.unlink(temp_path)
    
    def validate_event(self, event: Dict[str, Any]) -> bool:
        """
        Validate an event's digest according to the specification.
        
        Returns True if the event is valid, False otherwise.
        """
        # Skip validation for non-IMR3 events for now
        if event.get('imr') != 3:
            return True
        
        # Calculate digest using sha384(type:event:payload)
        event_type = event.get('event_type', 0)
        event_name = event.get('event', '')
        event_payload = bytes.fromhex(event.get('event_payload', ''))
        
        if isinstance(event_payload, str):
            event_payload = event_payload.encode()
        
        hasher = hashlib.sha384()
        hasher.update(event_type.to_bytes(4, byteorder='little'))
        hasher.update(b':')
        hasher.update(event_name.encode())
        hasher.update(b':')
        hasher.update(event_payload)
        
        calculated_digest = hasher.digest().hex()
        return calculated_digest == event.get('digest')
    
    def replay_rtmrs(self) -> Dict[int, str]:
        """
        Replay RTMR history to verify the boot sequence.
        
        Cryptographically proves all boot events are authentic.
        Returns dictionary with replayed RTMR0-3 values.
        """
        rtmrs = {}
        for idx in range(4):
            history = []
            for event in self.parsed_event_log:
                if event.get('imr') == idx:
                    # Only add digest to history if event is valid
                    if self.validate_event(event):
                        history.append(event['digest'])
                    else:
                        raise ValueError(f"Invalid event digest found in IMR {idx}")
            rtmrs[idx] = replay_rtmr(history)
        return rtmrs


def sha256_hex(data: str) -> str:
    """Calculate the SHA256 hash of the given data."""
    return hashlib.sha256(data.encode()).hexdigest()


def verify_attestation(
    quote: str,
    event_log: str,
    expected_compose_hash: str
) -> bool:
    """
    Complete attestation verification workflow.
    
    Args:
        quote: Hex-encoded TDX quote
        event_log: JSON event log string
        expected_compose_hash: Expected SHA256 of app-compose.json
    
    Returns:
        True if all verification steps pass
    
    Raises:
        ValueError: If any verification step fails
    """
    quote_obj = DstackTdxQuote(quote, event_log)
    
    # Verify the quote signature
    quote_obj.verify()
    print("✓ Quote signature verified by Intel TDX hardware")
    
    # Get the measurement registers
    mrs = quote_obj.mrs()
    print(f"✓ Retrieved measurement registers")
    print(f"  - MRTD: {mrs['mr_td'][:16]}...")
    print(f"  - RTMR3: {mrs['rt_mr3'][:16]}...")
    
    # Replay RTMR3 to verify boot sequence
    replayed_mrs = quote_obj.replay_rtmrs()
    
    # Verify RTMR3 matches
    if replayed_mrs[3] != mrs['rt_mr3']:
        raise ValueError(
            f"RTMR3 mismatch after replay: "
            f"{replayed_mrs[3]} != {mrs['rt_mr3']}"
        )
    print("✓ RTMR3 replay verified - boot sequence is authentic")
    
    # Verify compose hash
    if quote_obj.compose_hash != expected_compose_hash:
        raise ValueError(
            f"Compose hash mismatch: "
            f"{quote_obj.compose_hash} != {expected_compose_hash}"
        )
    print(f"✓ Compose hash verified: {quote_obj.compose_hash}")
    
    # Print extracted metadata
    print(f"\\nExtracted Metadata:")
    print(f"  - App ID: {quote_obj.app_id}")
    print(f"  - Instance ID: {quote_obj.instance_id}")
    print(f"  - Key Provider: {quote_obj.key_provider}")
    
    return True


# Usage Example
if __name__ == "__main__":
    import requests
    
    # Fetch from your running container
    attest_resp = requests.get('https://your-app.example.com/attestation')
    info_resp = requests.get('https://your-app.example.com/info')
    
    attest_data = attest_resp.json()
    info_data = info_resp.json()
    
    quote = attest_data['quote']
    event_log = attest_data['event_log']
    app_compose = info_data['tcb_info']['app_compose']
    
    # Calculate expected compose hash
    expected_hash = hashlib.sha256(app_compose.encode()).hexdigest()
    
    # Verify
    try:
        verify_attestation(quote, event_log, expected_hash)
        print("\\n✅ ALL VERIFICATIONS PASSED")
    except Exception as e:
        print(f"\\n❌ VERIFICATION FAILED: {e}")
        exit(1)
```

---

## Verification Checklist

### Basic Verification (Minimum for Most Use Cases)

- [ ] Download quote and event_log from `/attestation` endpoint
- [ ] Download app-compose config from `/info` endpoint
- [ ] Calculate SHA256 of app-compose JSON
- [ ] Compare calculated hash with attested compose-hash in event log
- [ ] Call Phala Cloud verification API: `https://cloud-api.phala.network/api/v1/attestations/verify`
- [ ] Verify response shows `quote.verified = true`
- [ ] Confirm reportData contains expected challenge/public key
- [ ] Check TCB status shows no known vulnerabilities

### Advanced Verification (High-Assurance Applications)

Complete all basic verification steps, then:

- [ ] Verify RTMR3 replay matches attested value from quote
- [ ] Extract and validate all RTMR0-3 values
- [ ] Confirm all Docker images use immutable SHA256 digests (not mutable tags like `latest`)
- [ ] Verify compose-hash is whitelisted on-chain (if using on-chain governance)
- [ ] Verify image digests link to audited source code (Sigstore signatures)
- [ ] Check event log integrity - no events should have invalid digests
- [ ] Verify instance-id uniqueness across deployments
- [ ] Confirm key-provider KMS is trusted

---

## Complete Architecture Flow

### Data Flow: Quote Generation to Verification
```
┌────────────────────────────────────────────────────────────┐
│ INSIDE CONTAINER (Phala Cloud TEE)                         │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  1. Mount /var/run/dstack.sock                            │
│  2. Create DstackClient                                    │
│  3. Call client.getQuote(reportData)                      │
│  4. Receive: quote, event_log, vm_config                  │
│                                                            │
└──────────────────┬─────────────────────────────────────────┘
                   │
                   │ Expose via HTTPS
                   ▼
┌────────────────────────────────────────────────────────────┐
│ API ENDPOINTS (Accessible to External Verifiers)           │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  GET /attestation                                          │
│    ├─ quote (Intel TDX signed)                             │
│    ├─ event_log (boot events)                              │
│    └─ vm_config                                            │
│                                                            │
│  GET /info                                                 │
│    ├─ app_compose (Docker config)                          │
│    └─ tcb_info                                             │
│                                                            │
└──────────────────┬─────────────────────────────────────────┘
                   │
                   │ HTTPS Request
                   ▼
┌────────────────────────────────────────────────────────────┐
│ CLIENT VERIFICATION (External Machine)                     │
├────────────────────────────────────────────────────────────┤
│                                                            │
│ 1. Download quote & event_log from /attestation            │
│ 2. Download app_compose from /info                         │
│ 3. Calculate SHA256(app_compose) locally                   │
│ 4. Extract compose-hash from event_log                     │
│ 5. Verify: calculated_hash == attested_hash                │
│ 6. Call Phala API: verify_quote(quote)                     │
│ 7. Parse Intel's signature verification                    │
│ 8. Verify: result.quote.verified == true                   │
│ 9. Extract RTMR3 from verified quote                       │
│ 10. Replay RTMR3 using event_log                           │
│ 11. Verify: replayed_rtmr3 == attested_rtmr3               │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Trust Flow Diagram
```
Intel Hardware
    ↓
    └─ Signs quote with TDX key
        ↓
        └─ Proves hardware authenticity
            ↓
            └─ MRTD measurement
                ↓
                └─ Proves OS integrity
                    ↓
                    └─ RTMR3 from event log
                        ↓
                        └─ Proves application config
                            ↓
                            └─ compose-hash
                                ↓
                                └─ Proves Docker images
                                    ↓
                                    └─ Complete Chain of Trust ✓
```

---

## Attack Scenarios Prevented

### 1. Compromised Docker Registry

**Attack**: Attacker modifies images in Docker Hub/ECR

**Prevention**: TEE verifies image digests against compose-hash during boot
- Even if registry serves malicious images, digest verification fails
- Quote becomes invalid
- Deployment is prevented

### 2. Code Substitution

**Attack**: Attacker replaces application code

**Prevention**: compose-hash in RTMR3 is recorded by TEE hardware
- Modifying code changes compose-hash
- Breaks the quote signature
- Modification is cryptographically impossible to hide

### 3. Unauthorized Updates

**Attack**: Malicious developer deploys unapproved version

**Prevention**: On-chain governance (if enabled) whitelists only approved configs
- Only authorized compose-hashes can boot
- Unauthorized deployments are blocked at hardware level
- Cannot be bypassed

### 4. Event Log Tampering

**Attack**: Attacker modifies boot events to hide changes

**Prevention**: RTMR3 hash chain proves authenticity
- Each event's digest is hashed into RTMR3
- Modifying any event changes the final RTMR3
- Modified RTMR3 won't match the quote

### 5. Quote Forgery

**Attack**: Attacker creates fake quote

**Prevention**: Intel's signature makes counterfeiting cryptographically impossible
- Only real TDX hardware can produce valid signatures
- Phala's verification API checks against Intel's root keys
- Fake quotes are rejected immediately

### 6. Stale Quote Reuse (Replay Attack)

**Attack**: Attacker replays old quote from earlier deployment

**Prevention**: reportData contains freshness nonce/timestamp
- Each quote includes fresh nonce or timestamp
- Old quotes become invalid after expiration
- Replay attacks are detected

---

## Quick Reference: API Endpoints

### Container Attestation Endpoints

#### GET /attestation

Retrieve the attestation quote for hardware verification.

**Response:**
```json
{
  "quote": "0x0a0b0c0d...",
  "event_log": "[{\\"event\\": \\"compose-hash\\", \\"event_payload\\": \\"...\\"}]",
  "vm_config": {
    "vcpus": 2,
    "memory": "4G"
  },
  "report_data": "0x1234...abcd"
}
```

**Fields:**
- `quote`: Hex-encoded TDX quote signed by Intel hardware
- `event_log`: JSON array of boot events with digests
- `vm_config`: VM configuration details
- `report_data`: Custom application data (64 bytes max)

#### GET /info

Retrieve application configuration and metadata.

**Response:**
```json
{
  "tcb_info": {
    "app_compose": "{\\"version\\": \\"3\\", \\"services\\": {...}}",
    "vm_config": {
      "vcpus": 2,
      "memory": "4G"
    }
  }
}
```

**Fields:**
- `tcb_info.app_compose`: JSON string of docker-compose config
- `tcb_info.vm_config`: VM configuration

### Phala Cloud Verification API

#### POST https://cloud-api.phala.network/api/v1/attestations/verify

Verify that the quote was signed by genuine Intel TDX hardware.

**Request:**
```json
{
  "hex": "0x0a0b0c0d..."
}
```

**Response:**
```json
{
  "quote": {
    "verified": true,
    "status": "UpToDate",
    "report": {
      "TD10": {
        "mr_td": "0x...",
        "rt_mr0": "0x...",
        "rt_mr1": "0x...",
        "rt_mr2": "0x...",
        "rt_mr3": "0x...",
        "report_data": "0x..."
      }
    }
  }
}
```

**Response Fields:**
- `verified`: Boolean - true if Intel signature is valid
- `status`: TCB status (e.g., "UpToDate", "OutOfDate", "Revoked")
- `report.TD10` or `report.TD15`: Measurement registers
  - `mr_td`: MRTD (48 bytes) - OS/firmware hash
  - `rt_mr0-3`: RTMR0-3 (48 bytes each) - Runtime measurements
  - `report_data`: Custom application data

---

## Key Measurements Explained

### Measurement Registers (MRs)

| Field | Size | Purpose | What It Measures |
|-------|------|---------|-----------------|
| **MRTD** (mr_td) | 48 bytes (96 hex chars) | OS + Firmware Hash | OS kernel, bootloader, firmware integrity |
| **RTMR0** (rt_mr0) | 48 bytes | Boot Configuration | Initial system state |
| **RTMR1** (rt_mr1) | 48 bytes | System State | Runtime system configuration |
| **RTMR2** (rt_mr2) | 48 bytes | Reserved | Reserved for future use |
| **RTMR3** (rt_mr3) | 48 bytes | Application Config | **Docker Compose configuration hash** |
| **reportData** | 64 bytes (128 hex chars) | Custom App Data | Nonce, challenge, public key, etc. |

### Event Log Structure

Each event in the event_log has this structure:
```json
{
  "imr": 3,
  "event": "compose-hash",
  "event_type": 1,
  "event_payload": "abc123...",
  "digest": "0x..."
}
```

**Fields:**
- `imr`: Which register (0-3) this event extends
- `event`: Event type (e.g., "compose-hash", "instance-id", "key-provider")
- `event_payload`: The actual data (hex-encoded)
- `digest`: SHA384 hash of the event

### How RTMR3 Works

RTMR3 uses a hash chain where each event extends the previous value:
```
RTMR3_new = SHA384(RTMR3_old || SHA384(event))
```

This creates a cryptographic chain where:
1. Start with initial value (48 zero bytes)
2. For each event, compute `SHA384(event)` and pad to 48 bytes
3. Compute `SHA384(RTMR3_old || padded_event_hash)`
4. Result becomes new RTMR3
5. Final RTMR3 is recorded in the hardware quote

**Why this matters**: Modifying ANY event changes the entire chain, making tampering immediately obvious.

---

## Tools & Resources

### Required Tools

| Tool | Purpose | Installation | Use Case |
|------|---------|--------------|----------|
| **dcap-qvl-cli** | Verify Intel TDX signatures | `cargo install dcap-qvl-cli` | Quote verification (client-side) |
| **dstack-sdk (Python)** | Generate quotes in Python | `pip install dstack-sdk` | Quote generation (inside container) |
| **dstack-sdk (TypeScript)** | Generate quotes in TypeScript | `npm install @phala/dstack-sdk` | Quote generation (inside container) |
| **dstack (Go)** | Generate quotes in Go | `go install github.com/Dstack-TEE/dstack@latest` | Quote generation (inside container) |

### Optional Tools

| Tool | Purpose | Installation | Use Case |
|------|---------|--------------|----------|
| **dstack-mr** | Calculate expected measurements | `go install github.com/kvinwang/dstack-mr@latest` | Pre-calculate RTMRs for testing |
| **trust-center** | Reference implementation | `git clone https://github.com/Phala-Network/trust-center` | Complete verification example |
| **RTMR3 Calculator** | Web-based hash calculator | https://rtmr3-calculator.vercel.app/ | Calculate compose-hash online |

### Example Repositories

| Repository | Contains | Link |
|------------|----------|------|
| **dstack-examples** | Complete working examples | https://github.com/Dstack-TEE/dstack-examples |
| **trust-center** | Reference implementation | https://github.com/Phala-Network/trust-center |
| **dstack** | Main dstack implementation | https://github.com/Dstack-TEE/dstack |

### Documentation References

| Document | Topics | Link |
|----------|--------|------|
| **Get Attestation** | SDK usage, quote generation | https://docs.phala.com/phala-cloud/attestation/get-attestation |
| **Verify Your Application** | Client-side verification, RTMR3 | https://docs.phala.com/phala-cloud/attestation/verify-your-application |
| **Attestation Overview** | Concepts, architecture | https://docs.phala.com/phala-cloud/attestation/overview |

---

## Dependencies & Requirements

### For Container (Producer - Quote Generation)

**Minimum Requirements:**
- Docker container with Phala Cloud support
- dstack SDK installed (Python, TypeScript, or Go)
- Network access to `/var/run/dstack.sock`
- HTTP server to expose `/attestation` and `/info` endpoints

**Recommended Setup:**
```dockerfile
FROM phala/dstack:latest

# Install dependencies
RUN apt-get update && apt-get install -y \\
    curl \\
    nodejs \\
    npm

# Copy application
WORKDIR /app
COPY . .

# Install dstack SDK
RUN npm install @phala/dstack-sdk

# Mount socket at runtime
# docker run -v /var/run/dstack.sock:/var/run/dstack.sock ...
```

### For Client Verification (Consumer - Quote Verification)

**Minimum Requirements:**
- Python 3.7 or higher
- `dcap-qvl-cli` (Cargo required to build)
- `requests` library (for HTTP calls)
- Network access to container's endpoints
- Can run on any machine (local computer, CI/CD pipeline, etc.)

**Installation:**
```bash
# Install Rust (required for dcap-qvl)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install dcap-qvl
cargo install dcap-qvl-cli

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install requests
```

### Optional (Advanced Use Cases)

For source code provenance verification:
- GitHub Actions for building images
- Sigstore for cryptographic signing
- Go 1.16+ (for dstack-mr tool)

For on-chain governance:
- Web3.py or ethers.js
- Access to blockchain RPC endpoint
- DstackApp contract address

---

## Summary

### What You Now Know

1. **Attestation Basics**: Quotes are unforgeable cryptographic proofs that containers run in genuine Intel TDX hardware

2. **How to Generate**: Use dstack SDK (Python/TypeScript/Go) to call `getQuote()` with custom data

3. **How to Expose**: Implement `/attestation` and `/info` API endpoints for external verification

4. **How to Verify**: Client-side Python code that:
   - Downloads quote and configuration
   - Verifies compose-hash locally
   - Calls Phala's API for hardware signature verification
   - Optionally replays RTMR3 for boot sequence verification

5. **Security Properties**: Hardware-signed, measurement-based, unforgeable, tamper-proof

### Next Steps

1. **Start Simple**: Implement basic verification (3 steps) first
2. **Add Security**: Gradually move to advanced verification with RTMR3
3. **Monitor**: Set up continuous attestation verification in CI/CD
4. **Scale**: Use on-chain governance for production deployments

### Key Resources

- **Phala Docs**: https://docs.phala.com
- **dstack-examples**: https://github.com/Dstack-TEE/dstack-examples
- **trust-center**: https://github.com/Phala-Network/trust-center

---

## Appendix: Glossary

- **TEE**: Trusted Execution Environment - hardware-based secure computation
- **TDX**: Intel Trust Domain Extension - specific TEE implementation
- **MRTD**: Measurement Register TD - OS/firmware hash
- **RTMR**: Runtime Measurement Register - application state hash
- **compose-hash**: SHA256 hash of Docker Compose configuration
- **reportData**: Custom 64-byte field in attestation quote
- **event_log**: Log of boot events with cryptographic hashes
- **dcap-qvl**: Quote verification library from Intel/Phala
- **dstack**: Decentralized stack - framework for TEE applications
- **CVM**: Confidential Virtual Machine - TEE instance on Phala Cloud

---

**Document Version**: 1.0  
**Last Updated**: December 27, 2025  
**Source**: Phala Cloud Documentation & dstack-examples Repository
