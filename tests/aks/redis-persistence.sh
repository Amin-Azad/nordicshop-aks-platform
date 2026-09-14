#!/usr/bin/env bash
set -Eeuo pipefail

# NordicShop AKS Redis Cart Persistence Test
#
# Purpose:
#   - Create a fresh cart through the public API
#   - Verify cart contents
#   - Delete the current nordic-api Pod
#   - Wait for Kubernetes to create a Ready replacement
#   - Verify the same cart still exists after API replacement
#   - Optionally save timestamped evidence
#
# Basic run:
#   BASE_URL="http://20.73.231.149" ./tests/aks/redis-persistence.sh
#
# Save evidence:
#   BASE_URL="http://20.73.231.149" SAVE_EVIDENCE=1 ./tests/aks/redis-persistence.sh
#
# Optional overrides:
#   NAMESPACE=nordicshop
#   DEPLOYMENT=nordicshop-api
#   PRODUCT_ID=1
#   QUANTITY=2
#   TIMEOUT=180s

BASE_URL="${BASE_URL:-http://20.73.231.149}"
NAMESPACE="${NAMESPACE:-nordicshop}"
DEPLOYMENT="${DEPLOYMENT:-nordicshop-api}"
PRODUCT_ID="${PRODUCT_ID:-1}"
QUANTITY="${QUANTITY:-2}"
TIMEOUT="${TIMEOUT:-180s}"
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

for cmd in kubectl curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    printf 'ERROR: required command not found: %s\n' "$cmd" >&2
    exit 2
  }
done

if [[ "$SAVE_EVIDENCE" == "1" && -z "$EVIDENCE_FILE" ]]; then
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  EVIDENCE_FILE="docs/evidence/aks/redis-persistence-${timestamp}.log"
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
  local body="${3:-}"

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

printf 'NordicShop AKS Redis Cart Persistence Test\n'
printf 'Namespace:  %s\n' "$NAMESPACE"
printf 'Deployment: %s\n' "$DEPLOYMENT"
printf 'BASE_URL:   %s\n' "$BASE_URL"
printf 'Product ID: %s\n' "$PRODUCT_ID"
printf 'Quantity:   %s\n' "$QUANTITY"
printf 'Timeout:    %s\n' "$TIMEOUT"
printf '%s\n' '--------------------------------------------------'

# 1. Confirm API is healthy before starting.
request_json GET "/api/health"
assert_status 200 "$HTTP_STATUS" "API health"
assert_json "$HTTP_BODY" "API health"
echo "$HTTP_BODY" | jq -e '.status == "ok"' >/dev/null \
  || fail "API health status is not ok"
pass "API health before test"

request_json GET "/api/ready"
assert_status 200 "$HTTP_STATUS" "API readiness"
assert_json "$HTTP_BODY" "API readiness"
echo "$HTTP_BODY" | jq -e '.status == "ready"' >/dev/null \
  || fail "API readiness status is not ready"
pass "API readiness before test"

# 2. Confirm product exists and capture its live price/name for evidence.
request_json GET "/api/products"
assert_status 200 "$HTTP_STATUS" "Product catalogue"
assert_json "$HTTP_BODY" "Product catalogue"

PRODUCT_JSON="$(
  echo "$HTTP_BODY" |
  jq -c --argjson pid "$PRODUCT_ID" '.[] | select(.id == $pid)' |
  head -n 1
)"

[[ -n "$PRODUCT_JSON" ]] || fail "Product $PRODUCT_ID does not exist"

PRODUCT_NAME="$(echo "$PRODUCT_JSON" | jq -r '.name')"
PRODUCT_PRICE="$(echo "$PRODUCT_JSON" | jq -r '.price')"

pass "Product $PRODUCT_ID exists ($PRODUCT_NAME)"

# 3. Create a unique cart and add the selected product.
CART_ID="aks-redis-$(date -u +%Y%m%dT%H%M%SZ)-$$"

printf '\nCart ID: %s\n' "$CART_ID"

request_json POST "/api/cart/items" \
  "{\"cart_id\":\"$CART_ID\",\"product_id\":$PRODUCT_ID,\"quantity\":$QUANTITY}"

assert_status 201 "$HTTP_STATUS" "Add cart item"
assert_json "$HTTP_BODY" "Add cart item"
echo "$HTTP_BODY" | jq -e '.status == "added"' >/dev/null \
  || fail "Cart item add response did not report status=added"

pass "Added product $PRODUCT_ID x$QUANTITY to cart"

# 4. Read and validate the cart before API Pod deletion.
request_json GET "/api/cart/$CART_ID"
assert_status 200 "$HTTP_STATUS" "Cart read before API restart"
assert_json "$HTTP_BODY" "Cart before API restart"
CART_BEFORE="$HTTP_BODY"

echo "$CART_BEFORE" | jq -e \
  --argjson pid "$PRODUCT_ID" \
  --argjson qty "$QUANTITY" \
  'any(.items[]; .id == $pid and .quantity == $qty)' >/dev/null \
  || fail "Cart does not contain product $PRODUCT_ID x$QUANTITY before API restart"

EXPECTED_TOTAL="$(jq -n --argjson p "$PRODUCT_PRICE" --argjson q "$QUANTITY" '$p * $q')"
ACTUAL_TOTAL_BEFORE="$(echo "$CART_BEFORE" | jq -r '.total')"

jq -n -e \
  --argjson expected "$EXPECTED_TOTAL" \
  --argjson actual "$ACTUAL_TOTAL_BEFORE" \
  '$expected == $actual' >/dev/null \
  || fail "Cart total before restart is $ACTUAL_TOTAL_BEFORE, expected $EXPECTED_TOTAL"

pass "Cart verified before API Pod deletion"

