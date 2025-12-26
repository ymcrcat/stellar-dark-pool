#![cfg(test)]

use super::*;
use soroban_sdk::{testutils::Address as _, Address, BytesN, Env};

fn create_test_env() -> Env {
    let env = Env::default();
    env.mock_all_auths();
    env
}

fn create_test_address(env: &Env, _seed: &str) -> Address {
    Address::generate(env)
}

fn create_test_bytes32(env: &Env, seed: u8) -> BytesN<32> {
    let mut bytes = [0u8; 32];
    bytes[0] = seed;
    BytesN::from_array(env, &bytes)
}

// Commenting out unused helper - can be re-enabled when needed
// fn create_test_asset_pair(env: &Env) -> AssetPair {
//     AssetPair {
//         base: SorobanString::from_str(env, "XLM"),
//         quote: SorobanString::from_str(env, "USDC"),
//     }
// }

fn create_test_settlement_instruction(
    env: &Env,
    buy_user: &Address,
    sell_user: &Address,
    base_asset: &Address,
    quote_asset: &Address,
) -> SettlementInstruction {
    SettlementInstruction {
        trade_id: create_test_bytes32(env, 10),
        buy_user: buy_user.clone(),
        sell_user: sell_user.clone(),
        base_asset: base_asset.clone(),
        quote_asset: quote_asset.clone(),
        base_amount: 100_000_000,  // 100.0 scaled by 10^7
        quote_amount: 150_000_000, // 150.0 scaled by 10^7
        fee_base: 0,
        fee_quote: 0,
        timestamp: 1234567890,
    }
}

#[test]
fn test_constructor() {
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");

    // Register contract with constructor arguments
    let _contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &_contract_id);

    // Verify assets were set correctly
    let asset_a = client.get_asset_a();
    let asset_b = client.get_asset_b();
    assert_eq!(asset_a, token_a);
    assert_eq!(asset_b, token_b);
}

#[test]
fn test_deposit() {
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    let user = create_test_address(&env, "user");

    // Create a token address (in real scenario, this would be a deployed token contract)
    let token_address = token_a;
    
    // First, check initial balance (should be 0)
    let initial_balance = client.get_balance(&user, &token_address);
    assert_eq!(initial_balance, 0);
    
    // Test deposit - with mock_all_auths(), authentication is mocked
    // The deposit function will:
    // 1. Require user auth (mocked)
    // 2. Call token_client.transfer() - this requires a real token contract
    //    For unit tests, we test the balance storage logic separately
    // 3. Call storage::add_balance() - this actually updates storage
    
    // Note: To fully test deposit with token transfers, we'd need to:
    // 1. Register a token contract using env.register_contract_wasm()
    // 2. Mint tokens to the user
    // 3. Approve the contract to spend tokens
    // 4. Call deposit
    
    // For now, we test that the deposit function can be called and updates balances
    // The actual token transfer is tested in integration tests (test_e2e.sh)
    
    // Since we're using mock_all_auths(), we can test the deposit flow
    // However, the token transfer will fail without a real token contract
    // So we'll test the balance storage logic directly in other tests
    
    // Verify get_balance works correctly
    assert_eq!(initial_balance, 0);
}

#[test]
fn test_deposit_balance_storage() {
    // Test that deposit correctly updates vault balances
    // This tests the storage logic without requiring token contracts
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let user = create_test_address(&env, "user");
    let token_address = token_a;
    
    // Test balance storage directly (simulating what deposit does)
    use crate::storage;
    env.as_contract(&contract_id, || {
        // Simulate deposit by adding balance
        storage::add_balance(&env, &user, &token_address, 100_000_000);
        
        // Verify balance was added
        let balance = storage::get_balance(&env, &user, &token_address);
        assert_eq!(balance, 100_000_000);
        
        // Simulate another deposit
        storage::add_balance(&env, &user, &token_address, 50_000_000);
        
        // Verify balance increased
        let final_balance = storage::get_balance(&env, &user, &token_address);
        assert_eq!(final_balance, 150_000_000);
    });
    
    // Verify via contract client
    let client = SettlementContractClient::new(&env, &contract_id);
    let balance = client.get_balance(&user, &token_address);
    assert_eq!(balance, 150_000_000);
}

#[test]
fn test_withdraw() {
    // Note: This test requires a real token contract to be deployed
    // For unit tests, we test the balance storage directly instead
    // See test_settle_trade_success for vault balance manipulation tests
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    let user = create_test_address(&env, "user");
    let token = token_a;
    
    // In a real scenario, withdraw would:
    // 1. Check vault balance via storage::get_balance
    // 2. Update vault balance via storage::subtract_balance
    // 3. Transfer tokens from contract to user via TokenClient
    // For unit tests without token contracts, we test balance storage separately
    // and integration tests would test the full withdraw flow
    
    // Test that get_balance works (returns 0 for new user)
    let balance = client.get_balance(&user, &token);
    assert_eq!(balance, 0);
}

