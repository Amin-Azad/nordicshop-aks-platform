# NordicShop - Invalid API Image Recovery Evidence

**Started:** 2026-09-18T20:59:37Z  
**Completed:** 2026-09-18T21:00:41Z  
**Environment:** AKS  
**GitOps controller:** Argo CD  

## Baseline

- Argo before test: Synced/Healthy
- Original API image: acrnordicshopazaddevweu.azurecr.io/nordicshop-api@sha256:1b5f884a0758031574b37916294b0d40210227b662abd1f51194da25200792e6

## Controlled failure

- Invalid API image: acrnordicshopazaddevweu.azurecr.io/nordicshop-api:invalid-recovery-test-20260918-205937
- Failure commit: c25f7fe8dd9f1a38c9e383246bd7d201eb35247f
- Failure detected: yes
- Failure detected at: 2026-09-18T21:00:18Z

## Recovery

- Recovery method: Git revert
- Recovery commit: 02ff594cc5f86695f326748fda6526edb6042c65
- Recovered: yes
- Final Argo state: Synced/Healthy
- Final API image: acrnordicshopazaddevweu.azurecr.io/nordicshop-api@sha256:1b5f884a0758031574b37916294b0d40210227b662abd1f51194da25200792e6

## Result

**PASS**

The failure was introduced and recovered only through Git desired state.