# 5. Get the Deployment selector dynamically.
kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1 \
  || fail "Deployment $DEPLOYMENT does not exist in namespace $NAMESPACE"

SELECTOR="$(
  kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json |
  jq -r '.spec.selector.matchLabels
         | to_entries
         | map("\(.key)=\(.value)")
         | join(",")'
)"

[[ -n "$SELECTOR" && "$SELECTOR" != "null" ]] \
  || fail "Could not derive Pod selector from Deployment $DEPLOYMENT"

pass "Derived API Deployment selector"

# 6. Record the current Ready API Pod.
OLD_POD_JSON="$(
  kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" -o json |
  jq -c '
    [.items[]
     | select(
         any(.status.conditions[]?;
             .type == "Ready" and .status == "True")
       )
    ]
    | sort_by(.metadata.creationTimestamp)
    | first // empty
  '
)"

[[ -n "$OLD_POD_JSON" ]] || fail "No Ready API Pod found"

OLD_POD_NAME="$(echo "$OLD_POD_JSON" | jq -r '.metadata.name')"
OLD_POD_UID="$(echo "$OLD_POD_JSON" | jq -r '.metadata.uid')"

printf '\nCurrent API Pod: %s\n' "$OLD_POD_NAME"
printf 'Current API UID: %s\n' "$OLD_POD_UID"
pass "Recorded current API Pod"

# 7. Delete the API Pod.
kubectl delete pod "$OLD_POD_NAME" \
  -n "$NAMESPACE" \
  --wait=false >/dev/null \
  || fail "Could not delete API Pod $OLD_POD_NAME"

pass "Requested deletion of API Pod $OLD_POD_NAME"

# 8. Wait for Deployment recovery.
kubectl rollout status deployment/"$DEPLOYMENT" \
  -n "$NAMESPACE" \
  --timeout="$TIMEOUT" \
  || fail "API Deployment did not recover within $TIMEOUT"

pass "API Deployment recovered"

# 9. Find the replacement Ready Pod with a different UID.
NEW_POD_JSON="$(
  kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" -o json |
  jq -c --arg old_uid "$OLD_POD_UID" '
    [.items[]
     | select(.metadata.uid != $old_uid)
     | select(
         any(.status.conditions[]?;
             .type == "Ready" and .status == "True")
       )
    ]
    | sort_by(.metadata.creationTimestamp)
    | last // empty
  '
)"

[[ -n "$NEW_POD_JSON" ]] || fail "No Ready replacement API Pod found"

NEW_POD_NAME="$(echo "$NEW_POD_JSON" | jq -r '.metadata.name')"
NEW_POD_UID="$(echo "$NEW_POD_JSON" | jq -r '.metadata.uid')"

printf 'Replacement API Pod: %s\n' "$NEW_POD_NAME"
printf 'Replacement API UID: %s\n' "$NEW_POD_UID"

[[ "$NEW_POD_UID" != "$OLD_POD_UID" ]] \
  || fail "Replacement Pod UID matches deleted Pod UID"

pass "Ready replacement API Pod has a new UID"

# 10. Verify public API health after replacement.
request_json GET "/api/health"
assert_status 200 "$HTTP_STATUS" "API health after replacement"
assert_json "$HTTP_BODY" "API health after replacement"
echo "$HTTP_BODY" | jq -e '.status == "ok"' >/dev/null \
  || fail "API health after replacement is not ok"

pass "API health after replacement"

request_json GET "/api/ready"
assert_status 200 "$HTTP_STATUS" "API readiness after replacement"
assert_json "$HTTP_BODY" "API readiness after replacement"
echo "$HTTP_BODY" | jq -e '.status == "ready"' >/dev/null \
  || fail "API readiness after replacement is not ready"

pass "API readiness after replacement"

# 11. Read the exact same cart again.
request_json GET "/api/cart/$CART_ID"
assert_status 200 "$HTTP_STATUS" "Cart read after API replacement"
assert_json "$HTTP_BODY" "Cart after API replacement"
CART_AFTER="$HTTP_BODY"

echo "$CART_AFTER" | jq -e \
  --argjson pid "$PRODUCT_ID" \
  --argjson qty "$QUANTITY" \
  'any(.items[]; .id == $pid and .quantity == $qty)' >/dev/null \
  || fail "Cart item was lost after API Pod replacement"

ACTUAL_TOTAL_AFTER="$(echo "$CART_AFTER" | jq -r '.total')"

jq -n -e \
  --argjson before "$ACTUAL_TOTAL_BEFORE" \
  --argjson after "$ACTUAL_TOTAL_AFTER" \
  '$before == $after' >/dev/null \
  || fail "Cart total changed across API Pod replacement: before=$ACTUAL_TOTAL_BEFORE after=$ACTUAL_TOTAL_AFTER"

pass "Cart survived API Pod replacement unchanged"

printf '\nCart after API replacement:\n'
echo "$CART_AFTER" | jq .

printf '%s\n' '--------------------------------------------------'
printf 'REDIS CART PERSISTENCE: PASS\n'
printf 'Cart ID:         %s\n' "$CART_ID"
printf 'Product:         %s (%s)\n' "$PRODUCT_NAME" "$PRODUCT_ID"
printf 'Quantity:        %s\n' "$QUANTITY"
printf 'Cart total:      %s\n' "$ACTUAL_TOTAL_AFTER"
printf 'Deleted API Pod: %s\n' "$OLD_POD_NAME"
printf 'New API Pod:     %s\n' "$NEW_POD_NAME"
printf 'SUMMARY: %d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"

if [[ -n "$EVIDENCE_FILE" ]]; then
  printf 'Evidence file: %s\n' "$EVIDENCE_FILE"
fi
