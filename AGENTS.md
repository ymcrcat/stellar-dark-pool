# Repository Guidelines

## Project Structure & Module Organization
- `contracts/settlement/`: Soroban smart contract (Rust) for vaults and settlement. Key entry points in `contracts/settlement/src/`.
- `matching-engine/`: Python matching engine with REST API. Source in `matching-engine/src/`, tests in `matching-engine/tests/`.
- `scripts/`: Utilities including `sign_order.py` (SEP-0053 signing), `demo_remote_tee.sh`, `verify_remote_attestation.py`, `compute_compose_hash.py`.
- Top-level docs: `docs/ARCHITECTURE.md`, `TUTORIAL.md`, `docs/RESEARCH.md`, `docs/TODO.md`, `docs/TEE.md`, `docs/PHALA.md`, `WARP.md`, `TEE_SPEC.md`.

## Build, Test, and Development Commands
- Contract build: `cd contracts/settlement && stellar contract build --profile release-with-logs --optimize` (produces optimized WASM in `target/wasm32v1-none/release-with-logs/settlement.wasm`).
- Contract tests: `cd contracts/settlement && cargo test`.
- Contract E2E test: `cd contracts/settlement && bash test_contract.sh` (deploys to testnet and runs full integration test).
- Matching engine (local): `cd matching-engine && python -m venv venv && source venv/bin/activate && pip install -r requirements.txt && python -m src.main`.
- Matching engine (Docker): `docker-compose up -d` from repo root (auto-generates ephemeral keypair on startup).
- E2E tests: `./test_e2e_docker.sh` (recommended) or `./test_e2e_full.sh`.
- Makefile targets: `make contract` (build), `make contract-deploy` (build and deploy), `make docker-deploy` (build and push Docker image).

## Architecture Overview
- Off-chain matching happens in `matching-engine/` to keep orders private; it submits settlements to the Soroban contract in `contracts/settlement/`.
- Users pre-deposit funds into the contract vault, enabling atomic on-chain settlement without per-order signatures.
- Soroban RPC is used directly; no Horizon dependency for blockchain interactions.

## Coding Style & Naming Conventions
- Follow existing file patterns in each module (Rust in `contracts/settlement/`, Python in `matching-engine/src/`).
- Tests follow pytest defaults: files `test_*.py`, functions `test_*` (see `matching-engine/pytest.ini`).
- New scripts should live in `scripts/` and be named descriptively (e.g., `sign_order.py`).

## Testing Guidelines
- Python tests use pytest; run `pytest tests/` from `matching-engine/` (or `pytest` from `matching-engine/` since `pytest.ini` sets `testpaths = tests`).
- Use targeted tests when iterating: `pytest tests/test_orderbook.py::test_full_match_buy_sell -v`.
- Test markers available: `@pytest.mark.asyncio`, `@pytest.mark.unit`, `@pytest.mark.integration` (see `matching-engine/pytest.ini`).
- Contract tests live in `contracts/settlement/src/test.rs` (unit tests) and `contracts/settlement/src/lib.rs` (inline tests).
- Contract E2E: `contracts/settlement/test_contract.sh` provides full deployment and integration testing on testnet.

## Commit & Pull Request Guidelines
- Commit messages in history are short, imperative summaries (e.g., “E2E test with dockerized matching engine”). Keep subjects concise and scoped.
- PRs should include: purpose, affected components (contract vs. engine), and how to test (commands + expected outcome). Link related issues when applicable.

## Security & Configuration Tips
- Matching engine requires `.env` (see `matching-engine/README.md`); never commit secrets.
- Docker runs with ephemeral keypairs; ensure you fund and authorize the displayed public key before testing settlement.
- Docker can auto-deploy contracts when `AUTO_DEPLOY_CONTRACT=true` is set (requires prebuilt WASM in `matching-engine/artifacts/`).
- For on-chain actions, use testnet and fund accounts via Friendbot as documented in `README.md`.
- TEE deployment options: see `docs/TEE.md` for Trusted Execution Environment setup and `docs/PHALA.md` for Phala Network integration.