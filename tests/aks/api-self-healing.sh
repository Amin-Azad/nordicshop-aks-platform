#!/usr/bin/env bash
set -Eeuo pipefail

# NordicShop AKS API Self-Healing Test
#
# Purpose:
#   - Record the current nordic-api Pod
#   - Delete that Pod
#   - Wait for the Deployment/ReplicaSet to create a Ready replacement
#   - Verify /api/health and /api/ready through the public entry path
#   - Optionally save a timestamped evidence log
#
# Basic run:
#   BASE_URL="http://20.73.231.149" ./tests/aks/api-self-healing.sh
#
# Save evidence:
#   BASE_URL="http://20.73.231.149" SAVE_EVIDENCE=1 ./tests/aks/api-self-healing.sh
#
# Optional overrides:
#   NAMESPACE=nordicshop
#   DEPLOYMENT=nordicshop-api
#   TIMEOUT=180s

BASE_URL="${BASE_URL:-http://20.73.231.149}"
NAMESPACE="${NAMESPACE:-nordicshop}"
DEPLOYMENT="${DEPLOYMENT:-nordicshop-api}"
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
  EVIDENCE_FILE="docs/evidence/aks/api-self-healing-${timestamp}.log"
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

printf 'NordicShop AKS API Self-Healing Test\n'
printf 'Namespace:  %s\n' "$NAMESPACE"
printf 'Deployment: %s\n' "$DEPLOYMENT"
printf 'BASE_URL:   %s\n' "$BASE_URL"
printf 'Timeout:    %s\n' "$TIMEOUT"
printf '%s\n' '--------------------------------------------------'

# 1. Confirm Deployment exists.
kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1 \
  || fail "Deployment $DEPLOYMENT does not exist in namespace $NAMESPACE"

pass "Deployment $DEPLOYMENT exists"

# 2. Build the Pod selector from the Deployment's own matchLabels.
#    This avoids hard-coding assumptions such as app=nordicshop-api.
SELECTOR="$(
  kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json |
  jq -r '.spec.selector.matchLabels
         | to_entries
         | map("\(.key)=\(.value)")
         | join(",")'
)"

[[ -n "$SELECTOR" && "$SELECTOR" != "null" ]] \
  || fail "Could not derive Pod selector from Deployment $DEPLOYMENT"

printf 'Deployment selector: %s\n' "$SELECTOR"
pass "Derived Deployment Pod selector"

# 3. Confirm the Deployment is healthy before disruption.
kubectl rollout status deployment/"$DEPLOYMENT" \
  -n "$NAMESPACE" \
  --timeout="$TIMEOUT" >/dev/null \
  || fail "Deployment is not healthy before the test"

pass "Deployment is healthy before Pod deletion"

# 4. Verify the public API is healthy before disruption.
HEALTH_BEFORE="$(curl -fsS "$BASE_URL/api/health")" \
  || fail "Public /api/health failed before Pod deletion"
assert_json "$HEALTH_BEFORE" "Pre-test API health"
echo "$HEALTH_BEFORE" | jq -e '.status == "ok"' >/dev/null \
  || fail "Pre-test /api/health did not report status=ok"

READY_BEFORE="$(curl -fsS "$BASE_URL/api/ready")" \
  || fail "Public /api/ready failed before Pod deletion"
assert_json "$READY_BEFORE" "Pre-test API readiness"
echo "$READY_BEFORE" | jq -e '.status == "ready"' >/dev/null \
  || fail "Pre-test /api/ready did not report status=ready"

pass "API health and readiness are good before disruption"

# 5. Select one currently Ready API Pod and record its identity.
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

[[ -n "$OLD_POD_JSON" ]] \
  || fail "No Ready Pod found for Deployment $DEPLOYMENT"

OLD_POD_NAME="$(echo "$OLD_POD_JSON" | jq -r '.metadata.name')"
OLD_POD_UID="$(echo "$OLD_POD_JSON" | jq -r '.metadata.uid')"
OLD_POD_CREATED="$(echo "$OLD_POD_JSON" | jq -r '.metadata.creationTimestamp')"
OLD_POD_NODE="$(echo "$OLD_POD_JSON" | jq -r '.spec.nodeName')"

printf '\nCurrent API Pod:\n'
printf '  Name:    %s\n' "$OLD_POD_NAME"
printf '  UID:     %s\n' "$OLD_POD_UID"
printf '  Created: %s\n' "$OLD_POD_CREATED"
printf '  Node:    %s\n' "$OLD_POD_NODE"

pass "Recorded current Ready API Pod $OLD_POD_NAME"

