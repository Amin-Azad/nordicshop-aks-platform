#!/usr/bin/env bash
set -Eeuo pipefail

# NordicShop AKS Vendor Journey & Isolation Test
#
# Basic run:
#   BASE_URL="http://20.73.231.149" ./tests/aks/vendor-isolation.sh
#
# Save a timestamped evidence log:
#   BASE_URL="http://20.73.231.149" SAVE_EVIDENCE=1 ./tests/aks/vendor-isolation.sh
#
# Optional:
#   EXPECTED_ORDER_ID=1
#   VENDOR_A_USER=1
#   VENDOR_B_USER=2

BASE_URL="${BASE_URL:-http://20.73.231.149}"
VENDOR_A_USER="${VENDOR_A_USER:-1}"
VENDOR_B_USER="${VENDOR_B_USER:-2}"
EXPECTED_ORDER_ID="${EXPECTED_ORDER_ID:-}"
SAVE_EVIDENCE="${SAVE_EVIDENCE:-0}"
EVIDENCE_FILE="${EVIDENCE_FILE:-}"

PASS_COUNT=0
FAIL_COUNT=0

if [[ "$BASE_URL" == *"["* || "$BASE_URL" == *"]("* || "$BASE_URL" == *")"* ]]; then
  printf 'ERROR: BASE_URL looks Markdown-formatted: %s\n' "$BASE_URL" >&2
  printf 'Use a plain URL, for example: BASE_URL="http://20.73.231.149"\n' >&2
  exit 2
fi

BASE_URL="${BASE_URL%/}"

for cmd in curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    printf 'ERROR: required command not found: %s\n' "$cmd" >&2
    exit 2
  }
done

if [[ "$SAVE_EVIDENCE" == "1" && -z "$EVIDENCE_FILE" ]]; then
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  EVIDENCE_FILE="docs/evidence/aks/vendor-isolation-${timestamp}.log"
fi

if [[ -n "$EVIDENCE_FILE" ]]; then
  mkdir -p "$(dirname "$EVIDENCE_FILE")"
  exec > >(tee "$EVIDENCE_FILE") 2>&1
fi

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL: %s\n' "$1" >&2
  printf 'SUMMARY: %d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT" >&2
  exit 1
}

assert_json() {
  local body="$1"
  local label="$2"
  echo "$body" | jq -e . >/dev/null 2>&1 || fail "$label returned invalid JSON"
}

assert_status() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label returned HTTP $actual (expected $expected)"
}

HTTP_STATUS=""
HTTP_BODY=""

request_json() {
  local method="$1"
  local path="$2"
  local user_id="${3:-}"
  local body="${4:-}"

  local tmp
  tmp="$(mktemp)"

  local args=(
    -sS
    -o "$tmp"
    -w '%{http_code}'
    -X "$method"
    "$BASE_URL$path"
    -H 'Accept: application/json'
  )

  if [[ -n "$user_id" ]]; then
    args+=(-H "X-Demo-User: $user_id")
  fi

  if [[ -n "$body" ]]; then
    args+=(-H 'Content-Type: application/json' --data "$body")
  fi

  if ! HTTP_STATUS="$(curl "${args[@]}")"; then
    rm -f "$tmp"
    fail "$method $path could not reach $BASE_URL"
  fi

  HTTP_BODY="$(cat "$tmp")"
  rm -f "$tmp"
}

OWNED_PRODUCT_ID=""
ORIGINAL_A_STOCK=""
STOCK_CHANGED=0

restore_stock() {
  if [[ "$STOCK_CHANGED" == "1" && -n "$OWNED_PRODUCT_ID" && -n "$ORIGINAL_A_STOCK" ]]; then
    curl -sS -o /dev/null \
      -X PATCH "$BASE_URL/api/vendor/products/$OWNED_PRODUCT_ID/stock" \
      -H "X-Demo-User: $VENDOR_A_USER" \
      -H 'Content-Type: application/json' \
      --data "{\"stock\":$ORIGINAL_A_STOCK}" || true
  fi
}
trap restore_stock EXIT

