# TEE Integration

## Summary

Run the matching engine inside Phala Cloud TEE (Intel TDX) and expose standard HTTPS. Trust is established by attestation, not by the Certificate Authority. The TLS private key must be generated inside the TEE and never leave it; the TLS public key SPKI hash is bound into the attestation quote.

## Goals

- Prove the matching engine is running the intended code in genuine Intel TDX hardware.
- Prove the TLS keypair and Stellar keypair are generated inside the same TEE instance.
- Provide normal HTTPS for users (self-signed certificates), with attestation as the security anchor.
- Support graceful degradation outside TEE (local development) without breaking core functionality.

## Trust Model

- Certificate Authority: domain binding and browser-friendly HTTPS.
- TEE attestation: cryptographic proof of code integrity and key ownership.
- Combined: users get a clean HTTPS UX and a verifiable security proof that the TLS key is TEE-generated and matches the running code.

## TLS Strategy (Self-Signed Certificates)

Key requirement: the TLS private key is generated inside the TEE and never leaves it.

Design notes:
- Generate self-signed TLS certificates inside the container using OpenSSL.
- Do not mount or import keys/certs from the host; generate key material in-TEE.
- Bind the TLS public key via SPKI hash into the attestation reportData.
- Certificate fingerprint is informational only; trust is derived from the SPKI hash in the quote.

## Container Requirements

Install inside the container:
- OpenSSL (for TLS keypair generation, certificate creation, and SPKI extraction).
- dstack SDK runtime dependency (for quote generation).

Network ports:
- `443` for HTTPS.

File system:
- Writable path for TLS keys and certificates (inside the container).
- No host mounts for TLS keys or certs.

## Attestation Binding (Report Data)

ReportData is limited to 64 bytes. Use hashes, not raw keys.

Bind the following values:
- Stellar public key (matching engine signing key) as a hash.
- TLS public key SPKI hash (SHA256 of SPKI DER).
- Optional domain name hash.
- Optional challenge nonce for freshness.

Recommended reportData structure (conceptual):
- reportData = SHA256("stellar_pubkey|tls_spki_hash|domain|timestamp|challenge")

Return the preimage fields in the API response so verifiers can recompute the hash.

## Attestation API Design

Endpoints:
- GET /attestation
  - Returns quote, event log, vm config, reportData, and identity metadata.
  - Supports optional challenge for freshness (hex, <= 64 bytes).
- GET /info
  - Returns TCB info, compose configuration, and metadata.

Response metadata should include:
- tls_spki_hash (TLS public key SPKI hash)
- stellar_pubkey (Stellar public key / matching engine signing key)
- domain (if configured)
- timestamp

## Verification Flow (Client)

1. Connect via HTTPS (CA trust is convenience only).
2. Fetch /attestation.
3. Verify Intel TDX quote signature (Phala verification API or local verifier).
4. Verify compose-hash against the reported configuration.
5. Verify reportData recomputation matches the quote.
6. Extract TLS public key SPKI hash from the live TLS certificate and confirm it matches tls_spki_hash.

Only after steps 2-6 should the client treat the connection as trusted.

## Verification Scripts

Three scripts are provided in `scripts/` for attestation verification and demo:

### 1. Remote Verification (Recommended)

```bash
python3 scripts/verify_remote_attestation.py <base_url> [--save-cert PATH]
```

Fetches `/info` and `/attestation` from a live deployment and verifies the compose-hash and TLS certificate match.

**Examples**:
```bash
# Basic verification
python3 scripts/verify_remote_attestation.py https://c5d5291eef49362eaadcac3d3bf62eb5f3452860-443s.dstack-pha-prod9.phala.network

# Verify and save TLS certificate
python3 scripts/verify_remote_attestation.py \
  https://c5d5291eef49362eaadcac3d3bf62eb5f3452860-443s.dstack-pha-prod9.phala.network \
  --save-cert server.crt
```

