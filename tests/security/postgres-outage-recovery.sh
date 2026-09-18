#!/usr/bin/env bash

set -u

NS="nordicshop"
ARGO_NS="argocd"
ARGO_APP="nordicshop"

POSTGRES_STS="postgres"
POSTGRES_POD="postgres-0"
API_DEPLOYMENT="nordicshop-api"

EVIDENCE_DIR="docs/evidence/security-recovery"
STAMP="$(date -u +"%Y%m%d-%H%M%S")"
STARTED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
REPORT="${EVIDENCE_DIR}/postgres-outage-recovery-${STAMP}.md"

PORT="18080"

PASS=0
FAIL=0
CLEANUP_DONE=0

mkdir -p "$EVIDENCE_DIR"

pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}

db_query() {
    kubectl exec -n "$NS" "$POSTGRES_POD" -- \
        psql -X -Atq \
        -U nordicshop \
        -d nordicshop \
        -F '|' \
        -c "$1"
}

api_ready_code() {
    local pf_pid
    local code

    kubectl port-forward \
        -n "$NS" \
        deployment/"$API_DEPLOYMENT" \
        "${PORT}:8000" \
        >/tmp/nordicshop-postgres-recovery-portforward.log 2>&1 &

    pf_pid=$!

    sleep 2

    code="$(curl -s \
        --max-time 4 \
        -o /dev/null \
        -w '%{http_code}' \
        "http://127.0.0.1:${PORT}/api/ready" 2>/dev/null || true)"

    kill "$pf_pid" >/dev/null 2>&1 || true
    wait "$pf_pid" >/dev/null 2>&1 || true

    echo "${code:-000}"
}

restore_environment() {
    if [[ "$CLEANUP_DONE" -eq 1 ]]; then
        return
    fi

    CLEANUP_DONE=1

    echo
    echo "Safety cleanup: restoring PostgreSQL and Argo self-heal..."

    kubectl scale statefulset "$POSTGRES_STS" \
        -n "$NS" \
        --replicas="$ORIGINAL_REPLICAS" \
        >/dev/null 2>&1 || true

    kubectl patch application "$ARGO_APP" \
        -n "$ARGO_NS" \
        --type merge \
        -p "{\"spec\":{\"syncPolicy\":{\"automated\":{\"enabled\":true,\"prune\":true,\"selfHeal\":${ORIGINAL_SELF_HEAL}}}}}" \
        >/dev/null 2>&1 || true
}

trap restore_environment EXIT INT TERM

echo
echo "==============================================="
echo " NordicShop - PostgreSQL Outage Recovery Test"
echo "==============================================="
echo

#
# 1. Safety gates
#

CURRENT_CONTEXT="$(kubectl config current-context)"

echo "Kubernetes context: $CURRENT_CONTEXT"

ARGO_TARGET="$(kubectl get application "$ARGO_APP" \
    -n "$ARGO_NS" \
    -o jsonpath='{.spec.source.targetRevision}')"

if [[ "$ARGO_TARGET" != "main" ]]; then
    fail "Argo is not tracking main"
    exit 1
fi
pass "Argo is tracking main"

ARGO_STATE="$(kubectl get application "$ARGO_APP" \
    -n "$ARGO_NS" \
    -o jsonpath='{.status.sync.status}/{.status.health.status}')"

if [[ "$ARGO_STATE" != "Synced/Healthy" ]]; then
    fail "Argo baseline is $ARGO_STATE instead of Synced/Healthy"
    exit 1
fi
pass "Argo baseline is Synced/Healthy"

ORIGINAL_REPLICAS="$(kubectl get statefulset "$POSTGRES_STS" \
    -n "$NS" \
    -o jsonpath='{.spec.replicas}')"

if [[ -z "$ORIGINAL_REPLICAS" || "$ORIGINAL_REPLICAS" == "0" ]]; then
    fail "PostgreSQL is not currently running"
    exit 1
fi
pass "PostgreSQL baseline replicas = $ORIGINAL_REPLICAS"

ORIGINAL_SELF_HEAL="$(kubectl get application "$ARGO_APP" \
    -n "$ARGO_NS" \
    -o jsonpath='{.spec.syncPolicy.automated.selfHeal}')"

if [[ "$ORIGINAL_SELF_HEAL" != "true" && "$ORIGINAL_SELF_HEAL" != "false" ]]; then
    fail "Could not determine Argo selfHeal state"
    exit 1
fi

#
# 2. Capture PVC and persistent data before outage
#

PVC_NAME="$(kubectl get pod "$POSTGRES_POD" \
    -n "$NS" \
    -o jsonpath='{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}' \
    | grep -v '^$' \
    | head -1)"

