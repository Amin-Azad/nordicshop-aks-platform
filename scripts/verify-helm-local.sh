#!/usr/bin/env bash
set -Eeuo pipefail

# NordicShop local Helm acceptance verification
#
# Assumptions:
# - A Helm release named "nordicshop" is already installed.
# - The application namespace is "nordicshop".
# - ingress-nginx is installed in namespace "ingress-nginx".
# - helm/nordicshop/values-local-secret.yaml exists locally and is NOT tracked by Git.
#
# The script saves:
#   docs/evidence/helm-local-verification-<timestamp>.log
#   docs/evidence/helm-local-verification-<timestamp>.md

RELEASE="${RELEASE:-nordicshop}"
APP_NS="${APP_NS:-nordicshop}"
CHART="${CHART:-helm/nordicshop}"
SECRET_VALUES="${SECRET_VALUES:-helm/nordicshop/values-local-secret.yaml}"
INGRESS_NS="${INGRESS_NS:-ingress-nginx}"
INGRESS_SERVICE="${INGRESS_SERVICE:-ingress-nginx-controller}"
LOCAL_PORT="${LOCAL_PORT:-18081}"
EVIDENCE_DIR="${EVIDENCE_DIR:-docs/evidence}"

TS="$(date '+%Y%m%d-%H%M%S')"
LOG_FILE="${EVIDENCE_DIR}/helm-local-verification-${TS}.log"
MD_FILE="${EVIDENCE_DIR}/helm-local-verification-${TS}.md"
TMP_DIR="$(mktemp -d)"
PF_PID=""

PASS_COUNT=0
FAIL_COUNT=0

mkdir -p "$EVIDENCE_DIR"

cleanup() {
  if [[ -n "${PF_PID}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

exec > >(tee -a "$LOG_FILE") 2>&1

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[PASS] %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[FAIL] %s\n' "$1"
}

section() {
  printf '\n===== %s =====\n' "$1"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[FATAL] Required command not found: %s\n' "$1"
    exit 1
  fi
}

json_check() {
  local file="$1"
  local expr="$2"
  local message="$3"

  if python3 - "$file" "$expr" <<'PY'
import json, sys
path, expr = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    obj = json.load(f)
safe_builtins = {
    "len": len,
    "isinstance": isinstance,
    "list": list,
    "dict": dict,
    "all": all,
    "any": any,
    "int": int,
    "str": str,
    "float": float,
}
ok = bool(eval(expr, {"__builtins__": safe_builtins}, {"obj": obj}))
raise SystemExit(0 if ok else 1)
PY
  then
    pass "$message"
  else
    fail "$message"
  fi
}

section "Prerequisites"
for cmd in helm kubectl curl python3 git; do
  require_cmd "$cmd"
done
pass "Required commands are available"

if [[ ! -f "$SECRET_VALUES" ]]; then
  printf '[FATAL] Missing local secret values file: %s\n' "$SECRET_VALUES"
  exit 1
fi

section "Helm release and ownership"
release_ns="$(helm list -A -o json | python3 -c '
import json, sys
name = sys.argv[1]
rows = json.load(sys.stdin)
matches = [r for r in rows if r.get("name") == name]
print(matches[0].get("namespace", "") if matches else "")
' "$RELEASE")"

if [[ "$release_ns" == "$APP_NS" ]]; then
  pass "Helm release '${RELEASE}' is stored in namespace '${APP_NS}'"
else
  fail "Helm release namespace is '${release_ns:-<missing>}' (expected '${APP_NS}')"
fi

owner_ns="$(kubectl get deployment nordicshop-api -n "$APP_NS" \
  -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}' 2>/dev/null || true)"

if [[ "$owner_ns" == "$APP_NS" ]]; then
  pass "Nordic API Helm ownership points to '${APP_NS}'"
else
  fail "Nordic API Helm ownership namespace is '${owner_ns:-<missing>}'"
fi

section "Chart validation"
if helm lint "$CHART" -f "$SECRET_VALUES"; then
  pass "helm lint passed"
else
  fail "helm lint failed"
fi

if helm template "$RELEASE" "$CHART" \
  --namespace "$APP_NS" \
  -f "$SECRET_VALUES" > "$TMP_DIR/rendered.yaml"; then
  pass "helm template rendered successfully"
else
  fail "helm template failed"
fi

if grep -q '^kind: Namespace$' "$TMP_DIR/rendered.yaml"; then
  fail "Rendered chart unexpectedly contains a Namespace object"
else
  pass "Chart does not manage the Namespace object"
fi

if grep -Rqs '\.Values\.namespace' "$CHART/templates"; then
  fail "Old .Values.namespace reference still exists"
else
  pass "No .Values.namespace references remain"
fi

if kubectl apply --dry-run=client -f "$TMP_DIR/rendered.yaml" >/dev/null; then
  pass "Kubernetes client dry-run accepted rendered objects"
else
  fail "Kubernetes client dry-run rejected rendered objects"
fi

section "Workload readiness"
declare -a deployments=(
  "nordicshop-api"
  "nordicshop-customer-web"
  "nordicshop-vendor-portal"
  "nordicshop-admin-portal"
  "redis"
)

for d in "${deployments[@]}"; do
  if kubectl rollout status "deployment/${d}" -n "$APP_NS" --timeout=180s; then
    pass "Deployment ${d} is ready"
  else
    fail "Deployment ${d} is not ready"
  fi
done

if kubectl rollout status statefulset/postgres -n "$APP_NS" --timeout=180s; then
  pass "PostgreSQL StatefulSet is ready"
else
  fail "PostgreSQL StatefulSet is not ready"
fi

section "ConfigMap, Secret and PVC references"
db_ref="$(kubectl get deployment nordicshop-api -n "$APP_NS" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NORDICSHOP_DATABASE_URL")].valueFrom.secretKeyRef.name}')"
db_key="$(kubectl get deployment nordicshop-api -n "$APP_NS" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NORDICSHOP_DATABASE_URL")].valueFrom.secretKeyRef.key}')"
redis_ref="$(kubectl get deployment nordicshop-api -n "$APP_NS" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NORDICSHOP_REDIS_URL")].valueFrom.configMapKeyRef.name}')"
redis_key="$(kubectl get deployment nordicshop-api -n "$APP_NS" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="NORDICSHOP_REDIS_URL")].valueFrom.configMapKeyRef.key}')"

