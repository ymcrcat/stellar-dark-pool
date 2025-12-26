use soroban_sdk::{contracttype, Address, BytesN, String as SorobanString};

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AssetPair {
    pub base: SorobanString,
    pub quote: SorobanString,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SettlementInstruction {
    pub trade_id: BytesN<32>,
    pub buy_user: Address,
    pub sell_user: Address,
    pub base_asset: Address,  // Stellar asset contract address
    pub quote_asset: Address, // Stellar asset contract address
    pub base_amount: i128,
    pub quote_amount: i128,
    pub fee_base: i128,
    pub fee_quote: i128,
    pub timestamp: u64,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SettlementResult {
    Success,
    InvalidSignature,
    InvalidMatchingProof,
    InsufficientBalance,
    TransferFailed,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SettlementRecord {
    pub trade_id: BytesN<32>,
    pub buy_user: Address,
    pub sell_user: Address,
    pub base_asset: Address,
    pub quote_asset: Address,
    pub base_amount: i128,
    pub quote_amount: i128,
    pub execution_price: i128,
    pub execution_quantity: i128,
    pub timestamp: u64,
}