if [[ -z "$PVC_NAME" ]]; then
    fail "Could not discover PostgreSQL PVC"
    exit 1
fi

PVC_STATUS_BEFORE="$(kubectl get pvc "$PVC_NAME" \
    -n "$NS" \
    -o jsonpath='{.status.phase}')"

if [[ "$PVC_STATUS_BEFORE" != "Bound" ]]; then
    fail "PVC baseline status is $PVC_STATUS_BEFORE"
    exit 1
fi

pass "PostgreSQL PVC $PVC_NAME is Bound"

ORDER_COUNT_BEFORE="$(db_query "SELECT count(*) FROM orders;")"
MAX_ORDER_BEFORE="$(db_query "SELECT COALESCE(max(id),0) FROM orders;")"

LATEST_ORDER_BEFORE="$(db_query "
SELECT
    id,
    customer_email,
    status
FROM orders
ORDER BY id DESC
LIMIT 1;
")"

echo
echo "Baseline persistent data:"
echo "Orders:       $ORDER_COUNT_BEFORE"
echo "Max order ID: $MAX_ORDER_BEFORE"
echo "Latest order: $LATEST_ORDER_BEFORE"

BASELINE_READY="$(api_ready_code)"

if [[ "$BASELINE_READY" != "200" ]]; then
    fail "API readiness baseline returned $BASELINE_READY"
    exit 1
fi

pass "API readiness baseline returned 200"

#
# 3. Disable Argo self-heal temporarily
#

echo
echo "Temporarily disabling Argo self-heal..."

kubectl patch application "$ARGO_APP" \
    -n "$ARGO_NS" \
    --type merge \
    -p '{"spec":{"syncPolicy":{"automated":{"enabled":true,"prune":true,"selfHeal":false}}}}' \
    >/dev/null

pass "Argo self-heal temporarily disabled"

#
# 4. Create controlled PostgreSQL outage
#

echo
echo "Scaling PostgreSQL StatefulSet to 0..."

OUTAGE_STARTED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

kubectl scale statefulset "$POSTGRES_STS" \
    -n "$NS" \
    --replicas=0

kubectl wait \
    --for=delete \
    pod/"$POSTGRES_POD" \
    -n "$NS" \
    --timeout=120s \
    >/dev/null

pass "PostgreSQL Pod stopped"

PVC_STATUS_DURING="$(kubectl get pvc "$PVC_NAME" \
    -n "$NS" \
    -o jsonpath='{.status.phase}')"

if [[ "$PVC_STATUS_DURING" == "Bound" ]]; then
    pass "PVC remained Bound during PostgreSQL outage"
else
    fail "PVC changed state during outage: $PVC_STATUS_DURING"
fi

#
# 5. Verify API impact
#

echo
echo "Waiting for API readiness impact..."

OUTAGE_API_CODE="200"

for _ in {1..15}; do
    OUTAGE_API_CODE="$(api_ready_code)"

    echo "API readiness: $OUTAGE_API_CODE"

    if [[ "$OUTAGE_API_CODE" != "200" ]]; then
        break
    fi

    sleep 3
done

if [[ "$OUTAGE_API_CODE" != "200" ]]; then
    pass "API readiness was impacted by PostgreSQL outage ($OUTAGE_API_CODE)"
else
    fail "API readiness remained 200 while PostgreSQL was unavailable"
fi

#
# 6. Restore PostgreSQL
#

echo
echo "Restoring PostgreSQL..."

RESTORE_STARTED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

kubectl scale statefulset "$POSTGRES_STS" \
    -n "$NS" \
    --replicas="$ORIGINAL_REPLICAS"

kubectl wait \
    --for=condition=Ready \
    pod/"$POSTGRES_POD" \
    -n "$NS" \
    --timeout=180s \
    >/dev/null

pass "PostgreSQL Pod returned Ready"

PVC_STATUS_AFTER="$(kubectl get pvc "$PVC_NAME" \
    -n "$NS" \
    -o jsonpath='{.status.phase}')"

if [[ "$PVC_STATUS_AFTER" == "Bound" ]]; then
    pass "PVC remained Bound after recovery"
else
    fail "PVC status after recovery is $PVC_STATUS_AFTER"
fi

#
# 7. Verify persistent database data
#

ORDER_COUNT_AFTER="$(db_query "SELECT count(*) FROM orders;")"
MAX_ORDER_AFTER="$(db_query "SELECT COALESCE(max(id),0) FROM orders;")"

LATEST_ORDER_AFTER="$(db_query "
SELECT
    id,
    customer_email,
    status
FROM orders
ORDER BY id DESC
LIMIT 1;
")"