[[ "$db_ref" == "nordicshop-secret" && "$db_key" == "NORDICSHOP_DATABASE_URL" ]] \
  && pass "API database URL comes from nordicshop-secret/NORDICSHOP_DATABASE_URL" \
  || fail "API database Secret reference is incorrect"

[[ "$redis_ref" == "nordicshop-config" && "$redis_key" == "NORDICSHOP_REDIS_URL" ]] \
  && pass "API Redis URL comes from nordicshop-config/NORDICSHOP_REDIS_URL" \
  || fail "API Redis ConfigMap reference is incorrect"

kubectl get secret nordicshop-secret -n "$APP_NS" >/dev/null \
  && pass "Runtime Secret exists" \
  || fail "Runtime Secret is missing"

kubectl get configmap nordicshop-config -n "$APP_NS" >/dev/null \
  && pass "Runtime ConfigMap exists" \
  || fail "Runtime ConfigMap is missing"

pvc_phase="$(kubectl get pvc postgres-pvc -n "$APP_NS" -o jsonpath='{.status.phase}')"
if [[ "$pvc_phase" == "Bound" ]]; then
  pass "PostgreSQL PVC is Bound"
else
  fail "PostgreSQL PVC is '${pvc_phase}'"
fi

pv_before="$(kubectl get pvc postgres-pvc -n "$APP_NS" -o jsonpath='{.spec.volumeName}')"
if [[ -n "$pv_before" ]]; then
  pass "PostgreSQL PVC is bound to PV ${pv_before}"
else
  fail "PostgreSQL PVC has no PV"
fi

section "Ingress routes"
if ! kubectl get svc "$INGRESS_SERVICE" -n "$INGRESS_NS" >/dev/null; then
  printf '[FATAL] Ingress controller Service not found\n'
  exit 1
fi
pass "Ingress controller Service exists"

kubectl port-forward -n "$INGRESS_NS" \
  "service/${INGRESS_SERVICE}" "${LOCAL_PORT}:80" \
  > "$TMP_DIR/port-forward.log" 2>&1 &
PF_PID=$!

for _ in $(seq 1 30); do
  if curl -sS --max-time 2 "http://127.0.0.1:${LOCAL_PORT}/" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! kill -0 "$PF_PID" 2>/dev/null; then
  cat "$TMP_DIR/port-forward.log"
  printf '[FATAL] Ingress port-forward failed\n'
  exit 1