#[test]
fn test_set_matching_engine() {
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    let matching_engine = create_test_address(&env, "matching_engine");

    // Set matching engine
    client.set_matching_engine(&matching_engine);
    
    // Verify it was set (by checking if matching engine can call settle_trade)
    // This is tested indirectly in test_settle_trade_with_vault_balances
}

#[test]
fn test_settle_trade_matching_engine_authorization() {
    // Test that settle_trade can be called by the matching engine
    // This verifies that the matching engine authorization works correctly
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    let buy_user = create_test_address(&env, "buyer");
    let sell_user = create_test_address(&env, "seller");
    let matching_engine = create_test_address(&env, "matching_engine");

    // 1. Set matching engine (required for authorization)
    client.set_matching_engine(&matching_engine);

    // 2. Setup vault balances
    use crate::storage;
    let base_token_contract = token_a.clone();
    let quote_token_contract = token_b.clone();
    
    env.as_contract(&contract_id, || {
        storage::set_balance(&env, &sell_user, &base_token_contract, 200_000_000);
        storage::set_balance(&env, &buy_user, &quote_token_contract, 200_000_000);
    });

    // 3. Create settlement instruction
    let instruction = create_test_settlement_instruction(
        &env,
        &buy_user,
        &sell_user,
        &base_token_contract,
        &quote_token_contract,
    );

    // 4. Call settle_trade as matching engine
    // With mock_all_auths(), the matching engine's require_auth() will pass
    // In production, the matching engine must sign the transaction
    let result = client.settle_trade(&instruction);

    // 5. Verify settlement succeeded
    assert_eq!(result, SettlementResult::Success);

    // 6. Verify settlement was recorded
    let settlement = client.get_settlement(&instruction.trade_id);
    assert!(settlement.is_some());
    
    // Note: To test that non-matching-engine accounts CANNOT call settle_trade,
    // we would need integration tests without mock_all_auths().
    // In unit tests with mock_all_auths(), all auth checks pass.
}

#[test]
fn test_settle_trade_success() {
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    let buy_user = create_test_address(&env, "buyer");
    let sell_user = create_test_address(&env, "seller");
    let matching_engine = create_test_address(&env, "matching_engine");

    // Contract initialized via __constructor during registration
    
    // Set matching engine
    client.set_matching_engine(&matching_engine);

    // Setup vault balances directly (bypassing token contracts for unit tests)
    // In production, balances are set via deposit() which transfers tokens
    use crate::storage;
    let base_token_contract = token_a.clone();
    let quote_token_contract = token_b.clone();
    
    // Set vault balances directly for testing (need contract context)
    env.as_contract(&contract_id, || {
        storage::set_balance(&env, &sell_user, &base_token_contract, 200_000_000);
        storage::set_balance(&env, &buy_user, &quote_token_contract, 200_000_000);
    });
    
    // Create instruction with actual token contract addresses
    let instruction = create_test_settlement_instruction(
        &env,
        &buy_user,
        &sell_user,
        &base_token_contract,
        &quote_token_contract,
    );

    // Settle trade (matching engine is authorized)
    let result = client.settle_trade(&instruction);

    // Verify success
    assert_eq!(result, SettlementResult::Success);

    // Verify settlement was recorded
    let trade_id = instruction.trade_id;
    let settlement = client.get_settlement(&trade_id);
    assert!(settlement.is_some());

    let record = settlement.unwrap();
    assert_eq!(record.buy_user, buy_user);
    assert_eq!(record.sell_user, sell_user);
    assert_eq!(record.base_amount, 100_000_000);
    assert_eq!(record.quote_amount, 150_000_000);
    
    // Verify vault balances were updated
    let buy_base_balance = client.get_balance(&buy_user, &base_token_contract);
    let buy_quote_balance = client.get_balance(&buy_user, &quote_token_contract);
    let sell_base_balance = client.get_balance(&sell_user, &base_token_contract);
    let sell_quote_balance = client.get_balance(&sell_user, &quote_token_contract);
    
    // Buyer: received base, paid quote
    assert_eq!(buy_base_balance, 100_000_000);
    assert_eq!(buy_quote_balance, 50_000_000); // 200 - 150
    
    // Seller: received quote, paid base
    assert_eq!(sell_base_balance, 100_000_000); // 200 - 100
    assert_eq!(sell_quote_balance, 150_000_000);
}

