#!/usr/bin/env bash
set -Eeuo pipefail

# NordicShop AKS PostgreSQL Persistence Test
#
# Purpose:
#   - Record the current PostgreSQL Pod, UID, PVC name and PVC UID
#   - Delete ONLY the PostgreSQL Pod (never the PVC)
#   - Wait for the StatefulSet to recreate a Ready PostgreSQL Pod
#   - Verify the replacement Pod has a different UID
#   - Verify the exact same PVC is still Bound and reattached
#   - Confirm a known order and its order_lines still exist in PostgreSQL
#   - Optionally save a timestamped evidence log
#
# Basic run:
#   ORDER_ID=1 ./tests/aks/postgres-persistence.sh
#
# Save evidence:
#   ORDER_ID=1 SAVE_EVIDENCE=1 ./tests/aks/postgres-persistence.sh
#
# Optional overrides:
#   NAMESPACE=nordicshop
#   STATEFULSET=postgres
#   ORDER_ID=1
#   EXPECTED_LINE_COUNT=2
#   TIMEOUT=240s

NAMESPACE="${NAMESPACE:-nordicshop}"
STATEFULSET="${STATEFULSET:-postgres}"
ORDER_ID="${ORDER_ID:-1}"
EXPECTED_LINE_COUNT="${EXPECTED_LINE_COUNT:-2}"
TIMEOUT="${TIMEOUT:-240s}"
SAVE_EVIDENCE="${SAVE_EVIDENCE:-0}"
EVIDENCE_FILE="${EVIDENCE_FILE:-}"

PASS_COUNT=0
FAIL_COUNT=0

for cmd in kubectl jq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    printf 'ERROR: required command not found: %s\n' "$cmd" >&2
    exit 2
  }
done

if [[ "$SAVE_EVIDENCE" == "1" && -z "$EVIDENCE_FILE" ]]; then
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  EVIDENCE_FILE="docs/evidence/aks/postgres-persistence-${timestamp}.log"
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

printf 'NordicShop AKS PostgreSQL Persistence Test\n'
printf 'Namespace:      %s\n' "$NAMESPACE"
printf 'StatefulSet:    %s\n' "$STATEFULSET"
printf 'Order ID:       %s\n' "$ORDER_ID"
printf 'Expected lines: %s\n' "$EXPECTED_LINE_COUNT"
printf 'Timeout:        %s\n' "$TIMEOUT"
printf '%s\n' '--------------------------------------------------'

# 1. Confirm StatefulSet exists.
kubectl get statefulset "$STATEFULSET" -n "$NAMESPACE" >/dev/null 2>&1 \
  || fail "StatefulSet $STATEFULSET does not exist in namespace $NAMESPACE"

pass "StatefulSet $STATEFULSET exists"

# 2. Derive the expected ordinal-0 Pod name from the StatefulSet name.
POD_NAME="${STATEFULSET}-0"

kubectl get pod "$POD_NAME" -n "$NAMESPACE" >/dev/null 2>&1 \
  || fail "Expected PostgreSQL Pod $POD_NAME does not exist"

# 3. Wait until the current Pod is Ready before starting.
kubectl wait \
  --for=condition=Ready \
  "pod/$POD_NAME" \
  -n "$NAMESPACE" \
  --timeout="$TIMEOUT" >/dev/null \
  || fail "PostgreSQL Pod $POD_NAME is not Ready before the test"

pass "PostgreSQL Pod is Ready before disruption"

# 4. Record original Pod identity.
OLD_POD_JSON="$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o json)"
OLD_POD_UID="$(echo "$OLD_POD_JSON" | jq -r '.metadata.uid')"
OLD_POD_CREATED="$(echo "$OLD_POD_JSON" | jq -r '.metadata.creationTimestamp')"
OLD_POD_NODE="$(echo "$OLD_POD_JSON" | jq -r '.spec.nodeName')"

printf '\nOriginal PostgreSQL Pod:\n'
printf '  Name:    %s\n' "$POD_NAME"
printf '  UID:     %s\n' "$OLD_POD_UID"
printf '  Created: %s\n' "$OLD_POD_CREATED"
printf '  Node:    %s\n' "$OLD_POD_NODE"

pass "Recorded original PostgreSQL Pod UID"

# 5. Discover the PVC actually mounted by this Pod.
PVC_NAMES="$(
  echo "$OLD_POD_JSON" |
  jq -r '.spec.volumes[]? | select(.persistentVolumeClaim != null) | .persistentVolumeClaim.claimName'
)"

PVC_COUNT="$(printf '%s\n' "$PVC_NAMES" | sed '/^$/d' | wc -l | tr -d ' ')"

[[ "$PVC_COUNT" -ge 1 ]] \
  || fail "No PVC-mounted volume found on PostgreSQL Pod $POD_NAME"

