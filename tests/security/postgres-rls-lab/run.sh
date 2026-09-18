#!/usr/bin/env bash
set -Eeuo pipefail

LAB_NS="nordicshop-rls-lab"
LAB_POD="postgres-rls-lab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
EVIDENCE_DIR="$ROOT_DIR/docs/evidence/security-recovery"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
REPORT="$EVIDENCE_DIR/postgres-rls-lab-${STAMP}.md"
PASS=0
FAIL=0

mkdir -p "$EVIDENCE_DIR"

log() { printf '%s\n' "$*" | tee -a "$REPORT"; }
pass() { PASS=$((PASS+1)); log "- PASS: $*"; }
fail() { FAIL=$((FAIL+1)); log "- FAIL: $*"; }

cleanup() {
  kubectl delete namespace "$LAB_NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is required." >&2
  exit 2
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: kubectl cannot reach a Kubernetes cluster." >&2
  exit 2
fi

# Refuse to reuse an existing namespace unless it is clearly this lab.
if kubectl get namespace "$LAB_NS" >/dev/null 2>&1; then
  LABEL="$(kubectl get namespace "$LAB_NS" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/name}' 2>/dev/null || true)"
  if [[ "$LABEL" != "nordicshop-rls-lab" ]]; then
    echo "ERROR: namespace $LAB_NS already exists and is not labelled as this lab." >&2
    exit 2
  fi
  kubectl delete namespace "$LAB_NS" --wait=true >/dev/null
fi

cat > "$REPORT" <<EOF
# NordicShop PostgreSQL RLS Disposable Lab

- Timestamp (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Kubernetes context: $(kubectl config current-context)
- Namespace: $LAB_NS
- Storage: emptyDir only (deleted with namespace)
- Live NordicShop namespace modified: no

## Acceptance results
EOF

log ""
log "Creating isolated disposable PostgreSQL lab..."
kubectl apply -f "$SCRIPT_DIR/postgres-lab.yaml" >/dev/null
kubectl wait --for=condition=Ready "pod/$LAB_POD" -n "$LAB_NS" --timeout=120s >/dev/null

PSQL=(kubectl exec -i -n "$LAB_NS" "$LAB_POD" -- psql -X -q -v ON_ERROR_STOP=1 -U postgres -d nordicshop_rls_lab)

"${PSQL[@]}" < "$SCRIPT_DIR/sql/01-schema.sql" >/dev/null
"${PSQL[@]}" < "$SCRIPT_DIR/sql/02-seed.sql" >/dev/null
"${PSQL[@]}" < "$SCRIPT_DIR/sql/03-security.sql" >/dev/null

query() {
  local sql="$1"
  kubectl exec -i -n "$LAB_NS" "$LAB_POD" -- \
    psql -X -Atq -v ON_ERROR_STOP=1 -U postgres -d nordicshop_rls_lab -c "$sql" | tail -n 1 | tr -d '\r'
}

as_app() {
  local mode="$1"
  local tenant="$2"
  local sql="$3"
  local order_id="${4:-}"
  local prefix="SET ROLE nordicshop_app; SET app.access_mode = '$mode'; SET app.tenant_id = '$tenant'; SET app.order_id = '$order_id';"
  query "$prefix $sql"
}

flags="$(query "SELECT rolsuper::int || ',' || rolbypassrls::int FROM pg_roles WHERE rolname='nordicshop_app';")"
[[ "$flags" == "0,0" ]] && pass "runtime role is NOSUPERUSER and NOBYPASSRLS" || fail "runtime role flags expected 0,0; got $flags"

rls="$(query "SELECT count(*) FROM pg_class WHERE relname IN ('products','order_lines') AND relrowsecurity AND relforcerowsecurity;")"
[[ "$rls" == "2" ]] && pass "RLS is ENABLED and FORCED on products and order_lines" || fail "expected 2 protected tables; got $rls"

none_products="$(as_app "none" "" "SELECT count(*) FROM products;")"
[[ "$none_products" == "0" ]] && pass "missing access context sees zero products" || fail "missing context saw $none_products products"

customer_products="$(as_app "customer" "" "SELECT count(*) FROM products;")"
[[ "$customer_products" == "4" ]] && pass "customer can browse products across both vendors" || fail "customer expected 4 products; got $customer_products"

cust_update_a="$(as_app "customer" "" "WITH x AS (UPDATE products SET stock=stock-1 WHERE id=1 RETURNING id) SELECT count(*) FROM x;")"
cust_update_b="$(as_app "customer" "" "WITH x AS (UPDATE products SET stock=stock-1 WHERE id=3 RETURNING id) SELECT count(*) FROM x;")"
[[ "$cust_update_a" == "1" && "$cust_update_b" == "1" ]] && pass "customer checkout can decrement stock across two vendors" || fail "customer stock updates returned A=$cust_update_a B=$cust_update_b"

# Column grant test: customer/runtime role must not rename products.
set +e
rename_output="$(kubectl exec -i -n "$LAB_NS" "$LAB_POD" -- psql -X -Atq -U postgres -d nordicshop_rls_lab -c "SET ROLE nordicshop_app; SET app.access_mode='customer'; UPDATE products SET name='BAD' WHERE id=1;" 2>&1)"
rename_rc=$?
set -e
if [[ $rename_rc -ne 0 && "$rename_output" == *"permission denied"* ]]; then
  pass "runtime role cannot modify protected product columns such as name"
else
  fail "runtime role unexpectedly allowed product-name update"
fi

order_id="$(as_app "customer" "" "INSERT INTO orders(customer_name,customer_email) VALUES ('Lab Customer','lab@example.com') RETURNING id;")"
if [[ "$order_id" =~ ^[0-9]+$ ]]; then
  pass "customer can create an order"
else
  fail "customer order creation did not return an order id: $order_id"
  order_id="101"
fi

insert_a="$(as_app "customer" "" "INSERT INTO order_lines(order_id,tenant_id,product_id,product_name,quantity,unit_price) VALUES ($order_id,1,1,'Harbour Wool Throw',1,649.00) RETURNING id;" "$order_id")"
insert_b="$(as_app "customer" "" "INSERT INTO order_lines(order_id,tenant_id,product_id,product_name,quantity,unit_price) VALUES ($order_id,2,3,'Birch Table Lamp',1,799.00) RETURNING id;" "$order_id")"
if [[ "$insert_a" =~ ^[0-9]+$ && "$insert_b" =~ ^[0-9]+$ ]]; then
  pass "customer checkout can create order lines for multiple vendors"
else
  fail "customer cross-vendor order-line inserts failed: A=$insert_a B=$insert_b"
fi

customer_lines="$(as_app "customer" "" "SELECT count(*) FROM order_lines;" "$order_id")"
[[ "$customer_lines" == "2" ]] && pass "customer can read only the two lines for the current checkout order" || fail "customer expected 2 current-order lines; got $customer_lines"

customer_old_lines="$(as_app "customer" "" "SELECT count(*) FROM order_lines WHERE order_id=100;" "$order_id")"
[[ "$customer_old_lines" == "0" ]] && pass "customer cannot read another customer's existing order lines" || fail "customer unexpectedly read $customer_old_lines existing order lines"

vendor_a_products="$(as_app "vendor" "1" "SELECT string_agg(id::text,',' ORDER BY id) FROM products;")"
vendor_b_products="$(as_app "vendor" "2" "SELECT string_agg(id::text,',' ORDER BY id) FROM products;")"
[[ "$vendor_a_products" == "1,2" ]] && pass "Vendor A sees only tenant 1 products" || fail "Vendor A product IDs: $vendor_a_products"
[[ "$vendor_b_products" == "3,4" ]] && pass "Vendor B sees only tenant 2 products" || fail "Vendor B product IDs: $vendor_b_products"

vendor_a_own="$(as_app "vendor" "1" "WITH x AS (UPDATE products SET stock=stock+1 WHERE id=1 RETURNING id) SELECT count(*) FROM x;")"
vendor_a_cross="$(as_app "vendor" "1" "WITH x AS (UPDATE products SET stock=stock+1 WHERE id=3 RETURNING id) SELECT count(*) FROM x;")"
[[ "$vendor_a_own" == "1" ]] && pass "Vendor A can update own inventory" || fail "Vendor A own update count: $vendor_a_own"
[[ "$vendor_a_cross" == "0" ]] && pass "Vendor A cannot update Vendor B inventory" || fail "Vendor A cross-tenant update count: $vendor_a_cross"

vendor_a_lines="$(as_app "vendor" "1" "SELECT count(*) FROM order_lines;")"
vendor_b_lines="$(as_app "vendor" "2" "SELECT count(*) FROM order_lines;")"
[[ "$vendor_a_lines" == "2" ]] && pass "Vendor A sees only its own two order lines" || fail "Vendor A expected 2 order lines; got $vendor_a_lines"
[[ "$vendor_b_lines" == "2" ]] && pass "Vendor B sees only its own two order lines" || fail "Vendor B expected 2 order lines; got $vendor_b_lines"

admin_products="$(as_app "admin" "" "SELECT count(*) FROM products;")"
admin_lines="$(as_app "admin" "" "SELECT count(*) FROM order_lines;")"
[[ "$admin_products" == "4" ]] && pass "admin sees all products" || fail "admin expected 4 products; got $admin_products"
[[ "$admin_lines" == "4" ]] && pass "admin sees all order lines" || fail "admin expected 4 order lines; got $admin_lines"

log ""
log "## Summary"
log ""
log "- PASS: $PASS"
log "- FAIL: $FAIL"
log "- Result: $([[ $FAIL -eq 0 ]] && echo PASS || echo FAIL)"
log ""
log "The namespace is deleted automatically at the end of the run."

printf '\nRLS lab complete: PASS=%d FAIL=%d\nEvidence: %s\n' "$PASS" "$FAIL" "$REPORT"

if [[ $FAIL -ne 0 ]]; then
  exit 1
fi