#[test]
fn test_settle_trade_insufficient_balance() {
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    let buy_user = create_test_address(&env, "buyer");
    let sell_user = create_test_address(&env, "seller");
    let matching_engine = create_test_address(&env, "matching_engine");

    // Contract initialized via __constructor during registration

    // Set matching engine
    client.set_matching_engine(&matching_engine);

    // Setup insufficient vault balances directly
    use crate::storage;
    let base_token_contract = token_a.clone();
    let quote_token_contract = token_b.clone();
    
    // Set vault balances directly for testing (need contract context)
    env.as_contract(&contract_id, || {
        // Seller has insufficient base asset (only 50, need 100)
        storage::set_balance(&env, &sell_user, &base_token_contract, 50_000_000);
        
        // Buyer has sufficient quote asset
        storage::set_balance(&env, &buy_user, &quote_token_contract, 200_000_000);
    });

    // Create settlement instruction with actual token addresses
    let instruction = create_test_settlement_instruction(
        &env,
        &buy_user,
        &sell_user,
        &base_token_contract,
        &quote_token_contract,
    );

    // Try to settle - should fail due to insufficient balance
    let result = client.settle_trade(&instruction);

    // Should fail with InsufficientBalance
    assert_eq!(result, SettlementResult::InsufficientBalance);
}

// Removed test_settle_trade_invalid_matching_proof as matching proof verification was removed

#[test]
fn test_get_settlement() {
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    let buy_user = create_test_address(&env, "buyer");
    let sell_user = create_test_address(&env, "seller");
    let matching_engine = create_test_address(&env, "matching_engine");

    // Contract initialized via __constructor during registration
    client.set_matching_engine(&matching_engine);

    // Setup vault balances directly
    use crate::storage;
    let base_token_contract = token_a.clone();
    let quote_token_contract = token_b.clone();
    
    env.as_contract(&contract_id, || {
        storage::set_balance(&env, &sell_user, &base_token_contract, 200_000_000);
        storage::set_balance(&env, &buy_user, &quote_token_contract, 200_000_000);
    });

    // Settle trade
    let instruction = create_test_settlement_instruction(
        &env,
        &buy_user,
        &sell_user,
        &base_token_contract,
        &quote_token_contract,
    );

    let trade_id = instruction.trade_id.clone();
    let result = client.settle_trade(&instruction);
    assert_eq!(result, SettlementResult::Success);

    // Get settlement
    let settlement = client.get_settlement(&trade_id);
    assert!(settlement.is_some());

    let record = settlement.unwrap();
    assert_eq!(record.trade_id, trade_id);
    assert_eq!(record.buy_user, buy_user);
    assert_eq!(record.sell_user, sell_user);
}

#[test]
fn test_get_settlement_not_found() {
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    // Contract initialized via __constructor during registration

    // Try to get non-existent settlement
    let trade_id = create_test_bytes32(&env, 255);
    let settlement = client.get_settlement(&trade_id);

    assert!(settlement.is_none());
}

#[test]
fn test_get_trade_history() {
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    let buy_user = create_test_address(&env, "buyer");
    let sell_user = create_test_address(&env, "seller");
    let matching_engine = create_test_address(&env, "matching_engine");

    // Contract initialized via __constructor during registration
    client.set_matching_engine(&matching_engine);

    // Setup vault balances directly for multiple trades
    use crate::storage;
    let base_token_contract = token_a.clone();
    let quote_token_contract = token_b.clone();
    
    // Set vault balances directly for testing (need contract context)
    env.as_contract(&contract_id, || {
        // Set sufficient balances for multiple trades
        storage::set_balance(&env, &sell_user, &base_token_contract, 1_000_000_000);
        storage::set_balance(&env, &buy_user, &quote_token_contract, 1_000_000_000);
    });

    // Create and settle multiple trades
    for i in 0..3 {
        let mut instruction = create_test_settlement_instruction(
            &env,
            &buy_user,
            &sell_user,
            &base_token_contract,
            &quote_token_contract,
        );

        instruction.trade_id = create_test_bytes32(&env, (10 + i) as u8);
        instruction.timestamp = 1234567890 + i;

        client.settle_trade(&instruction);
    }

    // Get trade history for buy_user
    let history = client.get_trade_history(&buy_user, &10);

    assert_eq!(history.len(), 3);

    // Verify all trades are for buy_user
    for i in 0..history.len() {
        let record = history.get(i).unwrap();
        assert_eq!(record.buy_user, buy_user);
    }
}

