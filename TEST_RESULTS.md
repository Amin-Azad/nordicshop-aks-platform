# NordicShop Application Baseline v2 - Test Results

The application baseline was verified before being placed in the repository and was retested after the repository layout changes.

## Result

`7 passed`

The tests cover the current local development baseline, including API behavior, customer flow, vendor isolation and admin behavior.

## Important scope note

The active development runtime currently uses SQLite and an in-memory cart adapter. PostgreSQL Row-Level Security is included as the database policy for the later PostgreSQL environment but is not claimed as executed by the current SQLite test run. Redis is also introduced during the container-learning phase.

Run the current repository tests from the repository root with:

```bash
python -m pytest -q application/tests
```
