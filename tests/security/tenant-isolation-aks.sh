#!/usr/bin/env bash

set -u

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
VENDOR_A=1
VENDOR_B=2
ADMIN=3

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
FILE_TIMESTAMP="$(date -u +"%Y%m%d-%H%M%S")"

EVIDENCE_DIR="docs/evidence/security-recovery"
EVIDENCE_FILE="${EVIDENCE_DIR}/tenant-isolation-${FILE_TIMESTAMP}.md"

PASS=0
FAIL=0

mkdir -p "$EVIDENCE_DIR"

pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}

status_code() {
    curl -s -o /dev/null -w "%{http_code}" "$@"
}

echo "NordicShop  - Tenant Isolation Acceptance"
echo "Timestamp: $TIMESTAMP"
echo

#
# 1. API health
#

CODE=$(status_code "${BASE_URL}/api/health")

if [ "$CODE" = "200" ]; then
    pass "API health endpoint returned 200"
else
    fail "API health endpoint returned $CODE"
fi

CODE=$(status_code "${BASE_URL}/api/ready")

if [ "$CODE" = "200" ]; then
    pass "API readiness endpoint returned 200"
else
    fail "API readiness endpoint returned $CODE"
fi


#
# 2. Discover vendors
#

A_ME=$(curl -s \
    -H "X-Demo-User: ${VENDOR_A}" \
    "${BASE_URL}/api/vendor/me")

B_ME=$(curl -s \
    -H "X-Demo-User: ${VENDOR_B}" \
    "${BASE_URL}/api/vendor/me")

A_TENANT=$(echo "$A_ME" | jq -r '.tenant_id')
B_TENANT=$(echo "$B_ME" | jq -r '.tenant_id')

echo
echo "Vendor A tenant: $A_TENANT"
echo "Vendor B tenant: $B_TENANT"


#
# 3. Verify vendor product scoping
#

A_PRODUCTS=$(curl -s \
    -H "X-Demo-User: ${VENDOR_A}" \
    "${BASE_URL}/api/vendor/products")

B_PRODUCTS=$(curl -s \
    -H "X-Demo-User: ${VENDOR_B}" \
    "${BASE_URL}/api/vendor/products")

A_WRONG=$(echo "$A_PRODUCTS" |
    jq --argjson tenant "$A_TENANT" \
    '[.[] | select(.tenant_id != $tenant)] | length')

B_WRONG=$(echo "$B_PRODUCTS" |
    jq --argjson tenant "$B_TENANT" \
    '[.[] | select(.tenant_id != $tenant)] | length')

if [ "$A_WRONG" = "0" ]; then
    pass "Vendor A received only tenant $A_TENANT products"
else
    fail "Vendor A received cross-tenant products"
fi

if [ "$B_WRONG" = "0" ]; then
    pass "Vendor B received only tenant $B_TENANT products"
else
    fail "Vendor B received cross-tenant products"
fi


#
# 4. Authentication and role authorization
#

CODE=$(status_code "${BASE_URL}/api/vendor/products")

if [ "$CODE" = "401" ]; then
    pass "Missing identity was rejected with 401"
else
    fail "Missing identity returned $CODE instead of 401"
fi

CODE=$(status_code \
    -H "X-Demo-User: ${VENDOR_A}" \
    "${BASE_URL}/api/admin/summary")

if [ "$CODE" = "403" ]; then
    pass "Vendor A was denied admin access with 403"
else
    fail "Vendor A admin request returned $CODE"
fi

CODE=$(status_code \
    -H "X-Demo-User: ${ADMIN}" \
    "${BASE_URL}/api/admin/summary")

if [ "$CODE" = "200" ]; then
    pass "Admin identity successfully accessed admin API"
else
    fail "Admin API returned $CODE"
fi


#
# 5. Select one product from each tenant dynamically
#

A_PRODUCT_ID=$(echo "$A_PRODUCTS" | jq -r '.[0].id')
B_PRODUCT_ID=$(echo "$B_PRODUCTS" | jq -r '.[0].id')