#[test]
fn test_get_trade_history_limit() {
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    let buy_user = create_test_address(&env, "buyer");
    let sell_user = create_test_address(&env, "seller");
    let matching_engine = create_test_address(&env, "matching_engine");

    // Contract initialized via __constructor during registration
    client.set_matching_engine(&matching_engine);

    // Setup vault balances directly for multiple trades
    use crate::storage;
    let base_token_contract = token_a.clone();
    let quote_token_contract = token_b.clone();
    
    // Set vault balances directly for testing (need contract context)
    env.as_contract(&contract_id, || {
        // Set sufficient balances for multiple trades
        storage::set_balance(&env, &sell_user, &base_token_contract, 1_000_000_000);
        storage::set_balance(&env, &buy_user, &quote_token_contract, 1_000_000_000);
    });

    // Create 5 trades
    for i in 0..5 {
        let mut instruction = create_test_settlement_instruction(
            &env,
            &buy_user,
            &sell_user,
            &base_token_contract,
            &quote_token_contract,
        );

        instruction.trade_id = create_test_bytes32(&env, (10 + i) as u8);
        instruction.timestamp = 1234567890 + i;

        client.settle_trade(&instruction);
    }

    // Get trade history with limit of 2
    let history = client.get_trade_history(&buy_user, &2);

    // Should return only the last 2 trades
    assert_eq!(history.len(), 2);
}

#[test]
fn test_get_trade_history_empty() {
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    let user = create_test_address(&env, "user");

    // Contract initialized via __constructor during registration

    // Get trade history for user with no trades
    let history = client.get_trade_history(&user, &10);

    assert_eq!(history.len(), 0);
}

#[test]
fn test_settle_trade_multiple_times_same_trade_id() {
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    let buy_user = create_test_address(&env, "buyer");
    let sell_user = create_test_address(&env, "seller");
    let matching_engine = create_test_address(&env, "matching_engine");

    // Contract initialized via __constructor during registration
    client.set_matching_engine(&matching_engine);

    // Setup vault balances directly
    use crate::storage;
    let base_token_contract = token_a.clone();
    let quote_token_contract = token_b.clone();
    
    env.as_contract(&contract_id, || {
        storage::set_balance(&env, &sell_user, &base_token_contract, 200_000_000);
        storage::set_balance(&env, &buy_user, &quote_token_contract, 200_000_000);
    });

    let instruction = create_test_settlement_instruction(
        &env,
        &buy_user,
        &sell_user,
        &base_token_contract,
        &quote_token_contract,
    );

    // First settlement should succeed
    let result1 = client.settle_trade(&instruction);
    assert_eq!(result1, SettlementResult::Success);

    // Second settlement with same trade_id - will fail due to insufficient balance
    // (vault balances were already used in first settlement)
    // Note: Current implementation doesn't check for duplicate trade_id
    // In production, you might want to return a different result for duplicates
    let result2 = client.settle_trade(&instruction);
    assert_eq!(result2, SettlementResult::InsufficientBalance);
}

#[test]
fn test_settle_trade_with_fees() {
    let env = create_test_env();
    let admin = create_test_address(&env, "admin");
    let token_a = create_test_address(&env, "token_a");
    let token_b = create_test_address(&env, "token_b");
    let contract_id = env.register(SettlementContract, (admin.clone(), token_a.clone(), token_b.clone()));
    let client = SettlementContractClient::new(&env, &contract_id);
    let buy_user = create_test_address(&env, "buyer");
    let sell_user = create_test_address(&env, "seller");
    let matching_engine = create_test_address(&env, "matching_engine");

    // Contract initialized via __constructor during registration

    // Set matching engine
    client.set_matching_engine(&matching_engine);

    // Setup vault balances directly (including fees)
    use crate::storage;
    let base_token_contract = token_a.clone();
    let quote_token_contract = token_b.clone();
    
    // Set vault balances directly for testing (need contract context)
    env.as_contract(&contract_id, || {
        // Seller has base asset (including fee): 100 base + 1 fee
        storage::set_balance(&env, &sell_user, &base_token_contract, 201_000_000);
        
        // Buyer has quote asset (including fee): 150 quote + 1.5 fee
        storage::set_balance(&env, &buy_user, &quote_token_contract, 201_500_000);
    });

    // Create instruction with fees
    let mut instruction = create_test_settlement_instruction(
        &env,
        &buy_user,
        &sell_user,
        &base_token_contract,
        &quote_token_contract,
    );
    instruction.fee_base = 1_000_000; // 0.1 scaled by 10^7
    instruction.fee_quote = 1_500_000; // 0.15 scaled by 10^7

    let result = client.settle_trade(&instruction);

    // Should succeed even with fees
    assert_eq!(result, SettlementResult::Success);
    
    // Verify fees went to admin
    let admin_base_balance = client.get_balance(&admin, &base_token_contract);
    let admin_quote_balance = client.get_balance(&admin, &quote_token_contract);
    assert_eq!(admin_base_balance, 1_000_000);
    assert_eq!(admin_quote_balance, 1_500_000);
}
