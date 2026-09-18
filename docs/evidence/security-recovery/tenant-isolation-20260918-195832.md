# NordicShop - Tenant Isolation Evidence

**Timestamp:** 2026-09-18T19:58:32Z  
**Environment:** AKS  
**API:** http://127.0.0.1:8000  
**Result:** **FAIL**

## Test summary

- Passed: 9
- Failed: 2
- Vendor A tenant: 1
- Vendor B tenant: 2
- Vendor A test product: null
- Vendor B test product: null

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

**FAIL**