A_ORIGINAL_STOCK=$(echo "$A_PRODUCTS" |
    jq -r --argjson id "$A_PRODUCT_ID" \
    '.[] | select(.id == $id) | .stock')

B_ORIGINAL_STOCK=$(echo "$B_PRODUCTS" |
    jq -r --argjson id "$B_PRODUCT_ID" \
    '.[] | select(.id == $id) | .stock')

echo
echo "Vendor A test product: $A_PRODUCT_ID"
echo "Vendor B test product: $B_PRODUCT_ID"


#
# 6. Vendor A attempts to modify Vendor B
#

CODE=$(curl -s \
    -o /dev/null \
    -w "%{http_code}" \
    -X PATCH \
    -H "Content-Type: application/json" \
    -H "X-Demo-User: ${VENDOR_A}" \
    -d '{"stock":999}' \
    "${BASE_URL}/api/vendor/products/${B_PRODUCT_ID}/stock")

if [ "$CODE" = "403" ] || [ "$CODE" = "404" ]; then
    pass "Vendor A could not modify Vendor B product ($CODE)"
else
    fail "Vendor A -> Vendor B modification returned $CODE"
fi


#
# 7. Vendor B attempts to modify Vendor A
#

CODE=$(curl -s \
    -o /dev/null \
    -w "%{http_code}" \
    -X PATCH \
    -H "Content-Type: application/json" \
    -H "X-Demo-User: ${VENDOR_B}" \
    -d '{"stock":999}' \
    "${BASE_URL}/api/vendor/products/${A_PRODUCT_ID}/stock")

if [ "$CODE" = "403" ] || [ "$CODE" = "404" ]; then
    pass "Vendor B could not modify Vendor A product ($CODE)"
else
    fail "Vendor B -> Vendor A modification returned $CODE"
fi


#
# 8. Verify target products were not changed
#

A_AFTER=$(curl -s \
    -H "X-Demo-User: ${VENDOR_A}" \
    "${BASE_URL}/api/vendor/products")

B_AFTER=$(curl -s \
    -H "X-Demo-User: ${VENDOR_B}" \
    "${BASE_URL}/api/vendor/products")

A_AFTER_STOCK=$(echo "$A_AFTER" |
    jq -r --argjson id "$A_PRODUCT_ID" \
    '.[] | select(.id == $id) | .stock')

B_AFTER_STOCK=$(echo "$B_AFTER" |
    jq -r --argjson id "$B_PRODUCT_ID" \
    '.[] | select(.id == $id) | .stock')

if [ "$A_AFTER_STOCK" = "$A_ORIGINAL_STOCK" ]; then
    pass "Vendor A product remained unchanged"
else
    fail "Vendor A product stock changed unexpectedly"
fi

if [ "$B_AFTER_STOCK" = "$B_ORIGINAL_STOCK" ]; then
    pass "Vendor B product remained unchanged"
else
    fail "Vendor B product stock changed unexpectedly"
fi


#
# 9. Summary
#

echo
echo "=============================="
echo "Tenant Isolation Result"
echo "=============================="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [ "$FAIL" -eq 0 ]; then
    RESULT="PASS"
else
    RESULT="FAIL"
fi

cat > "$EVIDENCE_FILE" <<EOF
# NordicShop - Tenant Isolation Evidence

**Timestamp:** $TIMESTAMP  
**Environment:** AKS  
**API:** $BASE_URL  
**Result:** **$RESULT**

## Test summary

- Passed: $PASS
- Failed: $FAIL
- Vendor A tenant: $A_TENANT
- Vendor B tenant: $B_TENANT
- Vendor A test product: $A_PRODUCT_ID
- Vendor B test product: $B_PRODUCT_ID

## Controls verified

- Nordic API health and readiness
- Vendor A tenant-scoped product visibility
- Vendor B tenant-scoped product visibility
- Missing identity rejection
- Vendor-to-admin authorization denial
- Administrator authorization
- Vendor A cannot modify Vendor B product
- Vendor B cannot modify Vendor A product
- Cross-tenant attempts do not change protected data

## Result

**$RESULT**
EOF

echo
echo "Evidence: $EVIDENCE_FILE"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
