#!/usr/bin/env bash

set -u

NAMESPACE="nordicshop"
ARGO_NAMESPACE="argocd"
APP="nordicshop"
VALUES_FILE="helm/nordicshop/values-dev.yaml"
EVIDENCE_DIR="docs/evidence/security-recovery"

STAMP="$(date -u +"%Y%m%d-%H%M%S")"
START_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
REPORT="${EVIDENCE_DIR}/invalid-api-image-recovery-${STAMP}.md"

mkdir -p "$EVIDENCE_DIR"

echo
echo "============================================"
echo " NordicShop - Invalid API Image Recovery Test"
echo "============================================"
echo

# ---------------------------------------------------------
# Safety checks
# ---------------------------------------------------------

if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "FAIL: You must run this test from main."
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "FAIL: Working tree is not clean."
    git status --short
    exit 1
fi

ARGO_TARGET="$(kubectl get application "$APP" -n "$ARGO_NAMESPACE" \
    -o jsonpath='{.spec.source.targetRevision}')"

if [[ "$ARGO_TARGET" != "main" ]]; then
    echo "FAIL: Argo is not tracking main. Current target: $ARGO_TARGET"
    exit 1
fi

ARGO_BEFORE="$(kubectl get application "$APP" -n "$ARGO_NAMESPACE" \
    -o jsonpath='{.status.sync.status}/{.status.health.status}')"

if [[ "$ARGO_BEFORE" != "Synced/Healthy" ]]; then
    echo "FAIL: Argo must be Synced/Healthy before starting. Current: $ARGO_BEFORE"
    exit 1
fi

ORIGINAL_IMAGE="$(awk '
  /^api:/ {in_api=1; next}
  in_api && /^[^[:space:]]/ {in_api=0}
  in_api && /^[[:space:]]+image:/ {
      sub(/^[[:space:]]+image:[[:space:]]*/, "")
      print
      exit
  }
' "$VALUES_FILE")"

if [[ -z "$ORIGINAL_IMAGE" ]]; then
    echo "FAIL: Could not discover current API image."
    exit 1
fi

INVALID_IMAGE="${ORIGINAL_IMAGE%@*}:invalid-recovery-test-${STAMP}"

echo "Current API image:"
echo "$ORIGINAL_IMAGE"
echo
echo "Temporary invalid image:"
echo "$INVALID_IMAGE"
echo

read -r -p "This will intentionally cause an API rollout failure. Continue? [y/N] " answer

if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Cancelled."
    exit 0
fi

# ---------------------------------------------------------
# Introduce invalid desired state through Git
# ---------------------------------------------------------

python - "$VALUES_FILE" "$INVALID_IMAGE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
invalid = sys.argv[2]

text = path.read_text()
lines = text.splitlines()

inside_api = False
changed = False

for i, line in enumerate(lines):
    if line.startswith("api:"):
        inside_api = True
        continue

    if inside_api and line and not line[0].isspace():
        inside_api = False

    if inside_api and line.strip().startswith("image:"):
        indent = line[:len(line) - len(line.lstrip())]
        lines[i] = f"{indent}image: {invalid}"
        changed = True
        break

if not changed:
    raise SystemExit("Could not update api.image")

path.write_text("\n".join(lines) + "\n")
PY

git add "$VALUES_FILE"
git commit -m "test: introduce invalid API image"

BAD_COMMIT="$(git rev-parse HEAD)"

echo
echo "Pushing controlled failure commit..."
git push origin main

kubectl annotate application "$APP" \
    -n "$ARGO_NAMESPACE" \
    argocd.argoproj.io/refresh=hard \
    --overwrite >/dev/null

echo
echo "Waiting for Argo/AKS to detect the bad image..."

DETECTED="no"
DETECTED_TIME=""
FAILURE_STATE=""

for _ in {1..24}; do
    sleep 5

    ARGO_STATE="$(kubectl get application "$APP" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.status.sync.status}/{.status.health.status}')"

    POD_STATE="$(kubectl get pods -n "$NAMESPACE" \
        -l app=nordicshop-api \
        --no-headers 2>/dev/null || true)"

    echo "Argo: $ARGO_STATE"

    if echo "$POD_STATE" | grep -Eq \
        'ImagePullBackOff|ErrImagePull|CrashLoopBackOff|CreateContainerError'; then
        DETECTED="yes"
        DETECTED_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        FAILURE_STATE="$POD_STATE"
        echo "Controlled failure detected."
        break
    fi
done

# ---------------------------------------------------------
# Recover strictly through Git revert
# ---------------------------------------------------------

echo
echo "Reverting bad desired state through Git..."

git revert --no-edit "$BAD_COMMIT"

RECOVERY_COMMIT="$(git rev-parse HEAD)"

git push origin main

kubectl annotate application "$APP" \
    -n "$ARGO_NAMESPACE" \
    argocd.argoproj.io/refresh=hard \
    --overwrite >/dev/null

echo
echo "Waiting for recovery..."

RECOVERED="no"

for _ in {1..36}; do
    sleep 5

    ARGO_AFTER="$(kubectl get application "$APP" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.status.sync.status}/{.status.health.status}')"

    READY="$(kubectl get deployment nordicshop-api \
        -n "$NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"

    DESIRED="$(kubectl get deployment nordicshop-api \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"

    echo "Argo: $ARGO_AFTER | API Ready: ${READY:-0}/${DESIRED:-?}"

    if [[ "$ARGO_AFTER" == "Synced/Healthy" &&
          -n "$READY" &&
          "$READY" == "$DESIRED" ]]; then
        RECOVERED="yes"
        break
    fi
done

END_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

FINAL_IMAGE="$(kubectl get deployment nordicshop-api \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].image}')"

# ---------------------------------------------------------
# Evidence
# ---------------------------------------------------------

cat > "$REPORT" <<EOFREPORT
# NordicShop - Invalid API Image Recovery Evidence

**Started:** $START_TIME  
**Completed:** $END_TIME  
**Environment:** AKS  
**GitOps controller:** Argo CD  

## Baseline

- Argo before test: $ARGO_BEFORE
- Original API image: $ORIGINAL_IMAGE

## Controlled failure

- Invalid API image: $INVALID_IMAGE
- Failure commit: $BAD_COMMIT
- Failure detected: $DETECTED
- Failure detected at: ${DETECTED_TIME:-not detected}

## Recovery

- Recovery method: Git revert
- Recovery commit: $RECOVERY_COMMIT
- Recovered: $RECOVERED
- Final Argo state: ${ARGO_AFTER:-unknown}
- Final API image: $FINAL_IMAGE

## Result

$(if [[ "$DETECTED" == "yes" && "$RECOVERED" == "yes" && "$FINAL_IMAGE" == "$ORIGINAL_IMAGE" ]]; then
    echo "**PASS**"
else
    echo "**FAIL**"
fi)

The failure was introduced and recovered only through Git desired state.
EOFREPORT

echo
echo "============================================"
echo " Result"
echo "============================================"
echo "Failure detected: $DETECTED"
echo "Recovered:        $RECOVERED"
echo "Final image:"
echo "$FINAL_IMAGE"
echo
echo "Evidence:"
echo "$REPORT"
echo

if [[ "$DETECTED" == "yes" &&
      "$RECOVERED" == "yes" &&
      "$FINAL_IMAGE" == "$ORIGINAL_IMAGE" ]]; then
    echo "PASS: GitOps invalid-image recovery succeeded."
    exit 0
fi

echo "FAIL: Review the evidence and cluster state."
exit 1
