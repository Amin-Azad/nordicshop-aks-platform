#!/usr/bin/env bash
set -Eeuo pipefail

# NordicShop AKS Admin Authorization Test
#
# Basic run:
#   BASE_URL="http://20.73.231.149" ./tests/aks/admin-authorization.sh
#
# Save a timestamped evidence log:
#   BASE_URL="http://20.73.231.149" SAVE_EVIDENCE=1 ./tests/aks/admin-authorization.sh
#
# Optional overrides:
#   ADMIN_USER=3
#   VENDOR_A_USER=1
#   VENDOR_B_USER=2
#   EXPECTED_ORDER_ID=1

BASE_URL="${BASE_URL:-http://20.73.231.149}"
ADMIN_USER="${ADMIN_USER:-3}"
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
  EVIDENCE_FILE="docs/evidence/aks/admin-authorization-${timestamp}.log"
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

  if ! HTTP_STATUS="$(curl "${args[@]}")"; then
    rm -f "$tmp"
    fail "$method $path could not reach $BASE_URL"
  fi

  HTTP_BODY="$(cat "$tmp")"
  rm -f "$tmp"
}

printf 'NordicShop AKS Admin Authorization\n'
printf 'BASE_URL:      %s\n' "$BASE_URL"
printf 'Admin user:    %s\n' "$ADMIN_USER"
printf 'Vendor A user: %s\n' "$VENDOR_A_USER"
printf 'Vendor B user: %s\n' "$VENDOR_B_USER"
if [[ -n "$EXPECTED_ORDER_ID" ]]; then
  printf 'Expected order: %s\n' "$EXPECTED_ORDER_ID"
fi
printf '%s\n' '--------------------------------------------------'

# 1. API health
request_json GET "/api/health"
assert_status 200 "$HTTP_STATUS" "API health"
assert_json "$HTTP_BODY" "API health"
echo "$HTTP_BODY" | jq -e '.status == "ok"' >/dev/null || fail "API health status is not ok"
pass "API health"

# 2. API readiness
request_json GET "/api/ready"
assert_status 200 "$HTTP_STATUS" "API readiness"
assert_json "$HTTP_BODY" "API readiness"
echo "$HTTP_BODY" | jq -e '.status == "ready"' >/dev/null || fail "API readiness status is not ready"
pass "API readiness"

# 3. Admin summary
request_json GET "/api/admin/summary" "$ADMIN_USER"
assert_status 200 "$HTTP_STATUS" "Admin summary"
assert_json "$HTTP_BODY" "Admin summary"
ADMIN_SUMMARY="$HTTP_BODY"

echo "$ADMIN_SUMMARY" | jq -e 'type == "object"' >/dev/null \
  || fail "Admin summary is not a JSON object"

# Require at least one numeric counter in the summary, without assuming exact field names.
echo "$ADMIN_SUMMARY" | jq -e '
  [to_entries[] | select(.value | type == "number")] | length > 0
' >/dev/null || fail "Admin summary contains no numeric counters"

pass "Admin summary is accessible and contains numeric marketplace counters"

# 4. Admin vendor listing
request_json GET "/api/admin/vendors" "$ADMIN_USER"
assert_status 200 "$HTTP_STATUS" "Admin vendor listing"
assert_json "$HTTP_BODY" "Admin vendor listing"
ADMIN_VENDORS="$HTTP_BODY"

echo "$ADMIN_VENDORS" | jq -e 'type == "array" and length >= 2' >/dev/null \
  || fail "Admin vendor listing does not contain at least two vendors"

pass "Admin vendor listing is accessible and contains at least two vendors"

# 5. Admin order listing
request_json GET "/api/admin/orders" "$ADMIN_USER"
assert_status 200 "$HTTP_STATUS" "Admin order listing"
assert_json "$HTTP_BODY" "Admin order listing"
ADMIN_ORDERS="$HTTP_BODY"

echo "$ADMIN_ORDERS" | jq -e 'type == "array"' >/dev/null \
  || fail "Admin order listing is not an array"

pass "Admin order listing is accessible"

# Optional: prove the customer order created earlier is visible to admin.
if [[ -n "$EXPECTED_ORDER_ID" ]]; then
  echo "$ADMIN_ORDERS" | jq -e --argjson oid "$EXPECTED_ORDER_ID" '
    any(.[]; (.id // .order_id) == $oid)
  ' >/dev/null || fail "Expected order $EXPECTED_ORDER_ID is missing from admin order listing"

  pass "Admin can see expected order $EXPECTED_ORDER_ID"
fi

# 6. Vendor A must be denied from every admin route.
for route in "/api/admin/summary" "/api/admin/vendors" "/api/admin/orders"; do
  request_json GET "$route" "$VENDOR_A_USER"
  assert_status 403 "$HTTP_STATUS" "Vendor A access to $route"
  assert_json "$HTTP_BODY" "Vendor A denial for $route"
  pass "Vendor A denied from $route (HTTP 403)"
done

# 7. Vendor B must also be denied from every admin route.
for route in "/api/admin/summary" "/api/admin/vendors" "/api/admin/orders"; do
  request_json GET "$route" "$VENDOR_B_USER"
  assert_status 403 "$HTTP_STATUS" "Vendor B access to $route"
  assert_json "$HTTP_BODY" "Vendor B denial for $route"
  pass "Vendor B denied from $route (HTTP 403)"
done

# 8. Missing identity should not be allowed to use admin routes.
for route in "/api/admin/summary" "/api/admin/vendors" "/api/admin/orders"; do
  request_json GET "$route"
  if [[ "$HTTP_STATUS" != "401" && "$HTTP_STATUS" != "403" ]]; then
    fail "Missing identity access to $route returned HTTP $HTTP_STATUS (expected 401 or 403)"
  fi
  assert_json "$HTTP_BODY" "Missing identity denial for $route"
  pass "Missing identity denied from $route (HTTP $HTTP_STATUS)"
done

printf '%s\n' '--------------------------------------------------'
printf 'ADMIN AUTHORIZATION: PASS\n'
printf 'SUMMARY: %d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"

if [[ -n "$EVIDENCE_FILE" ]]; then
  printf 'Evidence file: %s\n' "$EVIDENCE_FILE"
fi
