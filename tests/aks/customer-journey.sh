#!/usr/bin/env bash
set -Eeuo pipefail

# NordicShop AKS customer journey smoke test
# Usage:
#   BASE_URL="http://20.73.231.149" ./tests/aks/customer-journey.sh
# Optional overrides:
#   PRODUCT_A_ID=1 PRODUCT_B_ID=6 PRODUCT_B_QTY=2 ./tests/aks/customer-journey.sh

BASE_URL="${BASE_URL:-http://20.73.231.149}"
PRODUCT_A_ID="${PRODUCT_A_ID:-1}"
PRODUCT_B_ID="${PRODUCT_B_ID:-6}"
PRODUCT_B_QTY="${PRODUCT_B_QTY:-2}"
CUSTOMER_NAME="${CUSTOMER_NAME:-AKS Customer Test}"
CUSTOMER_EMAIL="${CUSTOMER_EMAIL:-aks-customer-test@example.com}"
CURL_TIMEOUT="${CURL_TIMEOUT:-15}"

BASE_URL="${BASE_URL%/}"
CART_ID="aks-customer-$(date -u +%Y%m%dT%H%M%SZ)-$$"

PASS_COUNT=0
FAIL_COUNT=0
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

on_error() {
  local exit_code=$?
  local line_no=$1
  printf '\nFAIL: unexpected script error on line %s (exit %s)\n' "$line_no" "$exit_code" >&2
  printf 'SUMMARY: %d PASS / %d FAIL\n' "$PASS_COUNT" "$((FAIL_COUNT + 1))" >&2
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

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

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

is_json() {
  jq -e . >/dev/null 2>&1 <<<"$1"
}

http_request() {
  # Usage: http_request METHOD URL [JSON_BODY]
  local method=$1
  local url=$2
  local body=${3:-}
  local response_file="$TMP_DIR/body.json"
  local status

  if [[ -n "$body" ]]; then
    status=$(curl -sS \
      --connect-timeout "$CURL_TIMEOUT" \
      --max-time "$CURL_TIMEOUT" \
      -o "$response_file" \
      -w '%{http_code}' \
      -X "$method" \
      -H 'Accept: application/json' \
      -H 'Content-Type: application/json' \
      --data "$body" \
      "$url") || fail "HTTP request failed: $method $url"
  else
    status=$(curl -sS \
      --connect-timeout "$CURL_TIMEOUT" \
      --max-time "$CURL_TIMEOUT" \
      -o "$response_file" \
      -w '%{http_code}' \
      -X "$method" \
      -H 'Accept: application/json' \
      "$url") || fail "HTTP request failed: $method $url"
  fi

  HTTP_STATUS="$status"
  HTTP_BODY="$(cat "$response_file")"
}

expect_2xx_json() {
  local description=$1

  [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]] || {
    printf 'Response body:\n%s\n' "$HTTP_BODY" >&2
    fail "$description returned HTTP $HTTP_STATUS"
  }

  is_json "$HTTP_BODY" || {
    printf 'Response body:\n%s\n' "$HTTP_BODY" >&2
    fail "$description did not return valid JSON"
  }
}

require_command curl
require_command jq

printf 'NordicShop AKS Customer Journey\n'
printf 'BASE_URL: %s\n' "$BASE_URL"
printf 'CART_ID:  %s\n' "$CART_ID"
printf '%s\n' '--------------------------------------------------'

# 1. Health
http_request GET "$BASE_URL/api/health"
expect_2xx_json "Health endpoint"
jq -e '.status == "ok" and (.service? == "nordic-api" or .service? == null)' \
  >/dev/null <<<"$HTTP_BODY" || fail "Health JSON does not report status=ok"
pass "API health"

# 2. Readiness
http_request GET "$BASE_URL/api/ready"
expect_2xx_json "Readiness endpoint"
jq -e '.status == "ready"' >/dev/null <<<"$HTTP_BODY" \
  || fail "Readiness JSON does not report status=ready"
