use soroban_sdk::{contracttype, Address, BytesN};

// Storage key for user balances (needs struct since it has two fields)
#[derive(Clone)]
#[contracttype]
pub struct BalanceDataKey {
    pub user: Address,
    pub asset: Address,
}

// Main storage key enum
#[derive(Clone)]
#[contracttype]
pub enum DataKey {
    Admin,
    MatchingEngine,
    AssetA,
    AssetB,
    Balance(BalanceDataKey),
    Settlement(BytesN<32>),            // trade_id
    UserTradeHistory(Address),         // user
}