if [[ "$ORDER_COUNT_AFTER" == "$ORDER_COUNT_BEFORE" ]]; then
    pass "Order count persisted ($ORDER_COUNT_AFTER)"
else
    fail "Order count changed: before=$ORDER_COUNT_BEFORE after=$ORDER_COUNT_AFTER"
fi

if [[ "$MAX_ORDER_AFTER" == "$MAX_ORDER_BEFORE" ]]; then
    pass "Maximum order ID persisted ($MAX_ORDER_AFTER)"
else
    fail "Maximum order ID changed: before=$MAX_ORDER_BEFORE after=$MAX_ORDER_AFTER"
fi

if [[ "$LATEST_ORDER_AFTER" == "$LATEST_ORDER_BEFORE" ]]; then
    pass "Latest order data persisted"
else
    fail "Latest order changed after PostgreSQL recovery"
fi

#
# 8. Verify API recovery
#

echo
echo "Waiting for API readiness recovery..."

RECOVERY_API_CODE="000"

for _ in {1..20}; do
    RECOVERY_API_CODE="$(api_ready_code)"

    echo "API readiness: $RECOVERY_API_CODE"

    if [[ "$RECOVERY_API_CODE" == "200" ]]; then
        break
    fi

    sleep 3
done

if [[ "$RECOVERY_API_CODE" == "200" ]]; then
    pass "API readiness recovered to 200"
else
    fail "API readiness did not recover; final code=$RECOVERY_API_CODE"
fi

#
# 9. Restore normal Argo behavior
#

echo
echo "Restoring Argo self-heal..."

kubectl patch application "$ARGO_APP" \
    -n "$ARGO_NS" \
    --type merge \
    -p "{\"spec\":{\"syncPolicy\":{\"automated\":{\"enabled\":true,\"prune\":true,\"selfHeal\":${ORIGINAL_SELF_HEAL}}}}}" \
    >/dev/null

kubectl annotate application "$ARGO_APP" \
    -n "$ARGO_NS" \
    argocd.argoproj.io/refresh=hard \
    --overwrite \
    >/dev/null

sleep 5

FINAL_ARGO="$(kubectl get application "$ARGO_APP" \
    -n "$ARGO_NS" \
    -o jsonpath='{.status.sync.status}/{.status.health.status}')"

if [[ "$FINAL_ARGO" == "Synced/Healthy" ]]; then
    pass "Argo returned to Synced/Healthy"
else
    fail "Final Argo state is $FINAL_ARGO"
fi

CLEANUP_DONE=1

COMPLETED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

#
# 10. Evidence
#

if [[ "$FAIL" -eq 0 ]]; then
    RESULT="PASS"
else
    RESULT="FAIL"
fi

cat > "$REPORT" <<EOFREPORT
# NordicShop - PostgreSQL Outage Recovery Evidence

**Started:** $STARTED  
**Completed:** $COMPLETED  
**Environment:** AKS  
**Kubernetes context:** $CURRENT_CONTEXT  
**Result:** **$RESULT**

## Baseline

- Argo: $ARGO_STATE
- PostgreSQL replicas: $ORIGINAL_REPLICAS
- PVC: $PVC_NAME
- PVC status: $PVC_STATUS_BEFORE
- API readiness: $BASELINE_READY
- Order count: $ORDER_COUNT_BEFORE
- Maximum order ID: $MAX_ORDER_BEFORE
- Latest order: $LATEST_ORDER_BEFORE

## Controlled outage

- PostgreSQL scaled to: 0
- Outage started: $OUTAGE_STARTED
- PVC during outage: $PVC_STATUS_DURING
- API readiness during outage: $OUTAGE_API_CODE
- PVC deleted: no

## Recovery

- Restore started: $RESTORE_STARTED
- PostgreSQL replicas restored to: $ORIGINAL_REPLICAS
- PVC after recovery: $PVC_STATUS_AFTER
- API readiness after recovery: $RECOVERY_API_CODE
- Order count after recovery: $ORDER_COUNT_AFTER
- Maximum order ID after recovery: $MAX_ORDER_AFTER
- Latest order after recovery: $LATEST_ORDER_AFTER
- Final Argo state: $FINAL_ARGO

## Acceptance

- Passed checks: $PASS
- Failed checks: $FAIL

**Result: $RESULT**

The PostgreSQL StatefulSet was scaled down without deleting or modifying its PVC.
The same persistent data was verified after PostgreSQL and the API recovered.
EOFREPORT

echo
echo "==============================================="
echo " PostgreSQL Recovery Result"
echo "==============================================="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo "RESULT: $RESULT"
echo
echo "Evidence:"
echo "$REPORT"

if [[ "$FAIL" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