fi

BASE="http://127.0.0.1:${LOCAL_PORT}"

for path in "/" "/vendor/" "/admin/"; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "${BASE}${path}")"
  if [[ "$code" == "200" ]]; then
    pass "Ingress route ${path} returned HTTP 200"
  else
    fail "Ingress route ${path} returned HTTP ${code}"
  fi
done

section "API health and readiness"
curl -sS "${BASE}/api/health" > "$TMP_DIR/health.json"
json_check "$TMP_DIR/health.json" \
  'obj.get("status") == "ok" and obj.get("service") == "nordic-api"' \
  "API health endpoint passed"

curl -sS "${BASE}/api/ready" > "$TMP_DIR/ready.json"
json_check "$TMP_DIR/ready.json" \
  'obj.get("status") == "ready"' \
  "API readiness endpoint passed"

section "Customer catalog, Redis cart and checkout"
curl -sS "${BASE}/api/products" > "$TMP_DIR/products.json"
json_check "$TMP_DIR/products.json" \
  'isinstance(obj, list) and len(obj) == 8' \
  "Customer catalog returned 8 seeded products"

cart_id="helm-verify-${TS}"
customer_name="Helm Verification ${TS}"
customer_email="helm-verify-${TS}@example.com"

curl -sS -X POST "${BASE}/api/cart/items" \
  -H 'Content-Type: application/json' \
  -d "{\"cart_id\":\"${cart_id}\",\"product_id\":1,\"quantity\":1}" \
  > "$TMP_DIR/cart-add.json"

json_check "$TMP_DIR/cart-add.json" \
  'obj.get("status") == "added"' \
  "Item added to Redis-backed cart"

curl -sS "${BASE}/api/cart/${cart_id}" > "$TMP_DIR/cart.json"
json_check "$TMP_DIR/cart.json" \
  'len(obj.get("items", [])) == 1 and obj["items"][0].get("id") == 1 and obj["items"][0].get("quantity") == 1' \
  "Cart read returned expected item"

curl -sS -X POST "${BASE}/api/orders" \
  -H 'Content-Type: application/json' \
  -d "{\"cart_id\":\"${cart_id}\",\"customer_name\":\"${customer_name}\",\"customer_email\":\"${customer_email}\"}" \
  > "$TMP_DIR/order.json"

json_check "$TMP_DIR/order.json" \
  'obj.get("status") == "placed" and obj.get("order_id") is not None' \
  "Checkout created a PostgreSQL order"

order_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["order_id"])' < "$TMP_DIR/order.json")"

curl -sS "${BASE}/api/cart/${cart_id}" > "$TMP_DIR/cart-after.json"
json_check "$TMP_DIR/cart-after.json" \
  'obj.get("items") == [] and obj.get("total") == 0' \
  "Cart cleared after checkout"

section "Tenant isolation and authorization"
curl -sS "${BASE}/api/vendor/products" -H 'X-Demo-User: 1' > "$TMP_DIR/vendor-a.json"
json_check "$TMP_DIR/vendor-a.json" \
  'len(obj) > 0 and all(p.get("tenant_id") == 1 for p in obj)' \
  "Vendor A sees only tenant 1 products"

curl -sS "${BASE}/api/vendor/products" -H 'X-Demo-User: 2' > "$TMP_DIR/vendor-b.json"
json_check "$TMP_DIR/vendor-b.json" \
  'len(obj) > 0 and all(p.get("tenant_id") == 2 for p in obj)' \
  "Vendor B sees only tenant 2 products"

cross_code="$(curl -sS -o "$TMP_DIR/cross.json" -w '%{http_code}' \
  -X PATCH "${BASE}/api/vendor/products/5/stock" \
  -H 'X-Demo-User: 1' \
  -H 'Content-Type: application/json' \
  -d '{"stock":999}')"

if [[ "$cross_code" == "404" ]]; then
  pass "Vendor A cannot modify Vendor B product (HTTP 404)"
else
  fail "Cross-tenant mutation returned HTTP ${cross_code}; expected 404"
fi

orig_stock="$(python3 - "$TMP_DIR/vendor-a.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    rows = json.load(f)
print(next(p["stock"] for p in rows if p["id"] == 1))
PY
)"
temp_stock=$((orig_stock + 1))