# NordicShop should have one PostgreSQL data PVC. If more exist, use the first and record all.
PVC_NAME="$(printf '%s\n' "$PVC_NAMES" | sed '/^$/d' | head -n 1)"

printf '\nPVC(s) mounted by PostgreSQL Pod:\n%s\n' "$PVC_NAMES"

PVC_JSON="$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o json)"
PVC_UID="$(echo "$PVC_JSON" | jq -r '.metadata.uid')"
PVC_PHASE="$(echo "$PVC_JSON" | jq -r '.status.phase')"
PV_NAME="$(echo "$PVC_JSON" | jq -r '.spec.volumeName')"

[[ "$PVC_PHASE" == "Bound" ]] \
  || fail "PVC $PVC_NAME is not Bound before the test (phase=$PVC_PHASE)"

printf 'Primary PVC: %s\n' "$PVC_NAME"
printf 'PVC UID:     %s\n' "$PVC_UID"
printf 'PV:          %s\n' "$PV_NAME"

pass "Recorded Bound PostgreSQL PVC $PVC_NAME"

# 6. Prove Order exists before disruption.
PRE_ORDER_COUNT="$(
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atqc "SELECT count(*) FROM orders WHERE id = '"$ORDER_ID"';"'
)"

[[ "$PRE_ORDER_COUNT" == "1" ]] \
  || fail "Order $ORDER_ID does not exist before PostgreSQL Pod deletion"

pass "Order $ORDER_ID exists before disruption"

# 7. Prove expected order lines exist before disruption.
PRE_LINE_COUNT="$(
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atqc "SELECT count(*) FROM order_lines WHERE order_id = '"$ORDER_ID"';"'
)"

[[ "$PRE_LINE_COUNT" == "$EXPECTED_LINE_COUNT" ]] \
  || fail "Order $ORDER_ID has $PRE_LINE_COUNT lines before disruption (expected $EXPECTED_LINE_COUNT)"

pass "Order $ORDER_ID has $PRE_LINE_COUNT order lines before disruption"

printf '\nOrder before disruption:\n'
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
  sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT id, customer_name, customer_email, status, created_at FROM orders WHERE id = '"$ORDER_ID"';"'

printf '\nOrder lines before disruption:\n'
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
  sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT id, order_id, tenant_id, product_id, product_name, quantity, unit_price FROM order_lines WHERE order_id = '"$ORDER_ID"' ORDER BY id;"'

# 8. Delete ONLY the PostgreSQL Pod.
printf '\nDeleting ONLY PostgreSQL Pod %s (PVC will NOT be deleted)...\n' "$POD_NAME"

kubectl delete pod "$POD_NAME" \
  -n "$NAMESPACE" \
  --wait=false >/dev/null \
  || fail "Could not delete PostgreSQL Pod $POD_NAME"

pass "Requested deletion of PostgreSQL Pod only"

# 9. Wait for the old Pod UID to disappear.
TIMEOUT_SECONDS=240
case "$TIMEOUT" in
  *s) TIMEOUT_SECONDS="${TIMEOUT%s}" ;;
  *m) TIMEOUT_SECONDS=$(( ${TIMEOUT%m} * 60 )) ;;
esac

SECONDS_WAITED=0

while :; do
  CURRENT_UID="$(
    kubectl get pod "$POD_NAME" -n "$NAMESPACE" \
      -o jsonpath='{.metadata.uid}' 2>/dev/null || true
  )"

  if [[ -z "$CURRENT_UID" || "$CURRENT_UID" != "$OLD_POD_UID" ]]; then
    break
  fi

  if (( SECONDS_WAITED >= TIMEOUT_SECONDS )); then
    fail "Original PostgreSQL Pod UID did not disappear within $TIMEOUT"
  fi

  sleep 2
  SECONDS_WAITED=$((SECONDS_WAITED + 2))
done

pass "Original PostgreSQL Pod instance was removed"

# 10. Wait for StatefulSet recovery.
printf 'Waiting for StatefulSet recovery...\n'

kubectl rollout status "statefulset/$STATEFULSET" \
  -n "$NAMESPACE" \
  --timeout="$TIMEOUT" \
  || fail "StatefulSet $STATEFULSET did not recover within $TIMEOUT"

kubectl wait \
  --for=condition=Ready \
  "pod/$POD_NAME" \
  -n "$NAMESPACE" \
  --timeout="$TIMEOUT" >/dev/null \
  || fail "Replacement PostgreSQL Pod did not become Ready within $TIMEOUT"

pass "StatefulSet recreated a Ready PostgreSQL Pod"

