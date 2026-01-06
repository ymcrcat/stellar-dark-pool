#![no_std]
use soroban_sdk::{contract, contractimpl, log, Address, BytesN, Env, Vec};

mod events;
mod storage;
mod storage_types;
mod types;

#[cfg(test)]
mod test;

use types::*;

#[contract]
pub struct SettlementContract;

/// Helper function to validate that amount is positive
/// Following pattern from Soroban token example
fn check_positive_amount(amount: i128) {
    if amount <= 0 {
        panic!("Amount must be positive: {}", amount);
    }
}

#[contractimpl]
impl SettlementContract {
    /// Constructor function that runs automatically during deployment
    ///
    /// This is called automatically when constructor arguments are provided to
    /// `stellar contract deploy`. For example:
    /// `stellar contract deploy --wasm ... -- --admin <admin_address> --token_a <addr> --token_b <addr>`
    pub fn __constructor(env: Env, admin: Address, token_a: Address, token_b: Address) {
        storage::set_admin(&env, &admin);
        env.storage().instance().set(&storage_types::DataKey::AssetA, &token_a);
        env.storage().instance().set(&storage_types::DataKey::AssetB, &token_b);
    }

    /// Set the matching engine address (authorized to call settle_trade)
    /// Only admin can call this
    pub fn set_matching_engine(env: Env, matching_engine: Address) {
        let admin = storage::get_admin(&env);
        admin.require_auth();
        storage::set_matching_engine(&env, &matching_engine);
    }

    /// Deposit assets into the contract vault
    /// User must approve the contract to transfer tokens before calling this
    pub fn deposit(env: Env, user: Address, token: Address, amount: i128) {
        user.require_auth();
        check_positive_amount(amount);

        // Verify token is supported
        let asset_a = storage::get_asset_a(&env);
        let asset_b = storage::get_asset_b(&env);
        if token != asset_a && token != asset_b {
            panic!("Unsupported asset");
        }

        // Transfer tokens from user to contract
        use soroban_sdk::token::TokenClient;
        let token_client = TokenClient::new(&env, &token);
        token_client.transfer(&user, &env.current_contract_address(), &amount);

        // Update user balance in vault
        storage::add_balance(&env, &user, &token, amount);

        events::emit_deposit_event(&env, &user, &token, amount);
    }

    /// Withdraw assets from the contract vault
    pub fn withdraw(env: Env, user: Address, token: Address, amount: i128) {
        user.require_auth();
        check_positive_amount(amount);

        // Check user has sufficient balance
        let balance = storage::get_balance(&env, &user, &token);
        if balance < amount {
            panic!("Insufficient balance");
        }

        // Update user balance in vault
        storage::subtract_balance(&env, &user, &token, amount);

        // Transfer tokens from contract to user
        use soroban_sdk::token::TokenClient;
        let token_client = TokenClient::new(&env, &token);
        token_client.transfer(&env.current_contract_address(), &user, &amount);

        events::emit_withdraw_event(&env, &user, &token, amount);
    }

    /// Get user balance for a specific asset
    pub fn get_balance(env: Env, user: Address, token: Address) -> i128 {
        storage::get_balance(&env, &user, &token)
    }

    /// Get supported Asset A
    pub fn get_asset_a(env: Env) -> Address {
        storage::get_asset_a(&env)
    }

    /// Get supported Asset B
    pub fn get_asset_b(env: Env) -> Address {
        storage::get_asset_b(&env)
    }

