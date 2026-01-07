from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field

class Settings(BaseSettings):
    # Stellar Configuration
    stellar_network_passphrase: str = Field(
        default="Test SDF Network ; September 2015",
        validation_alias="STELLAR_NETWORK_PASSPHRASE"
    )
    soroban_rpc_url: str = Field(
        default="https://soroban-testnet.stellar.org",
        validation_alias="SOROBAN_RPC_URL"
    )
    settlement_contract_id: str = Field(
        default="",
        validation_alias="SETTLEMENT_CONTRACT_ID"
    )
    matching_engine_signing_key: Optional[str] = Field(
        default=None,
        validation_alias="MATCHING_ENGINE_SIGNING_KEY"
    )
    matching_engine_key_alias: Optional[str] = Field(
        default=None,
        validation_alias="MATCHING_ENGINE_KEY_ALIAS"
    )

    # Server Configuration
    rest_port: int = Field(
        default=8080,
        validation_alias="REST_PORT"
    )

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

settings = Settings()