# 11. Record replacement Pod identity and prove it is a new instance.
NEW_POD_JSON="$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o json)"
NEW_POD_UID="$(echo "$NEW_POD_JSON" | jq -r '.metadata.uid')"
NEW_POD_CREATED="$(echo "$NEW_POD_JSON" | jq -r '.metadata.creationTimestamp')"
NEW_POD_NODE="$(echo "$NEW_POD_JSON" | jq -r '.spec.nodeName')"

[[ "$NEW_POD_UID" != "$OLD_POD_UID" ]] \
  || fail "Replacement PostgreSQL Pod has the same UID as the deleted Pod"

printf '\nReplacement PostgreSQL Pod:\n'
printf '  Name:    %s\n' "$POD_NAME"
printf '  UID:     %s\n' "$NEW_POD_UID"
printf '  Created: %s\n' "$NEW_POD_CREATED"
printf '  Node:    %s\n' "$NEW_POD_NODE"

pass "Replacement PostgreSQL Pod has a new UID"

# 12. Verify the replacement Pod mounts the same PVC claim.
NEW_PVC_NAMES="$(
  echo "$NEW_POD_JSON" |
  jq -r '.spec.volumes[]? | select(.persistentVolumeClaim != null) | .persistentVolumeClaim.claimName'
)"

echo "$NEW_PVC_NAMES" | grep -Fxq "$PVC_NAME" \
  || fail "Replacement Pod does not reference original PVC $PVC_NAME"

pass "Replacement Pod references the same PVC name $PVC_NAME"

# 13. Verify the PVC object itself is still the same object and still Bound.
NEW_PVC_JSON="$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o json)"
NEW_PVC_UID="$(echo "$NEW_PVC_JSON" | jq -r '.metadata.uid')"
NEW_PVC_PHASE="$(echo "$NEW_PVC_JSON" | jq -r '.status.phase')"
NEW_PV_NAME="$(echo "$NEW_PVC_JSON" | jq -r '.spec.volumeName')"

[[ "$NEW_PVC_UID" == "$PVC_UID" ]] \
  || fail "PVC UID changed: before=$PVC_UID after=$NEW_PVC_UID"

[[ "$NEW_PVC_PHASE" == "Bound" ]] \
  || fail "PVC $PVC_NAME is not Bound after recovery (phase=$NEW_PVC_PHASE)"

[[ "$NEW_PV_NAME" == "$PV_NAME" ]] \
  || fail "PVC is bound to a different PV after recovery: before=$PV_NAME after=$NEW_PV_NAME"

pass "Same PVC object remains Bound to the same PV"

# 14. Confirm Order still exists after PostgreSQL recovery.
POST_ORDER_COUNT="$(
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atqc "SELECT count(*) FROM orders WHERE id = '"$ORDER_ID"';"'
)"

[[ "$POST_ORDER_COUNT" == "1" ]] \
  || fail "Order $ORDER_ID is missing after PostgreSQL recovery"

pass "Order $ORDER_ID still exists after PostgreSQL recovery"

# 15. Confirm order lines still exist after recovery.
POST_LINE_COUNT="$(
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atqc "SELECT count(*) FROM order_lines WHERE order_id = '"$ORDER_ID"';"'
)"

[[ "$POST_LINE_COUNT" == "$EXPECTED_LINE_COUNT" ]] \
  || fail "Order $ORDER_ID has $POST_LINE_COUNT lines after recovery (expected $EXPECTED_LINE_COUNT)"

pass "Order $ORDER_ID still has $POST_LINE_COUNT order lines after recovery"

printf '\nOrder after recovery:\n'
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
  sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT id, customer_name, customer_email, status, created_at FROM orders WHERE id = '"$ORDER_ID"';"'

printf '\nOrder lines after recovery:\n'
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
  sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT id, order_id, tenant_id, product_id, product_name, quantity, unit_price FROM order_lines WHERE order_id = '"$ORDER_ID"' ORDER BY id;"'

# 16. Final PVC and Pod evidence.
printf '\nCurrent PostgreSQL Pod:\n'
kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o wide

printf '\nCurrent PostgreSQL PVC:\n'
kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o wide

printf '%s\n' '--------------------------------------------------'
printf 'POSTGRESQL PERSISTENCE: PASS\n'
printf 'Order ID:        %s\n' "$ORDER_ID"
printf 'Order lines:     %s\n' "$POST_LINE_COUNT"
printf 'PostgreSQL Pod:  %s\n' "$POD_NAME"
printf 'Old Pod UID:     %s\n' "$OLD_POD_UID"
printf 'New Pod UID:     %s\n' "$NEW_POD_UID"
printf 'PVC:             %s\n' "$PVC_NAME"
printf 'PVC UID:         %s\n' "$PVC_UID"
printf 'PV:              %s\n' "$PV_NAME"
printf 'SUMMARY: %d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"

if [[ -n "$EVIDENCE_FILE" ]]; then
  printf 'Evidence file: %s\n' "$EVIDENCE_FILE"
fi