printf 'NordicShop AKS Vendor Journey & Isolation\n'
printf 'BASE_URL:      %s\n' "$BASE_URL"
printf 'Vendor A user: %s\n' "$VENDOR_A_USER"
printf 'Vendor B user: %s\n' "$VENDOR_B_USER"
if [[ -n "$EXPECTED_ORDER_ID" ]]; then
  printf 'Expected order: %s\n' "$EXPECTED_ORDER_ID"
fi
printf '%s\n' '--------------------------------------------------'

request_json GET "/api/health"
assert_status 200 "$HTTP_STATUS" "API health"
assert_json "$HTTP_BODY" "API health"
echo "$HTTP_BODY" | jq -e '.status == "ok"' >/dev/null || fail "API health status is not ok"
pass "API health"

request_json GET "/api/ready"
assert_status 200 "$HTTP_STATUS" "API readiness"
assert_json "$HTTP_BODY" "API readiness"
echo "$HTTP_BODY" | jq -e '.status == "ready"' >/dev/null || fail "API readiness status is not ready"
pass "API readiness"

request_json GET "/api/vendor/me" "$VENDOR_A_USER"
assert_status 200 "$HTTP_STATUS" "Vendor A identity"
assert_json "$HTTP_BODY" "Vendor A identity"
VENDOR_A_ME="$HTTP_BODY"
A_TENANT_ID="$(echo "$VENDOR_A_ME" | jq -er '.tenant_id')"
A_TENANT_NAME="$(echo "$VENDOR_A_ME" | jq -er '.tenant')"
pass "Vendor A identity maps to tenant $A_TENANT_ID ($A_TENANT_NAME)"

request_json GET "/api/vendor/me" "$VENDOR_B_USER"
assert_status 200 "$HTTP_STATUS" "Vendor B identity"
assert_json "$HTTP_BODY" "Vendor B identity"
VENDOR_B_ME="$HTTP_BODY"
B_TENANT_ID="$(echo "$VENDOR_B_ME" | jq -er '.tenant_id')"
B_TENANT_NAME="$(echo "$VENDOR_B_ME" | jq -er '.tenant')"
pass "Vendor B identity maps to tenant $B_TENANT_ID ($B_TENANT_NAME)"

[[ "$A_TENANT_ID" != "$B_TENANT_ID" ]] || fail "Vendor A and Vendor B unexpectedly map to the same tenant"
pass "Vendor A and Vendor B map to different tenants"

request_json GET "/api/vendor/products" "$VENDOR_A_USER"
assert_status 200 "$HTTP_STATUS" "Vendor A products"
assert_json "$HTTP_BODY" "Vendor A products"
VENDOR_A_PRODUCTS="$HTTP_BODY"
echo "$VENDOR_A_PRODUCTS" | jq -e 'type == "array" and length > 0' >/dev/null || fail "Vendor A product list is empty or not an array"
echo "$VENDOR_A_PRODUCTS" | jq -e --argjson tenant "$A_TENANT_ID" 'all(.[]; .tenant_id == $tenant)' >/dev/null || fail "Vendor A received a product outside tenant $A_TENANT_ID"
A_PRODUCT_COUNT="$(echo "$VENDOR_A_PRODUCTS" | jq 'length')"
pass "Vendor A sees only tenant $A_TENANT_ID products ($A_PRODUCT_COUNT products)"

request_json GET "/api/vendor/products" "$VENDOR_B_USER"
assert_status 200 "$HTTP_STATUS" "Vendor B products"
assert_json "$HTTP_BODY" "Vendor B products"
VENDOR_B_PRODUCTS="$HTTP_BODY"
echo "$VENDOR_B_PRODUCTS" | jq -e 'type == "array" and length > 0' >/dev/null || fail "Vendor B product list is empty or not an array"
echo "$VENDOR_B_PRODUCTS" | jq -e --argjson tenant "$B_TENANT_ID" 'all(.[]; .tenant_id == $tenant)' >/dev/null || fail "Vendor B received a product outside tenant $B_TENANT_ID"
B_PRODUCT_COUNT="$(echo "$VENDOR_B_PRODUCTS" | jq 'length')"
pass "Vendor B sees only tenant $B_TENANT_ID products ($B_PRODUCT_COUNT products)"

