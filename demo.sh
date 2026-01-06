#!/usr/bin/env bash
set -euo pipefail

BASE_URL=${BASE_URL:-}
NETWORK=${NETWORK:-testnet}
SETTLEMENT_CONTRACT_ID=${SETTLEMENT_CONTRACT_ID:-}
MATCHING_ENGINE_PUBLIC=${MATCHING_ENGINE_PUBLIC:-}

USER1_KEY_ALIAS=${USER1_KEY_ALIAS:-demo_user1}
USER2_KEY_ALIAS=${USER2_KEY_ALIAS:-demo_user2}

if [ -z "$BASE_URL" ]; then
  echo "BASE_URL is required. Example:" >&2
  echo "  BASE_URL=https://<app-id>-443.dstack-pha-prod9.phala.network" >&2
  exit 1
fi

for tool in python3 curl stellar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

if [ -z "$SETTLEMENT_CONTRACT_ID" ]; then
  echo "SETTLEMENT_CONTRACT_ID is required." >&2
  exit 1
fi

if [ -z "$MATCHING_ENGINE_PUBLIC" ]; then
  echo "MATCHING_ENGINE_PUBLIC is required (Stellar public key of the matching engine)." >&2
  exit 1
fi

create_user_if_needed() {
  local alias=$1
  if stellar keys ls 2>/dev/null | grep -q "^${alias}$"; then
    return 0
  fi
  if [ "$NETWORK" = "testnet" ]; then
    stellar keys generate "$alias" --fund
  else
    stellar keys generate "$alias"
  fi
}

create_user_if_needed "$USER1_KEY_ALIAS"
create_user_if_needed "$USER2_KEY_ALIAS"

USER1_PUBLIC=$(stellar keys address "$USER1_KEY_ALIAS")
USER2_PUBLIC=$(stellar keys address "$USER2_KEY_ALIAS")

USER1_SECRET=$(stellar keys show "$USER1_KEY_ALIAS")
USER2_SECRET=$(stellar keys show "$USER2_KEY_ALIAS")

if [ "$NETWORK" = "testnet" ]; then
  echo "Funding accounts via Friendbot..."
  curl -sS "https://friendbot.stellar.org/?addr=${USER1_PUBLIC}" > /dev/null || true
  curl -sS "https://friendbot.stellar.org/?addr=${USER2_PUBLIC}" > /dev/null || true
  curl -sS "https://friendbot.stellar.org/?addr=${MATCHING_ENGINE_PUBLIC}" > /dev/null || true
  sleep 5
fi

if [ -z "${BASE_TOKEN_ID:-}" ]; then
  BASE_TOKEN_ID=$(stellar contract id asset --asset native --network "$NETWORK")
fi
if [ -z "${QUOTE_TOKEN_ID:-}" ]; then
  QUOTE_TOKEN_ID=$(stellar contract id asset --asset native --network "$NETWORK")
fi

ADMIN_ALIAS=${STELLAR_SOURCE:-admin}
if stellar keys ls 2>/dev/null | grep -q "^${ADMIN_ALIAS}$"; then
  echo "Authorizing matching engine in settlement contract using ${ADMIN_ALIAS}..."
  stellar contract invoke \
    --id "$SETTLEMENT_CONTRACT_ID" \
    --source "$ADMIN_ALIAS" \
    --network "$NETWORK" \
    -- \
    set_matching_engine \
    --matching_engine "$MATCHING_ENGINE_PUBLIC"
else
  echo "Skipping matching engine authorization (no ${ADMIN_ALIAS} key found)."
fi

echo "Depositing funds into settlement contract..."
DEPOSIT_AMOUNT=1000000000
stellar contract invoke \
  --id "$SETTLEMENT_CONTRACT_ID" \
  --source "$USER1_KEY_ALIAS" \
  --network "$NETWORK" \
  -- \
  deposit --user "$USER1_PUBLIC" --token "$QUOTE_TOKEN_ID" --amount "$DEPOSIT_AMOUNT"
stellar contract invoke \
  --id "$SETTLEMENT_CONTRACT_ID" \
  --source "$USER2_KEY_ALIAS" \
  --network "$NETWORK" \
  -- \
  deposit --user "$USER2_PUBLIC" --token "$BASE_TOKEN_ID" --amount "$DEPOSIT_AMOUNT"

