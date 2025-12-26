use crate::types::*;
use soroban_sdk::{contractevent, Address, BytesN, Env};

// Event topics for better filtering and indexing
// Topics are defined as string literals in the macro
#[contractevent(topics = ["SETTLEMENT", "trade"])]
#[derive(Clone, Debug)]
pub struct SettlementEvent {
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

#[contractevent(topics = ["DEPOSIT"])]
#[derive(Clone, Debug)]
pub struct DepositEvent {
    pub user: Address,
    pub token: Address,
    pub amount: i128,
}

#[contractevent(topics = ["WITHDRAW"])]
#[derive(Clone, Debug)]
pub struct WithdrawEvent {
    pub user: Address,
    pub token: Address,
    pub amount: i128,
}

pub fn emit_settlement_event(env: &Env, instruction: &SettlementInstruction) {
    // Emit comprehensive settlement event
    SettlementEvent {
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
    }
    .publish(env);
}

pub fn emit_deposit_event(env: &Env, user: &Address, token: &Address, amount: i128) {
    DepositEvent {
        user: user.clone(),
        token: token.clone(),
        amount,
    }
    .publish(env);
}

pub fn emit_withdraw_event(env: &Env, user: &Address, token: &Address, amount: i128) {
    WithdrawEvent {
        user: user.clone(),
        token: token.clone(),
        amount,
    }
    .publish(env);
}