A_IDS="$(echo "$VENDOR_A_PRODUCTS" | jq '[.[].id]')"
B_IDS="$(echo "$VENDOR_B_PRODUCTS" | jq '[.[].id]')"
jq -n -e --argjson a "$A_IDS" --argjson b "$B_IDS" '[$a[] | select(. as $x | $b | index($x) != null)] | length == 0' >/dev/null || fail "Vendor product sets overlap"
pass "Vendor A and Vendor B product sets are disjoint"

request_json GET "/api/vendor/orders" "$VENDOR_A_USER"
assert_status 200 "$HTTP_STATUS" "Vendor A orders"
assert_json "$HTTP_BODY" "Vendor A orders"
VENDOR_A_ORDERS="$HTTP_BODY"
echo "$VENDOR_A_ORDERS" | jq -e 'type == "array"' >/dev/null || fail "Vendor A orders is not an array"
A_ALLOWED_NAMES="$(echo "$VENDOR_A_PRODUCTS" | jq '[.[].name]')"
echo "$VENDOR_A_ORDERS" | jq -e --argjson allowed "$A_ALLOWED_NAMES" 'all(.[]; .product as $p | ($allowed | index($p)) != null)' >/dev/null || fail "Vendor A order data contains a product not owned by Vendor A"
pass "Vendor A order data contains only Vendor A products"

request_json GET "/api/vendor/orders" "$VENDOR_B_USER"
assert_status 200 "$HTTP_STATUS" "Vendor B orders"
assert_json "$HTTP_BODY" "Vendor B orders"
VENDOR_B_ORDERS="$HTTP_BODY"
echo "$VENDOR_B_ORDERS" | jq -e 'type == "array"' >/dev/null || fail "Vendor B orders is not an array"
B_ALLOWED_NAMES="$(echo "$VENDOR_B_PRODUCTS" | jq '[.[].name]')"
echo "$VENDOR_B_ORDERS" | jq -e --argjson allowed "$B_ALLOWED_NAMES" 'all(.[]; .product as $p | ($allowed | index($p)) != null)' >/dev/null || fail "Vendor B order data contains a product not owned by Vendor B"
pass "Vendor B order data contains only Vendor B products"

if [[ -n "$EXPECTED_ORDER_ID" ]]; then
  echo "$VENDOR_A_ORDERS" | jq -e --argjson oid "$EXPECTED_ORDER_ID" 'any(.[]; .order_id == $oid)' >/dev/null || fail "Vendor A cannot see its line from expected order $EXPECTED_ORDER_ID"
  echo "$VENDOR_B_ORDERS" | jq -e --argjson oid "$EXPECTED_ORDER_ID" 'any(.[]; .order_id == $oid)' >/dev/null || fail "Vendor B cannot see its line from expected order $EXPECTED_ORDER_ID"
  pass "Both vendors see their own line from mixed-vendor order $EXPECTED_ORDER_ID"
fi

OWNED_PRODUCT_ID="$(echo "$VENDOR_A_PRODUCTS" | jq -er '.[0].id')"
ORIGINAL_A_STOCK="$(echo "$VENDOR_A_PRODUCTS" | jq -er '.[0].stock')"

if (( ORIGINAL_A_STOCK < 10000 )); then
  NEW_A_STOCK=$((ORIGINAL_A_STOCK + 1))
else
  NEW_A_STOCK=$((ORIGINAL_A_STOCK - 1))
fi