**What it verifies**:
- Computes SHA256 hash of app-compose from `/info` endpoint
- Extracts attested compose-hash from event log in `/attestation` endpoint
- Confirms compose-hash matches (proves configuration integrity)
- Extracts TLS certificate and verifies SPKI hash matches attestation (requires `cryptography` package)
- Optionally saves TLS certificate in PEM format for subsequent use

**Exit codes**: 0 = success, 1 = failure (suitable for CI/CD)

**Using the Saved Certificate**:

After saving the certificate, you can pin it for secure curl requests:

```bash
# Extract public key from certificate
openssl x509 -in server.crt -pubkey -noout > server_pubkey.pem

# Use with curl (pins the public key)
curl --pinnedpubkey server_pubkey.pem https://your-deployment/api

# Or trust the certificate as a CA (for self-signed certs)
curl --cacert server.crt https://your-deployment/api
```

**Public key pinning** is recommended as it provides the strongest security guarantee - even if the certificate is reissued, the pinned public key from the TEE attestation must match.

### 2. Local Hash Computation

```bash
python3 scripts/compute_compose_hash.py [app-compose.json] [attestation.json]
```

Computes compose-hash from a local app-compose.json file.

**Examples**:
```bash
# Compute hash only
python3 scripts/compute_compose_hash.py app-compose.json

# Compute and verify against saved attestation
python3 scripts/compute_compose_hash.py app-compose.json attestation.json
```

**Use cases**:
- Pre-deployment verification
- Audit trail comparison
- Debug hash mismatches

### 3. Remote TEE Demo

```bash
./scripts/demo_remote_tee.sh <tee_base_url> [--contract-id CONTRACT_ID] [--skip-attestation]
```

Complete end-to-end demonstration with a remote TEE-deployed matching engine.

**Examples**:
```bash
# Full demo with attestation verification
./scripts/demo_remote_tee.sh https://your-tee-deployment.phala.network --contract-id YOUR_CONTRACT_ID

# Skip attestation verification (for testing)
./scripts/demo_remote_tee.sh https://your-tee-deployment.phala.network --contract-id YOUR_CONTRACT_ID --skip-attestation
```

**What it does**:
1. Verifies TEE attestation (compose-hash, TLS SPKI, report_data)
2. Extracts matching engine public key from attestation
3. Creates test accounts and deposits funds to contract vault
4. Submits matching buy/sell orders with SEP-0053 signatures
5. Verifies on-chain settlement and balance changes

**Requirements**:
- Contract must be deployed and matching engine registered
- Provide contract ID via `--contract-id` argument
- Matching engine must be accessible via HTTPS

**Note**: This script assumes the contract is already deployed. Deploy the contract first, then deploy the matching engine configured with that contract ID.

### Compose Hash Algorithm

The compose-hash is computed as:
1. Remove all `null`/`None` values from app-compose
2. Recursively sort all dictionary keys lexicographically
3. Create deterministic JSON: `json.dumps(sorted_obj, separators=(",", ":"))`
4. Return SHA256 hex digest

This deterministic hash is recorded in RTMR3 and signed by Intel TDX hardware.

### 4. Intel TDX Quote Verification

The scripts above verify compose-hash integrity but don't verify Intel's cryptographic signature. To verify the quote was signed by genuine Intel TDX hardware:

```bash
# Install dcap-qvl-cli (one-time setup)
cargo install dcap-qvl-cli

# Fetch attestation quote and convert to binary
curl -k https://your-deployment/attestation | jq -r '.quote' > quote.hex
xxd -r -p quote.hex > quote.bin

# Verify Intel TDX signature
dcap-qvl verify quote.bin
```

The `dcap-qvl` verifier checks:
- Intel's cryptographic signature on the quote
- Certificate chain back to Intel's root CA
- TCB (Trusted Computing Base) status
- Measurement registers (MRTD, RTMR0-3, reportData)