pass "API readiness"

# 3. Product catalogue
http_request GET "$BASE_URL/api/products"
expect_2xx_json "Products endpoint"
jq -e 'type == "array" and length > 0' >/dev/null <<<"$HTTP_BODY" \
  || fail "Products response is not a non-empty JSON array"

PRODUCTS_JSON="$HTTP_BODY"
PRODUCT_COUNT="$(jq 'length' <<<"$PRODUCTS_JSON")"
pass "Product catalogue contains $PRODUCT_COUNT products"

jq -e --argjson id "$PRODUCT_A_ID" '.[] | select(.id == $id)' >/dev/null <<<"$PRODUCTS_JSON" \
  || fail "Product $PRODUCT_A_ID is missing"
pass "Product $PRODUCT_A_ID exists"

jq -e --argjson id "$PRODUCT_B_ID" '.[] | select(.id == $id)' >/dev/null <<<"$PRODUCTS_JSON" \
  || fail "Product $PRODUCT_B_ID is missing"
pass "Product $PRODUCT_B_ID exists"

PRODUCT_A_PRICE="$(jq -r --argjson id "$PRODUCT_A_ID" '.[] | select(.id == $id) | .price' <<<"$PRODUCTS_JSON")"
PRODUCT_B_PRICE="$(jq -r --argjson id "$PRODUCT_B_ID" '.[] | select(.id == $id) | .price' <<<"$PRODUCTS_JSON")"

[[ "$PRODUCT_A_PRICE" != "null" && -n "$PRODUCT_A_PRICE" ]] || fail "Product $PRODUCT_A_ID has no numeric price"
[[ "$PRODUCT_B_PRICE" != "null" && -n "$PRODUCT_B_PRICE" ]] || fail "Product $PRODUCT_B_ID has no numeric price"

EXPECTED_TOTAL="$(jq -n \
  --argjson a "$PRODUCT_A_PRICE" \
  --argjson b "$PRODUCT_B_PRICE" \
  --argjson q "$PRODUCT_B_QTY" \
  '$a + ($b * $q)')"

# 4. Add first product
ADD_A_PAYLOAD="$(jq -n \
  --arg cart_id "$CART_ID" \
  --argjson product_id "$PRODUCT_A_ID" \
  '{cart_id:$cart_id, product_id:$product_id, quantity:1}')"

http_request POST "$BASE_URL/api/cart/items" "$ADD_A_PAYLOAD"
expect_2xx_json "Add product $PRODUCT_A_ID"
jq -e '.status == "added"' >/dev/null <<<"$HTTP_BODY" \
  || fail "Adding product $PRODUCT_A_ID did not return status=added"
pass "Added product $PRODUCT_A_ID to cart"

# 5. Add second product
ADD_B_PAYLOAD="$(jq -n \
  --arg cart_id "$CART_ID" \
  --argjson product_id "$PRODUCT_B_ID" \
  --argjson quantity "$PRODUCT_B_QTY" \
  '{cart_id:$cart_id, product_id:$product_id, quantity:$quantity}')"

http_request POST "$BASE_URL/api/cart/items" "$ADD_B_PAYLOAD"
expect_2xx_json "Add product $PRODUCT_B_ID"
jq -e '.status == "added"' >/dev/null <<<"$HTTP_BODY" \
  || fail "Adding product $PRODUCT_B_ID did not return status=added"
pass "Added product $PRODUCT_B_ID x$PRODUCT_B_QTY to cart"

# 6. Verify cart
http_request GET "$BASE_URL/api/cart/$CART_ID"
expect_2xx_json "Cart endpoint"
CART_JSON="$HTTP_BODY"

jq -e 'has("items") and (.items | type == "array") and has("total")' >/dev/null <<<"$CART_JSON" \
  || fail "Cart JSON is missing required items/total fields"
jq -e --argjson id "$PRODUCT_A_ID" '.items[] | select(.id == $id and .quantity == 1)' \
  >/dev/null <<<"$CART_JSON" || fail "Cart does not contain product $PRODUCT_A_ID with quantity 1"