    /// Settle a trade
    /// Can be called by matching engine (authorized) or users
    pub fn settle_trade(env: Env, instruction: SettlementInstruction) -> SettlementResult {
        log!(&env, "settle_trade: Starting settlement");

        // Verify assets match supported assets
        let asset_a = storage::get_asset_a(&env);
        let asset_b = storage::get_asset_b(&env);
        let base = &instruction.base_asset;
        let quote = &instruction.quote_asset;

        log!(&env, "settle_trade: Checking asset support");
        if (base != &asset_a && base != &asset_b) || (quote != &asset_a && quote != &asset_b) {
             log!(&env, "settle_trade: ERROR - Unsupported asset in trade");
             return SettlementResult::InvalidMatchingProof;
        }

        log!(&env, "settle_trade: Verifying matching engine authorization");
        match storage::get_matching_engine(&env) {
            Some(matching_engine) => matching_engine.require_auth(),
            None => panic!("Matching engine not set"),
        }

        // Skip signature and proof verification for now
        log!(&env, "settle_trade: Skipping verification (simplified flow)");
        // 4. Check vault balances
        log!(&env, "settle_trade: Step 5 - Checking vault balances");
        let buy_balance = storage::get_balance(&env, &instruction.buy_user, &instruction.quote_asset);
        let sell_balance = storage::get_balance(&env, &instruction.sell_user, &instruction.base_asset);
        
        let required_quote = instruction.quote_amount + instruction.fee_quote;
        let required_base = instruction.base_amount + instruction.fee_base;

        log!(&env, "settle_trade: Checking buyer quote balance and seller base balance");

        if buy_balance < required_quote {
            log!(&env, "settle_trade: ERROR - Buyer has insufficient quote balance");
            log!(&env, "settle_trade: Buyer balance less than required quote amount, returning InsufficientBalance");
            return SettlementResult::InsufficientBalance;
        }

        if sell_balance < required_base {
            log!(&env, "settle_trade: ERROR - Seller has insufficient base balance");
            log!(&env, "settle_trade: Seller balance less than required base amount, returning InsufficientBalance");
            return SettlementResult::InsufficientBalance;
        }

        log!(&env, "settle_trade: All balance checks passed");

        // 5. Execute asset transfers from vault
        log!(&env, "settle_trade: Step 5 - Executing asset transfers");
        // Buyer pays quote asset, receives base asset
        log!(&env, "settle_trade: Transferring quote from buyer");
        storage::subtract_balance(&env, &instruction.buy_user, &instruction.quote_asset, required_quote);
        log!(&env, "settle_trade: Transferring base to buyer");
        storage::add_balance(&env, &instruction.buy_user, &instruction.base_asset, instruction.base_amount);

        // Seller pays base asset, receives quote asset
        log!(&env, "settle_trade: Transferring base from seller");
        storage::subtract_balance(&env, &instruction.sell_user, &instruction.base_asset, required_base);
        log!(&env, "settle_trade: Transferring quote to seller");
        storage::add_balance(&env, &instruction.sell_user, &instruction.quote_asset, instruction.quote_amount);
        log!(&env, "settle_trade: Asset transfers completed");

        // 6. Collect fees (transfer to admin or fee recipient)
        log!(&env, "settle_trade: Step 6 - Collecting fees");
        if instruction.fee_base > 0 || instruction.fee_quote > 0 {
            let admin = storage::get_admin(&env);
            if instruction.fee_base > 0 {
                log!(&env, "settle_trade: Collecting base fee");
                storage::add_balance(&env, &admin, &instruction.base_asset, instruction.fee_base);
            }
            if instruction.fee_quote > 0 {
                log!(&env, "settle_trade: Collecting quote fee");
                storage::add_balance(&env, &admin, &instruction.quote_asset, instruction.fee_quote);
            }
            log!(&env, "settle_trade: Fees collected");
        } else {
            log!(&env, "settle_trade: No fees to collect");
        }

        // 7. Record settlement
        log!(&env, "settle_trade: Step 7 - Recording settlement");
        storage::record_settlement(&env, &instruction);
        log!(&env, "settle_trade: Settlement recorded");

        // 8. Emit events
        log!(&env, "settle_trade: Step 8 - Emitting events");
        events::emit_settlement_event(&env, &instruction);
        log!(&env, "settle_trade: Events emitted");

        log!(&env, "settle_trade: Settlement completed successfully");
        SettlementResult::Success
    }

    /// Query trade history for a user
    pub fn get_trade_history(env: Env, user: Address, limit: u32) -> Vec<SettlementRecord> {
        storage::get_trade_history(&env, &user, limit)
    }

    /// Get a settlement record by trade ID
    pub fn get_settlement(env: Env, trade_id: BytesN<32>) -> Option<SettlementRecord> {
        storage::get_settlement(&env, &trade_id)
    }
}