own_code="$(curl -sS -o "$TMP_DIR/own-update.json" -w '%{http_code}' \
  -X PATCH "${BASE}/api/vendor/products/1/stock" \
  -H 'X-Demo-User: 1' \
  -H 'Content-Type: application/json' \
  -d "{\"stock\":${temp_stock}}")"

if [[ "$own_code" == "200" ]]; then
  pass "Vendor A can modify its own product"
else
  fail "Vendor A own-product update returned HTTP ${own_code}"
fi

# Restore stock so the verification does not leave a test-only inventory change.
curl -sS -X PATCH "${BASE}/api/vendor/products/1/stock" \
  -H 'X-Demo-User: 1' \
  -H 'Content-Type: application/json' \
  -d "{\"stock\":${orig_stock}}" >/dev/null
pass "Vendor A test stock was restored"

curl -sS "${BASE}/api/admin/summary" -H 'X-Demo-User: 3' > "$TMP_DIR/admin-summary.json"
json_check "$TMP_DIR/admin-summary.json" \
  'obj.get("vendors") == 2 and obj.get("products") == 8' \
  "Admin summary has marketplace-wide visibility"

curl -sS "${BASE}/api/admin/orders" -H 'X-Demo-User: 3' > "$TMP_DIR/admin-orders.json"

if python3 - "$TMP_DIR/admin-orders.json" "$customer_name" <<'PY'
import json, sys
path, customer = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    orders = json.load(f)
raise SystemExit(0 if any(o.get("customer") == customer for o in orders) else 1)
PY
then
  pass "Admin can see the verification order"
else
  fail "Admin cannot see the verification order"
fi

vendor_admin_code="$(curl -sS -o "$TMP_DIR/vendor-admin.json" -w '%{http_code}' \
  "${BASE}/api/admin/summary" -H 'X-Demo-User: 1')"

if [[ "$vendor_admin_code" == "403" ]]; then
  pass "Vendor is denied from admin API (HTTP 403)"
else
  fail "Vendor admin-route access returned HTTP ${vendor_admin_code}; expected 403"
fi

section "API Pod self-healing"
api_pod_before="$(kubectl get pod -n "$APP_NS" -l app=nordicshop-api -o jsonpath='{.items[0].metadata.name}')"
api_uid_before="$(kubectl get pod "$api_pod_before" -n "$APP_NS" -o jsonpath='{.metadata.uid}')"

kubectl delete pod "$api_pod_before" -n "$APP_NS" --wait=false >/dev/null
pass "Deleted Nordic API Pod ${api_pod_before}"

api_uid_after=""
api_pod_after=""
for _ in $(seq 1 90); do
  api_pod_after="$(kubectl get pod -n "$APP_NS" -l app=nordicshop-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -n "$api_pod_after" ]]; then
    api_uid_after="$(kubectl get pod "$api_pod_after" -n "$APP_NS" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
    ready="$(kubectl get pod "$api_pod_after" -n "$APP_NS" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
    if [[ "$api_uid_after" != "$api_uid_before" && "$ready" == "true" ]]; then
      break
    fi
  fi
  sleep 2
done

if [[ -n "$api_uid_after" && "$api_uid_after" != "$api_uid_before" ]]; then
  pass "Kubernetes created a replacement Nordic API Pod"
else
  fail "Nordic API replacement Pod was not observed"
fi

curl -sS "${BASE}/api/ready" > "$TMP_DIR/ready-after-api-delete.json"
json_check "$TMP_DIR/ready-after-api-delete.json" \
  'obj.get("status") == "ready"' \
  "API returned ready after self-healing"

section "PostgreSQL Pod recovery and persistence"
pv_before_restart="$(kubectl get pvc postgres-pvc -n "$APP_NS" -o jsonpath='{.spec.volumeName}')"
pg_uid_before="$(kubectl get pod postgres-0 -n "$APP_NS" -o jsonpath='{.metadata.uid}')"

kubectl delete pod postgres-0 -n "$APP_NS" --wait=false >/dev/null
pass "Deleted PostgreSQL Pod postgres-0"