This provides local verification without relying on third-party APIs.

## Operational Considerations

- Attestation is only available inside Phala Cloud; local dev should return 503 with a clear message.
- Quote generation should be cached (short TTL) to reduce overhead.
- TLS keys are ephemeral per deployment; clients should re-verify after restart.
- **Use immutable image digests (SHA256) in deployment for reproducible measurements and security.**
  - **Do not use image tags** (e.g., `:latest`, `:v1.0.0`) as they enable an attacker to deploy their own container with the same tag, bypassing the security guarantees of attestation.
  - **Always pin the image digest** using the format: `image@sha256:<digest>`
  - Example: `ymcrcat/stellar-darkpool-matching-engine@sha256:0c6868fde4062a1da251bbd0d6c3ddca7bca28411f4853a73eea65a636d48e9e`
  - **⚠️ Important**: The `docker-compose.phala.yml` file in the repository uses an image tag for convenience. **You must edit it before deployment** to replace the tag with a pinned SHA256 digest (e.g., change `image: ymcrcat/stellar-darkpool-matching-engine:latest` to `image: ymcrcat/stellar-darkpool-matching-engine@sha256:<digest>`).
  - The compose-hash includes the image digest, so pinning to a specific hash ensures that only the exact image you've verified can be deployed.
- **Important**: Environment variables like `${SETTLEMENT_CONTRACT_ID}` are resolved at deployment time and baked into the attested compose-hash.

## Container Startup Sequence

When the Docker container starts, the following must happen in order:

1. **Detect TEE availability** - Check for `/var/run/dstack.sock`
2. **Generate ephemeral Stellar keypair** - Inside container, never imported from outside
3. **Generate TLS keypair** - Inside container using OpenSSL
4. **Create self-signed certificate** - Using OpenSSL with the generated keypair
5. **Extract TLS public key SPKI hash** - SHA256 of TLS public key in SPKI DER format
6. **Bind identities to attestation** - Combine Stellar public key + TLS public key SPKI hash into reportData
7. **Initialize attestation service** - Generate initial quote with key bindings
8. **Start HTTPS server** - Uvicorn with ssl_certfile/ssl_keyfile
9. **Expose attestation endpoints** - `/attestation` and `/info`

**Critical requirements**:
- All key generation (Stellar keypair + TLS keypair) must happen inside the container
- Never import keys from host filesystem or environment variables
- TLS public key SPKI hash must be extracted and bound to attestation quote
- Use ephemeral keys (regenerated on every container restart)

**Environment variables set**:
- Public: `STELLAR_PUBKEY`, `TLS_SPKI_HASH`, `TLS_CERT_PATH`
- Secret (in-memory only): `STELLAR_SIGNING_KEY`, `TLS_KEY_PATH`

## Security Properties

Provided:
- Hardware authenticity (Intel TDX signature).
- Code integrity (compose-hash and RTMR values).
- TLS key confinement (TLS public key SPKI hash bound to TEE).
- Identity binding (Stellar public key bound to TEE).

Not provided:
- Privacy of order data inside the enclave memory.
- Censorship resistance or liveness guarantees.

## Phased Implementation

Phase 1: Core attestation ✅ **COMPLETED**
- Add attestation service with quote generation, caching, and info endpoints.
- Bind Stellar public key to reportData.

Phase 2: TLS key binding ✅ **COMPLETED**
- Generate TLS keypair inside TEE.
- Bind TLS public key SPKI hash into reportData and expose it in attestation responses.

Phase 3: Verification tooling ✅ **COMPLETED**
- Provide scripts and docs for attestation verification and TLS public key SPKI pinning.

Phase 4: Docs and ops ✅ **COMPLETED**
- Update architecture docs, deployment guides, and local dev guidance.

## Open Decisions

- Verification cadence for clients (per session vs periodic).
- Rotation policy for TLS keypair and Stellar keypair.