pass "Cart contains product $PRODUCT_A_ID x1"

jq -e --argjson id "$PRODUCT_B_ID" --argjson qty "$PRODUCT_B_QTY" \
  '.items[] | select(.id == $id and .quantity == $qty)' \
  >/dev/null <<<"$CART_JSON" || fail "Cart does not contain product $PRODUCT_B_ID with quantity $PRODUCT_B_QTY"
pass "Cart contains product $PRODUCT_B_ID x$PRODUCT_B_QTY"

ACTUAL_TOTAL="$(jq -r '.total' <<<"$CART_JSON")"
TOTAL_MATCH="$(jq -n \
  --argjson actual "$ACTUAL_TOTAL" \
  --argjson expected "$EXPECTED_TOTAL" \
  '((($actual - $expected) | fabs) < 0.01)')"

[[ "$TOTAL_MATCH" == "true" ]] \
  || fail "Unexpected cart total: got $ACTUAL_TOTAL, expected $EXPECTED_TOTAL"
pass "Cart total matches expected value: $EXPECTED_TOTAL"

# 7. Checkout
ORDER_PAYLOAD="$(jq -n \
  --arg cart_id "$CART_ID" \
  --arg customer_name "$CUSTOMER_NAME" \
  --arg customer_email "$CUSTOMER_EMAIL" \
  '{cart_id:$cart_id, customer_name:$customer_name, customer_email:$customer_email}')"

http_request POST "$BASE_URL/api/orders" "$ORDER_PAYLOAD"
expect_2xx_json "Checkout endpoint"
ORDER_JSON="$HTTP_BODY"

ORDER_ID="$(jq -r '.id // .order_id // empty' <<<"$ORDER_JSON")"
[[ -n "$ORDER_ID" && "$ORDER_ID" != "null" ]] || {
  printf 'Order response:\n%s\n' "$(jq . <<<"$ORDER_JSON")" >&2
  fail "Checkout response does not contain an order ID"
}
pass "Checkout created order ID $ORDER_ID"

# Optional but useful structure checks when those fields are present.
if jq -e 'has("customer_name")' >/dev/null <<<"$ORDER_JSON"; then
  jq -e --arg expected "$CUSTOMER_NAME" '.customer_name == $expected' >/dev/null <<<"$ORDER_JSON" \
    || fail "Order customer_name does not match request"
fi

if jq -e 'has("customer_email")' >/dev/null <<<"$ORDER_JSON"; then
  jq -e --arg expected "$CUSTOMER_EMAIL" '.customer_email == $expected' >/dev/null <<<"$ORDER_JSON" \
    || fail "Order customer_email does not match request"
fi

# 8. Verify post-checkout cart state.
# NordicShop is expected to clear the cart after successful checkout.
http_request GET "$BASE_URL/api/cart/$CART_ID"
expect_2xx_json "Post-checkout cart endpoint"
POST_CART_JSON="$HTTP_BODY"

jq -e 'has("items") and (.items | type == "array") and has("total")' >/dev/null <<<"$POST_CART_JSON" \
  || fail "Post-checkout cart JSON is missing required items/total fields"

jq -e '(.items | length) == 0' >/dev/null <<<"$POST_CART_JSON" \
  || {
    printf 'Post-checkout cart:\n%s\n' "$(jq . <<<"$POST_CART_JSON")" >&2
    fail "Cart was not cleared after checkout"
  }

jq -e '(.total | tonumber) == 0' >/dev/null <<<"$POST_CART_JSON" \
  || fail "Post-checkout cart total is not zero"
pass "Post-checkout cart is empty"

printf '%s\n' '--------------------------------------------------'
printf 'CUSTOMER JOURNEY: PASS\n'
printf 'Order ID: %s\n' "$ORDER_ID"
printf 'Cart ID:  %s\n' "$CART_ID"
printf 'SUMMARY:  %d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