pg_uid_after=""
for _ in $(seq 1 120); do
  if kubectl get pod postgres-0 -n "$APP_NS" >/dev/null 2>&1; then
    pg_uid_after="$(kubectl get pod postgres-0 -n "$APP_NS" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
    ready="$(kubectl get pod postgres-0 -n "$APP_NS" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
    if [[ "$pg_uid_after" != "$pg_uid_before" && "$ready" == "true" ]]; then
      break
    fi
  fi
  sleep 2
done

if [[ -n "$pg_uid_after" && "$pg_uid_after" != "$pg_uid_before" ]]; then
  pass "PostgreSQL StatefulSet recreated postgres-0"
else
  fail "PostgreSQL replacement Pod was not observed"
fi

pv_after_restart="$(kubectl get pvc postgres-pvc -n "$APP_NS" -o jsonpath='{.spec.volumeName}')"

if [[ "$pv_before_restart" == "$pv_after_restart" && -n "$pv_after_restart" ]]; then
  pass "PostgreSQL reused the same PV: ${pv_after_restart}"
else
  fail "PostgreSQL PV changed after Pod recreation"
fi

# Wait for API readiness to recover after the database restart.
for _ in $(seq 1 60); do
  if curl -sS --max-time 2 "${BASE}/api/ready" > "$TMP_DIR/ready-after-pg.json" 2>/dev/null; then
    if python3 - "$TMP_DIR/ready-after-pg.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    obj=json.load(f)
raise SystemExit(0 if obj.get("status")=="ready" else 1)
PY
    then
      break
    fi
  fi
  sleep 2
done

json_check "$TMP_DIR/ready-after-pg.json" \
  'obj.get("status") == "ready"' \
  "API readiness recovered after PostgreSQL restart"

curl -sS "${BASE}/api/admin/orders" -H 'X-Demo-User: 3' > "$TMP_DIR/admin-orders-after-pg.json"

if python3 - "$TMP_DIR/admin-orders-after-pg.json" "$customer_name" "$order_id" <<'PY'
import json, sys
path, customer, order_id = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(path, encoding="utf-8") as f:
    orders = json.load(f)
raise SystemExit(
    0 if any(o.get("customer") == customer and o.get("id") == order_id for o in orders) else 1
)
PY
then
  pass "Verification order persisted after PostgreSQL Pod recreation"
else
  fail "Verification order was not found after PostgreSQL Pod recreation"
fi

section "Git secret-safety check"
if git ls-files --error-unmatch "$SECRET_VALUES" >/dev/null 2>&1; then
  fail "${SECRET_VALUES} is tracked by Git"
else
  pass "${SECRET_VALUES} is not tracked by Git"
fi

if git status --short -- "$SECRET_VALUES" | grep -q .; then
  printf '[INFO] Local secret values file is present but ignored/untracked as expected.\n'
fi

section "Final result"
printf 'Passed checks: %d\n' "$PASS_COUNT"
printf 'Failed checks: %d\n' "$FAIL_COUNT"

STATUS="PASSED"
if (( FAIL_COUNT > 0 )); then
  STATUS="FAILED"
fi

cat > "$MD_FILE" <<EOF
# NordicShop Helm Local Verification

- Date: $(date -Iseconds)
- Release: \`${RELEASE}\`
- Namespace: \`${APP_NS}\`
- Chart: \`${CHART}\`
- Result: **${STATUS}**
- Passed checks: **${PASS_COUNT}**
- Failed checks: **${FAIL_COUNT}**
- Raw log: \`$(basename "$LOG_FILE")\`

## Scope verified

- Helm release namespace and Helm ownership
- \`.Release.Namespace\` chart behavior
- Helm lint and render
- Kubernetes client dry-run
- Six workload readiness
- Secret and ConfigMap references
- PostgreSQL PVC/PV binding
- Customer, Vendor and Admin Ingress routes
- API health and readiness
- Customer catalog, Redis cart and checkout
- Vendor tenant isolation and cross-tenant denial
- Admin authorization
- Nordic API Pod self-healing
- PostgreSQL Pod recreation using the same PV
- Order persistence after PostgreSQL recovery
- Local secret values file not tracked by Git

## Notes

This verification intentionally creates one demonstration order and deletes/recreates the Nordic API and PostgreSQL Pods to prove reconciliation and persistence. It does not uninstall the Helm release or delete the PVC.
EOF

printf '\nEvidence saved:\n'
printf '  %s\n' "$LOG_FILE"
printf '  %s\n' "$MD_FILE"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi

printf '\nNordicShop Helm verification: PASSED\n'