get_balance() {
  local key_alias=$1
  local user_addr=$2
  local token_id=$3

  stellar contract invoke \
    --id "$SETTLEMENT_CONTRACT_ID" \
    --source "$key_alias" \
    --network "$NETWORK" \
    -- \
    get_balance --user "$user_addr" --token "$token_id" 2>&1 | grep -o '"[0-9]*"' | tr -d '"' | head -1
}

echo "Checking balances before orders..."
buyer_before=$(get_balance "$USER1_KEY_ALIAS" "$USER1_PUBLIC" "$BASE_TOKEN_ID")
seller_before=$(get_balance "$USER2_KEY_ALIAS" "$USER2_PUBLIC" "$BASE_TOKEN_ID")
echo "Buyer balance before: ${buyer_before}"
echo "Seller balance before: ${seller_before}"

order_json() {
  local order_id=$1
  local user_address=$2
  local side=$3
  local ts=$4

  local asset_base="XLM"
  local asset_quote="XLM"
  local order_price=0.5
  local order_qty=10
  local time_in_force="GTC"

  cat <<JSON
{"order_id":"${order_id}","user_address":"${user_address}","asset_pair":{"base":"${asset_base}","quote":"${asset_quote}"},"side":"${side}","order_type":"Limit","price":${order_price},"quantity":${order_qty},"time_in_force":"${time_in_force}","timestamp":${ts}}
JSON
}

sign_order() {
  local secret=$1
  local json=$2
  python3 scripts/sign_order.py "$secret" "$json"
}

add_signature() {
  local json=$1
  local signature=$2
  python3 -c 'import json,sys; obj=json.loads(sys.argv[1]); obj["signature"]=sys.argv[2]; print(json.dumps(obj))' "$json" "$signature"
}

submit_order() {
  local payload=$1
  curl -sS \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$payload" \
    "${BASE_URL}/api/v1/orders"
}

ts=$(date +%s)
order_id_buy="demo-order-${ts}-buy"
order_id_sell="demo-order-${ts}-sell"

buy_json=$(order_json "$order_id_buy" "$USER1_PUBLIC" "Buy" "$ts")
buy_sig=$(sign_order "$USER1_SECRET" "$buy_json")
buy_req=$(add_signature "$buy_json" "$buy_sig")

sell_json=$(order_json "$order_id_sell" "$USER2_PUBLIC" "Sell" "$ts")
sell_sig=$(sign_order "$USER2_SECRET" "$sell_json")
sell_req=$(add_signature "$sell_json" "$sell_sig")

echo "Submitting buy order: ${order_id_buy}"
submit_order "$buy_req" || {
  echo "Buy order failed" >&2
  exit 1
}

echo "Submitting sell order: ${order_id_sell}"
submit_order "$sell_req" || {
  echo "Sell order failed" >&2
  exit 1
}

echo "Orders submitted. Waiting for settlement..."
delta=$(python3 - <<PY
from decimal import Decimal, ROUND_HALF_UP

price = Decimal("0.5")
qty = Decimal("10")
stroops = Decimal("10000000")
net = (qty - (qty * price)) * stroops
print(int(net.to_integral_value(rounding=ROUND_HALF_UP)))
PY
)

expected_buyer=$((buyer_before + delta))
expected_seller=$((seller_before - delta))

settled=false
for _ in {1..15}; do
  sleep 2
  buyer_after=$(get_balance "$USER1_KEY_ALIAS" "$USER1_PUBLIC" "$BASE_TOKEN_ID")
  seller_after=$(get_balance "$USER2_KEY_ALIAS" "$USER2_PUBLIC" "$BASE_TOKEN_ID")
  if [ "$buyer_after" = "$expected_buyer" ] && [ "$seller_after" = "$expected_seller" ]; then
    settled=true
    break
  fi
done

echo "Buyer balance after: ${buyer_after}"
echo "Seller balance after: ${seller_after}"

if [ "$settled" = true ]; then
  echo "Settlement verified (balances match expected)."
else
  echo "Settlement not verified. Expected buyer=${expected_buyer}, seller=${expected_seller}." >&2
  exit 1
fi