request_json PATCH "/api/vendor/products/$OWNED_PRODUCT_ID/stock" "$VENDOR_A_USER" "{\"stock\":$NEW_A_STOCK}"
assert_status 200 "$HTTP_STATUS" "Vendor A owned stock update"
assert_json "$HTTP_BODY" "Vendor A owned stock update"
echo "$HTTP_BODY" | jq -e --argjson id "$OWNED_PRODUCT_ID" --argjson tenant "$A_TENANT_ID" --argjson stock "$NEW_A_STOCK" '.id == $id and .tenant_id == $tenant and .stock == $stock' >/dev/null || fail "Vendor A stock update response did not match expected owned product"
STOCK_CHANGED=1
pass "Vendor A can update stock for owned product $OWNED_PRODUCT_ID ($ORIGINAL_A_STOCK -> $NEW_A_STOCK)"

B_TARGET_ID="$(echo "$VENDOR_B_PRODUCTS" | jq -er '.[0].id')"
B_ORIGINAL_STOCK="$(echo "$VENDOR_B_PRODUCTS" | jq -er '.[0].stock')"

if (( B_ORIGINAL_STOCK < 10000 )); then
  B_FORBIDDEN_STOCK=$((B_ORIGINAL_STOCK + 1))
else
  B_FORBIDDEN_STOCK=$((B_ORIGINAL_STOCK - 1))
fi

request_json PATCH "/api/vendor/products/$B_TARGET_ID/stock" "$VENDOR_A_USER" "{\"stock\":$B_FORBIDDEN_STOCK}"
assert_status 404 "$HTTP_STATUS" "Vendor A cross-tenant update"
assert_json "$HTTP_BODY" "Vendor A cross-tenant update"
pass "Vendor A is denied when updating Vendor B product $B_TARGET_ID (HTTP 404)"

request_json GET "/api/vendor/products" "$VENDOR_B_USER"
assert_status 200 "$HTTP_STATUS" "Vendor B products after denied update"
assert_json "$HTTP_BODY" "Vendor B products after denied update"
echo "$HTTP_BODY" | jq -e --argjson id "$B_TARGET_ID" --argjson stock "$B_ORIGINAL_STOCK" 'any(.[]; .id == $id and .stock == $stock)' >/dev/null || fail "Vendor B product stock changed after Vendor A's denied request"
pass "Vendor B stock remains unchanged after Vendor A cross-tenant attempt"

request_json PATCH "/api/vendor/products/$OWNED_PRODUCT_ID/stock" "$VENDOR_B_USER" "{\"stock\":$ORIGINAL_A_STOCK}"
assert_status 404 "$HTTP_STATUS" "Vendor B cross-tenant update"
assert_json "$HTTP_BODY" "Vendor B cross-tenant update"
pass "Vendor B is denied when updating Vendor A product $OWNED_PRODUCT_ID (HTTP 404)"

request_json PATCH "/api/vendor/products/$OWNED_PRODUCT_ID/stock" "$VENDOR_A_USER" "{\"stock\":$ORIGINAL_A_STOCK}"
assert_status 200 "$HTTP_STATUS" "Vendor A stock restore"
assert_json "$HTTP_BODY" "Vendor A stock restore"
echo "$HTTP_BODY" | jq -e --argjson stock "$ORIGINAL_A_STOCK" '.stock == $stock' >/dev/null || fail "Vendor A stock restore did not return the original stock value"
STOCK_CHANGED=0
pass "Vendor A stock restored to original value $ORIGINAL_A_STOCK"

printf '%s\n' '--------------------------------------------------'
printf 'VENDOR JOURNEY & ISOLATION: PASS\n'
printf 'Vendor A tenant: %s (%s)\n' "$A_TENANT_ID" "$A_TENANT_NAME"
printf 'Vendor B tenant: %s (%s)\n' "$B_TENANT_ID" "$B_TENANT_NAME"
printf 'SUMMARY: %d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"

if [[ -n "$EVIDENCE_FILE" ]]; then
  printf 'Evidence file: %s\n' "$EVIDENCE_FILE"
fi
