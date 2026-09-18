# NordicShop - Tenant Isolation Evidence

**Timestamp:** 2026-09-18T19:57:15Z  
**Environment:** AKS  
**API:** http://127.0.0.1:8000  
**Result:** **FAIL**

## Test summary

- Passed: 2
- Failed: 9
- Vendor A tenant: 
- Vendor B tenant: 
- Vendor A test product: 
- Vendor B test product: 

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
