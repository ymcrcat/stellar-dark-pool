# TEE Integration

## Summary

Run the matching engine inside Phala Cloud TEE (Intel TDX) and expose standard HTTPS. Trust is established by attestation, not by the Certificate Authority. The TLS private key must be generated inside the TEE and never leave it; the TLS public key SPKI hash is bound into the attestation quote.

## Goals

- Prove the matching engine is running the intended code in genuine Intel TDX hardware.
- Prove the TLS keypair and Stellar keypair are generated inside the same TEE instance.
- Provide normal HTTPS for users (ACME/Let's Encrypt for domain UX), with attestation as the security anchor.
- Support graceful degradation outside TEE (local development) without breaking core functionality.

## Trust Model

- Certificate Authority: domain binding and browser-friendly HTTPS.
- TEE attestation: cryptographic proof of code integrity and key ownership.
- Combined: users get a clean HTTPS UX and a verifiable security proof that the TLS key is TEE-generated and matches the running code.

## TLS Strategy (ACME in TEE)

Key requirement: the TLS private key is generated inside the TEE and never leaves it.

Design notes:
- Use ACME (Let's Encrypt) inside the container to issue a certificate for the domain.
- Do not mount or import keys/certs from the host; generate key material in-TEE.
- Bind the TLS public key via SPKI hash into the attestation reportData.
- Certificate fingerprint is informational only; trust is derived from the SPKI hash in the quote.

Challenge options:
- http-01: requires port 80.
- tls-alpn-01: requires port 443 and ALPN support.

## Container Requirements

Install inside the container:
- ACME client (choose one): `certbot`, `lego`, or `acme.sh`.
- OpenSSL (for SPKI extraction and hashing).
- dstack SDK runtime dependency (for quote generation).
- CA root bundle (for outbound ACME calls).

Network ports:
- `80` if using http-01.
- `443` for HTTPS and tls-alpn-01.

File system:
- Writable path for ACME state and issued certs (inside the container).
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
- GET /api/v1/attestation
  - Returns quote, event log, vm config, reportData, and identity metadata.
  - Supports optional challenge for freshness (hex, <= 64 bytes).
- GET /api/v1/info
  - Returns TCB info, compose configuration, and metadata.
- Optional GET /api/v1/tls/certificate
  - Returns certificate PEM for client-side SPKI extraction.

Response metadata should include:
- tls_spki_hash (TLS public key SPKI hash)
- stellar_pubkey (Stellar public key / matching engine signing key)
- domain (if configured)
- timestamp

## Verification Flow (Client)

1. Connect via HTTPS (CA trust is convenience only).
2. Fetch /api/v1/attestation.
3. Verify Intel TDX quote signature (Phala verification API or local verifier).
4. Verify compose-hash against the reported configuration.
5. Verify reportData recomputation matches the quote.
6. Extract TLS public key SPKI hash from the live TLS certificate and confirm it matches tls_spki_hash.

Only after steps 2-6 should the client treat the connection as trusted.

## Operational Considerations

- Attestation is only available inside Phala Cloud; local dev should return 503 with a clear message.
- Quote generation should be cached (short TTL) to reduce overhead.
- TLS keys are ephemeral per deployment; clients should re-verify after restart.
- Use immutable image digests in deployment for reproducible measurements.

## Container Startup Sequence

When the Docker container starts, the following must happen in order:

1. **Detect TEE availability** - Check for `/var/run/dstack.sock`
2. **Generate ephemeral Stellar keypair** - Inside container, never imported from outside
3. **Generate TLS keypair** - Inside container (via ACME client or OpenSSL)
4. **Obtain certificate** - ACME/Let's Encrypt (if domain configured) or self-signed
5. **Extract TLS public key SPKI hash** - SHA256 of TLS public key in SPKI DER format
6. **Bind identities to attestation** - Combine Stellar public key + TLS public key SPKI hash into reportData
7. **Initialize attestation service** - Generate initial quote with key bindings
8. **Start HTTPS server** - Uvicorn with ssl_certfile/ssl_keyfile
9. **Expose attestation endpoints** - `/api/v1/attestation` and `/api/v1/info`

**Critical requirements**:
- All key generation (Stellar keypair + TLS keypair) must happen inside the container
- Never import keys from host filesystem or environment variables
- Do not mount `/etc/letsencrypt` from outside the container
- TLS public key SPKI hash must be extracted and bound to attestation quote
- Use ephemeral keys (regenerated on every container restart)

**Environment variables set**:
- Public: `STELLAR_PUBKEY`, `TLS_SPKI_HASH`, `TLS_CERT_PATH`, `DOMAIN_NAME`
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

## Phased Implementation (No Code)

Phase 1: Core attestation
- Add attestation service with quote generation, caching, and info endpoints.
- Bind Stellar public key to reportData.

Phase 2: TLS key binding
- Generate TLS keypair inside TEE.
- Issue certificate via ACME using the in-TEE TLS private key.
- Bind TLS public key SPKI hash into reportData and expose it in attestation responses.

Phase 3: Verification tooling
- Provide scripts and docs for attestation verification and TLS public key SPKI pinning.

Phase 4: Docs and ops
- Update architecture docs, deployment guides, and local dev guidance.

## Open Decisions

- ACME client choice (certbot, lego, acme.sh).
- Challenge type (http-01 vs tls-alpn-01) and port exposure strategy.
- Verification cadence for clients (per session vs periodic).
- Rotation policy for TLS keypair and Stellar keypair.
