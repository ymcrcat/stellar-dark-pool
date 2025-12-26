import hashlib
import base64
import time
import asyncio
import logging
from decimal import Decimal
from typing import Optional, Tuple, Any, Dict, List

from stellar_sdk import (
    Asset,
    Keypair,
    Network,
    SorobanServer,
    TransactionBuilder,
    strkey,
    xdr,
    Account
)
from stellar_sdk import scval
from stellar_sdk.xdr import (
    LedgerKey,
    LedgerKeyAccount,
    LedgerEntryType,
    LedgerEntryData,
)

from .types import Order, OrderSide, OrderType, TimeInForce, SettlementInstruction
from .config import settings

logger = logging.getLogger(__name__)

class StellarService:
    def __init__(self):
        self.soroban_server = SorobanServer(settings.soroban_rpc_url)
        self.network_passphrase = settings.stellar_network_passphrase
        
        # Configure Network - Logging only as SDK v9+ uses passphrase in builders
        if "TESTNET" in self.network_passphrase:
            logger.info(f"Using Testnet with passphrase: {self.network_passphrase}")
        elif "PUBLIC" in self.network_passphrase:
            logger.info(f"Using Public Network with passphrase: {self.network_passphrase}")
        else:
            logger.info(f"Using Custom Network with passphrase: {self.network_passphrase}")

    async def get_account_sequence(self, address: str) -> int:
        """
        Fetches the current sequence number for an account using Soroban RPC.
        """
        try:
            # Newer stellar-sdk versions have get_account helper
            if hasattr(self.soroban_server, "get_account"):
                 account = self.soroban_server.get_account(address)
                 return account.sequence
            
            # Fallback to getLedgerEntries
            kp = Keypair.from_public_key(address)
            account_id = kp.xdr_account_id()
            
            ledger_key = LedgerKey(
                type=LedgerEntryType.ACCOUNT,
                account=LedgerKeyAccount(account_id=account_id)
            )
            key_b64 = base64.b64encode(ledger_key.to_xdr_bytes()).decode("utf-8")
            response = self.soroban_server.get_ledger_entries([key_b64])
            
            if not response.entries:
                return 0

            # response.entries[0].xdr is already a base64 string
            entry_xdr = response.entries[0].xdr
            if isinstance(entry_xdr, str):
                entry_bytes = base64.b64decode(entry_xdr)
            else:
                entry_bytes = entry_xdr
            entry_data = LedgerEntryData.from_xdr(entry_bytes)
            if entry_data.type == LedgerEntryType.ACCOUNT:
                return entry_data.account.seq_num.sequence_number.int64
            return 0
        except Exception as e:
            logger.error(f"Failed to get account sequence for {address}: {e}")
            raise e

    async def get_asset_a(self) -> str:
        return await self._call_contract_read("get_asset_a")

    async def get_asset_b(self) -> str:
        return await self._call_contract_read("get_asset_b")

    async def _call_contract_read(self, method: str) -> str:
        try:
            source_kp = Keypair.random()
            source_account = Account(source_kp.public_key, 0)
            
            tx_builder = TransactionBuilder(
                source_account=source_account,
                network_passphrase=self.network_passphrase,
                base_fee=100
            )
            tx_builder.append_invoke_contract_function_op(
                contract_id=settings.settlement_contract_id,
                function_name=method,
                parameters=[]
            )
            tx = tx_builder.build()
            response = self.soroban_server.simulate_transaction(tx)
            
            if response.results and len(response.results) > 0:
                sc_val = xdr.SCVal.from_xdr(response.results[0].xdr)

                # Extract Address manually
                if sc_val.type == xdr.SCValType.SCV_ADDRESS:
                    addr = sc_val.address
                    if addr.type == xdr.SCAddressType.SC_ADDRESS_TYPE_ACCOUNT:
                        return strkey.StrKey.encode_ed25519_public_key(addr.account_id.ed25519.to_xdr_bytes())
                    elif addr.type == xdr.SCAddressType.SC_ADDRESS_TYPE_CONTRACT:
                        # contract_id is already a Hash object with the raw bytes
                        return strkey.StrKey.encode_contract(addr.contract_id.to_xdr_bytes())

                # Try to_native for other types
                if hasattr(scval, "to_native"):
                    result = scval.to_native(sc_val)
                    # If it's an Address object, convert to string
                    if hasattr(result, "account_id"):
                        return str(result)
                    return result

            raise ValueError(f"Failed to call {method}")
        except Exception as e:
            logger.error(f"Contract call {method} failed: {e}")
            raise e

    def asset_from_string(self, asset_str: str) -> Asset:
        if asset_str == "XLM" or asset_str == "native":
            return Asset.native()
        
        parts = asset_str.split(":")
        if len(parts) == 2:
            return Asset(parts[0], parts[1])
        
        raise ValueError(f"Invalid asset format: {asset_str}. Use 'XLM' or 'CODE:ISSUER'")

    def get_contract_address(self, asset_str: str) -> str:
        if asset_str.startswith("C") and len(asset_str) == 56:
            return asset_str
        
        if len(asset_str) == 64:
            try:
                raw_bytes = bytes.fromhex(asset_str)
                return strkey.StrKey.encode_contract(raw_bytes)
            except ValueError:
                pass 

        try:
            asset = self.asset_from_string(asset_str)
            return asset.contract_id(self.network_passphrase)
        except Exception as e:
            raise ValueError(f"Could not derive contract ID for {asset_str}: {e}")

    # =========================================================================
    # SEP-0053 Signing & Verification
    # =========================================================================

    def create_order_message(self, order: Order) -> str:
        parts = []
        parts.append(f"order_id:{order.order_id}")
        parts.append(f"user:{order.user_address}")
        parts.append(f"pair:{order.asset_pair.base}/{order.asset_pair.quote}")
        parts.append(f"side:{order.side.value}")
        parts.append(f"type:{order.order_type.value}")
        
        if order.price is not None:
            parts.append(f"price:{order.price}")
            
        parts.append(f"quantity:{order.quantity}")
        parts.append(f"tif:{order.time_in_force.value}")
        parts.append(f"timestamp:{order.timestamp}")
        
        if order.expiration is not None:
            parts.append(f"expiration:{order.expiration}")
            
        return "|".join(parts)

    def verify_order_signature(self, order: Order, signature: str, public_key: str) -> bool:
        try:
            message = self.create_order_message(order)
            prefix = "Stellar Signed Message:\n"
            full_message = (prefix + message).encode("utf-8")
            message_hash = hashlib.sha256(full_message).digest()
            
            sig_bytes = base64.b64decode(signature)
            
            kp = Keypair.from_public_key(public_key)
            kp.verify(message_hash, sig_bytes)
            return True
        except Exception as e:
            logger.warning(f"Signature verification failed: {e}")
            return False

    # =========================================================================
    # Soroban Interactions (Vault Balance)
    # =========================================================================

    async def get_vault_balance(self, user_address: str, token_address: str) -> int:
        contract_id = settings.settlement_contract_id
        if not contract_id:
            logger.error("Settlement contract ID not configured")
            return 0

        user_scval = scval.to_address(user_address)
        token_scval = scval.to_address(token_address)
        
        source_kp = Keypair.random()
        
        try:
            # Create a dummy account object for simulation
            # We don't need real sequence for simulation usually, but SDK needs an Account object
            source_account = Account(source_kp.public_key, 0)
            
            tx_builder = TransactionBuilder(
                source_account=source_account,
                network_passphrase=self.network_passphrase,
                base_fee=100
            )
            
            tx_builder.append_invoke_contract_function_op(
                contract_id=contract_id,
                function_name="get_balance",
                parameters=[user_scval, token_scval]
            )
            
            tx_builder.set_timeout(30)
            tx = tx_builder.build()
            tx.sign(source_kp)
            
            response = self.soroban_server.simulate_transaction(tx)

            if hasattr(response, 'error') and response.error:
                logger.error(f"Simulate transaction error: {response.error}")
                return 0

            if not response.results or len(response.results) == 0:
                return 0

            result = response.results[0]
            if hasattr(result, 'error') and result.error:
                 return 0
            
            # The result.xdr is the ScVal encoded in base64
            # We can use xdr.SCVal.from_xdr to parse it
            balance_scval = xdr.SCVal.from_xdr(result.xdr)
            
            # Attempt to convert to python int
            if hasattr(scval, 'to_native'):
                 return scval.to_native(balance_scval)
            else:
                # Fallback manual extraction
                if balance_scval.type == xdr.SCValType.SCV_I128:
                    parts = balance_scval.i128
                    hi = parts.hi.int64
                    lo = parts.lo.uint64
                    return (hi << 64) | lo
                elif balance_scval.type == xdr.SCValType.SCV_I64:
                    return balance_scval.i64.int64
                elif balance_scval.type == xdr.SCValType.SCV_U64:
                    return balance_scval.u64.uint64
                elif balance_scval.type == xdr.SCValType.SCV_U32:
                    return balance_scval.u32.uint32
                elif balance_scval.type == xdr.SCValType.SCV_I32:
                    return balance_scval.i32.int32
                else:
                    return 0

        except Exception as e:
            logger.error(f"Failed to get vault balance: {e}")
            return 0

    # =========================================================================
    # Settlement Submission
    # =========================================================================

    def _get_signing_key(self) -> str:
        if settings.matching_engine_signing_key:
            return settings.matching_engine_signing_key
        
        if settings.matching_engine_key_alias:
            import subprocess
            try:
                result = subprocess.run(
                    ["stellar", "keys", "show", settings.matching_engine_key_alias],
                    capture_output=True,
                    text=True,
                    check=True
                )
                secret = result.stdout.strip()
                if secret.startswith("S") and len(secret) == 56:
                    return secret
                # Try parsing if output contains extra text
                import re
                match = re.search(r"S[A-Z0-9]{55}", result.stdout)
                if match:
                    return match.group(0)
                raise ValueError(f"Could not parse secret key from stellar CLI output: {result.stdout}")
            except subprocess.CalledProcessError as e:
                raise ValueError(f"Failed to fetch key alias '{settings.matching_engine_key_alias}' from Stellar CLI: {e.stderr}")
            except FileNotFoundError:
                raise ValueError("Stellar CLI not found in PATH. Cannot resolve key alias.")
        
        raise ValueError("Neither MATCHING_ENGINE_SIGNING_KEY nor MATCHING_ENGINE_KEY_ALIAS is configured.")

    async def sign_and_submit_settlement(self, instruction: SettlementInstruction) -> str:
        secret_key = self._get_signing_key()
        me_kp = Keypair.from_secret(secret_key)

        # 1. Load account from Soroban RPC (includes sequence number)
        try:
            source_account = self.soroban_server.load_account(me_kp.public_key)
        except Exception as e:
             raise ValueError(f"Failed to load matching engine account {me_kp.public_key}: {str(e)}")
        
        args = self._build_settlement_args(instruction)
        
        # 2. Build initial Tx
        tx_builder = TransactionBuilder(
            source_account=source_account,
            network_passphrase=self.network_passphrase,
            base_fee=100
        )
        
        tx_builder.append_invoke_contract_function_op(
            contract_id=settings.settlement_contract_id,
            function_name="settle_trade",
            parameters=[args]
        )
        
        tx = tx_builder.build()
        tx.sign(me_kp)
        
        # 3. Simulate
        sim_response = self.soroban_server.simulate_transaction(tx)
        
        if sim_response.error:
             raise ValueError(f"Simulation failed: {sim_response.error}")
        
        # 4. Prepare transaction (add Soroban data)
        # Using the server's prepare_transaction if available, or manually assembling
        try:
            # We need to re-build or update the transaction with the simulation data.
            # Stellar SDK's SorobanServer usually has `prepare_transaction` helper
            tx = self.soroban_server.prepare_transaction(tx, sim_response)
        except AttributeError:
             # Fallback if specific method name differs in installed version
             # Assuming standard SDK v9 behavior where simulate returns data needed
             # but manual assembly is complex. 
             # For now, let's assume `prepare_transaction` exists as per docs.
             pass
             
        tx.sign(me_kp)
        
        # 5. Submit
        send_response = self.soroban_server.send_transaction(tx)
        if send_response.status == "ERROR":
            raise ValueError(f"Submission failed: {send_response.error_result_xdr}")
            
        return await self._poll_transaction(send_response.hash)

    async def _poll_transaction(self, tx_hash: str) -> str:
        from stellar_sdk.soroban_rpc import GetTransactionStatus

        logger.info(f"Polling transaction {tx_hash}")
        # Testnet can be slow, so we increase the timeout to 120 seconds (60 attempts × 2 seconds)
        for i in range(60):
            res = self.soroban_server.get_transaction(tx_hash)

            # Check against enum values, not string comparison
            if res.status == GetTransactionStatus.SUCCESS:
                logger.info(f"Transaction {tx_hash} confirmed successfully after {i*2} seconds")
                return tx_hash
            if res.status == GetTransactionStatus.FAILED:
                raise ValueError(f"Transaction failed on-chain: {res.result_xdr}")

            if i % 10 == 0:  # Log every 20 seconds
                logger.info(f"Still waiting for transaction {tx_hash}... (status: {res.status})")

            await asyncio.sleep(2)

        raise TimeoutError(f"Transaction polling timed out after 120 seconds. Last status: {res.status}. TX hash: {tx_hash}")

    def _build_settlement_args(self, instruction: SettlementInstruction) -> Any:
        # Convert asset strings to contract addresses if needed
        base_asset_addr = self.get_contract_address(instruction.base_asset)
        quote_asset_addr = self.get_contract_address(instruction.quote_asset)

        # Convert trade_id (UUID string) to bytes32
        # Remove hyphens and convert to bytes
        trade_id_clean = instruction.trade_id.replace('-', '')
        trade_id_bytes = bytes.fromhex(trade_id_clean)

        # Ensure it's exactly 32 bytes
        if len(trade_id_bytes) != 32:
            # UUID is 16 bytes, pad to 32 bytes
            trade_id_bytes = trade_id_bytes + b'\x00' * (32 - len(trade_id_bytes))

        data = {
            scval.to_symbol("base_amount"): self._to_i128(instruction.base_amount),
            scval.to_symbol("base_asset"): scval.to_address(base_asset_addr),
            scval.to_symbol("buy_user"): scval.to_address(instruction.buy_user),
            scval.to_symbol("fee_base"): self._to_i128(instruction.fee_base),
            scval.to_symbol("fee_quote"): self._to_i128(instruction.fee_quote),
            scval.to_symbol("quote_amount"): self._to_i128(instruction.quote_amount),
            scval.to_symbol("quote_asset"): scval.to_address(quote_asset_addr),
            scval.to_symbol("sell_user"): scval.to_address(instruction.sell_user),
            scval.to_symbol("timestamp"): scval.to_uint64(instruction.timestamp),
            scval.to_symbol("trade_id"): scval.to_bytes(trade_id_bytes),
        }

        return scval.to_map(data)

    def _to_i128(self, val: Any) -> Any:
        v = int(val)
        return scval.to_int128(v)

stellar_service = StellarService()
