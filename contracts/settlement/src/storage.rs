use crate::storage_types::*;
use crate::types::*;
use soroban_sdk::{Address, BytesN, Env, Vec};

pub fn set_admin(env: &Env, admin: &Address) {
    let key = DataKey::Admin;
    env.storage().instance().set(&key, admin);
}

pub fn get_admin(env: &Env) -> Address {
    let key = DataKey::Admin;
    env.storage().instance().get(&key).unwrap()
}

pub fn get_asset_a(env: &Env) -> Address {
    let key = DataKey::AssetA;
    env.storage().instance().get(&key).unwrap()
}

pub fn get_asset_b(env: &Env) -> Address {
    let key = DataKey::AssetB;
    env.storage().instance().get(&key).unwrap()
}

/// Set the matching engine address (authorized to call settle_trade)
pub fn set_matching_engine(env: &Env, matching_engine: &Address) {
    let key = DataKey::MatchingEngine;
    env.storage().instance().set(&key, matching_engine);
}

/// Get the matching engine address (authorized to call settle_trade)
/// Currently unused but kept for future authorization re-enablement
#[allow(dead_code)]
pub fn get_matching_engine(env: &Env) -> Option<Address> {
    let key = DataKey::MatchingEngine;
    env.storage().instance().get(&key)
}

/// Get user balance for a specific asset
pub fn get_balance(env: &Env, user: &Address, asset: &Address) -> i128 {
    let key = DataKey::Balance(BalanceDataKey {
        user: user.clone(),
        asset: asset.clone(),
    });
    env.storage().instance().get(&key).unwrap_or(0)
}

/// Set user balance for a specific asset
pub fn set_balance(env: &Env, user: &Address, asset: &Address, amount: i128) {
    let key = DataKey::Balance(BalanceDataKey {
        user: user.clone(),
        asset: asset.clone(),
    });
    env.storage().instance().set(&key, &amount);
}

/// Add to user balance (deposit)
pub fn add_balance(env: &Env, user: &Address, asset: &Address, amount: i128) {
    let current = get_balance(env, user, asset);
    set_balance(env, user, asset, current + amount);
}

/// Subtract from user balance (withdraw/settlement)
pub fn subtract_balance(env: &Env, user: &Address, asset: &Address, amount: i128) {
    let current = get_balance(env, user, asset);
    if current < amount {
        panic!("Insufficient balance");
    }
    set_balance(env, user, asset, current - amount);
}

pub fn record_settlement(env: &Env, instruction: &SettlementInstruction) {
    let record = SettlementRecord {
        trade_id: instruction.trade_id.clone(),
        buy_user: instruction.buy_user.clone(),
        sell_user: instruction.sell_user.clone(),
        base_asset: instruction.base_asset.clone(),
        quote_asset: instruction.quote_asset.clone(),
        base_amount: instruction.base_amount,
        quote_amount: instruction.quote_amount,
        execution_price: 0, // Placeholder - no matching proof
        execution_quantity: 0, // Placeholder - no matching proof
        timestamp: instruction.timestamp,
    };

    // Store by trade ID
    let trade_key = DataKey::Settlement(instruction.trade_id.clone());
    env.storage().instance().set(&trade_key, &record);

    // Store in user trade history
    let buy_trades_key = DataKey::UserTradeHistory(instruction.buy_user.clone());
    let sell_trades_key = DataKey::UserTradeHistory(instruction.sell_user.clone());

    let mut buy_trades: Vec<BytesN<32>> = env
        .storage()
        .instance()
        .get(&buy_trades_key)
        .unwrap_or_else(|| Vec::new(env));
    let mut sell_trades: Vec<BytesN<32>> = env
        .storage()
        .instance()
        .get(&sell_trades_key)
        .unwrap_or_else(|| Vec::new(env));

    buy_trades.push_back(instruction.trade_id.clone());
    sell_trades.push_back(instruction.trade_id.clone());

    env.storage().instance().set(&buy_trades_key, &buy_trades);
    env.storage()
        .instance()
        .set(&sell_trades_key, &sell_trades);
}

pub fn get_settlement(env: &Env, trade_id: &BytesN<32>) -> Option<SettlementRecord> {
    let key = DataKey::Settlement(trade_id.clone());
    env.storage().instance().get(&key)
}

pub fn get_trade_history(env: &Env, user: &Address, limit: u32) -> Vec<SettlementRecord> {
    let trades_key = DataKey::UserTradeHistory(user.clone());
    let trade_ids: Vec<BytesN<32>> = env
        .storage()
        .instance()
        .get(&trades_key)
        .unwrap_or_else(|| Vec::new(env));

    let mut records = Vec::new(env);
    let trade_ids_len_u32 = trade_ids.len();
    let limit_u32 = limit;
    let start_u32 = trade_ids_len_u32.saturating_sub(limit_u32);

    let start = start_u32;
    let len = trade_ids_len_u32;

    for i in start..len {
        if let Some(trade_id) = trade_ids.get(i) {
            if let Some(record) = get_settlement(env, &trade_id) {
                records.push_back(record);
            }
        }
    }

    records
}