# 6. Delete exactly that Pod.
printf '\nDeleting Pod %s...\n' "$OLD_POD_NAME"
kubectl delete pod "$OLD_POD_NAME" \
  -n "$NAMESPACE" \
  --wait=false >/dev/null \
  || fail "Could not delete Pod $OLD_POD_NAME"

pass "Requested deletion of API Pod $OLD_POD_NAME"

# 7. Wait for the old Pod UID to disappear.
printf 'Waiting for old Pod UID to disappear...\n'

SECONDS_WAITED=0
TIMEOUT_SECONDS=180

# Convert simple timeout values such as 180s or 3m to seconds for our loop.
case "$TIMEOUT" in
  *s) TIMEOUT_SECONDS="${TIMEOUT%s}" ;;
  *m) TIMEOUT_SECONDS=$(( ${TIMEOUT%m} * 60 )) ;;
esac

while :; do
  CURRENT_UID="$(
    kubectl get pod "$OLD_POD_NAME" -n "$NAMESPACE" \
      -o jsonpath='{.metadata.uid}' 2>/dev/null || true
  )"

  if [[ -z "$CURRENT_UID" || "$CURRENT_UID" != "$OLD_POD_UID" ]]; then
    break
  fi

  if (( SECONDS_WAITED >= TIMEOUT_SECONDS )); then
    fail "Old Pod UID $OLD_POD_UID did not disappear within $TIMEOUT"
  fi

  sleep 2
  SECONDS_WAITED=$((SECONDS_WAITED + 2))
done

pass "Original API Pod instance was removed"

# 8. Wait for the Deployment to reconcile back to its desired healthy state.
printf 'Waiting for Deployment reconciliation...\n'

kubectl rollout status deployment/"$DEPLOYMENT" \
  -n "$NAMESPACE" \
  --timeout="$TIMEOUT" \
  || fail "Deployment did not return to Ready state within $TIMEOUT"

pass "Deployment reconciled to desired Ready state"

# 9. Find a Ready replacement Pod with a different UID.
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

[[ -n "$NEW_POD_JSON" ]] \
  || fail "No Ready replacement Pod with a new UID was found"

NEW_POD_NAME="$(echo "$NEW_POD_JSON" | jq -r '.metadata.name')"
NEW_POD_UID="$(echo "$NEW_POD_JSON" | jq -r '.metadata.uid')"
NEW_POD_CREATED="$(echo "$NEW_POD_JSON" | jq -r '.metadata.creationTimestamp')"
NEW_POD_NODE="$(echo "$NEW_POD_JSON" | jq -r '.spec.nodeName')"

[[ "$NEW_POD_UID" != "$OLD_POD_UID" ]] \
  || fail "Replacement Pod UID unexpectedly matches the deleted Pod"

printf '\nReplacement API Pod:\n'
printf '  Name:    %s\n' "$NEW_POD_NAME"
printf '  UID:     %s\n' "$NEW_POD_UID"
printf '  Created: %s\n' "$NEW_POD_CREATED"
printf '  Node:    %s\n' "$NEW_POD_NODE"

pass "Ready replacement API Pod created: $NEW_POD_NAME"

# 10. Show current API Pods as runtime evidence.
printf '\nCurrent API Pods:\n'
kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" -o wide

# 11. Verify public health after recovery.
HEALTH_AFTER="$(curl -fsS "$BASE_URL/api/health")" \
  || fail "Public /api/health failed after recovery"
assert_json "$HEALTH_AFTER" "Post-recovery API health"
echo "$HEALTH_AFTER" | jq -e '.status == "ok"' >/dev/null \
  || fail "Post-recovery /api/health did not report status=ok"

pass "Public /api/health is healthy after recovery"

# 12. Verify public readiness after recovery.
READY_AFTER="$(curl -fsS "$BASE_URL/api/ready")" \
  || fail "Public /api/ready failed after recovery"
assert_json "$READY_AFTER" "Post-recovery API readiness"
echo "$READY_AFTER" | jq -e '.status == "ready"' >/dev/null \
  || fail "Post-recovery /api/ready did not report status=ready"

pass "Public /api/ready is ready after recovery"

printf '%s\n' '--------------------------------------------------'
printf 'API SELF-HEALING: PASS\n'
printf 'Deleted Pod:     %s\n' "$OLD_POD_NAME"
printf 'Deleted Pod UID: %s\n' "$OLD_POD_UID"
printf 'New Pod:         %s\n' "$NEW_POD_NAME"
printf 'New Pod UID:     %s\n' "$NEW_POD_UID"
printf 'SUMMARY: %d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"

if [[ -n "$EVIDENCE_FILE" ]]; then
  printf 'Evidence file: %s\n' "$EVIDENCE_FILE"
fi
