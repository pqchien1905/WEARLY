# Remove the vulnerable coverage-loader dependency chain

Audit A05: twenty Moderate entries trace to sprintf-js through
load-nyc-config → js-yaml3 → argparse1. npm's proposed Jest/ts-jest downgrade
is unsuitable. Existing load-nyc-config uses only `js-yaml.load(string)`.
js-yaml4.3.2 is already installed for Nest CLI/ESLint and retains that API,
without argparse1/sprintf-js.

Sources inspected: installed loader1.1.0 and lockfile; official
[loader source](https://github.com/istanbuljs/load-nyc-config/blob/v1.1.0/index.js),
[YAML4 API](https://github.com/nodeca/js-yaml/blob/4.3.2/README.md),
[sprintf advisory](https://github.com/advisories/GHSA-hp3w-g68c-fv3c).

- Add a compatibility test loading actual YAML coverage config with extends,
  arrays, booleans and numeric thresholds, plus malformed input rejection.
- Override only load-nyc-config's js-yaml to exact4.3.2; keep all direct Jest/
  ts-jest/runtime versions and the existing Swagger-specific YAML override.
- Inspect lockfile delta, run full and production npm audit, lint/build/unit/
  real E2E and isolated coverage-loader test; verify a clean npm-ci install.
- Rebuild runtime images if lockfile changes, verify containers, review and
  record the outcome. Do not use npm audit fix --force.

Outcome: completed. Full/production audits zero; lint/build,17 unit and80 E2E
passed. Three clean npm-ci image builds and runtime verification passed against
fresh `wearly_handoff_1792482185306_60f38cdd_test`. Independent review found no
actionable compatibility issue. Evidence `.tools/goal-toolchain-*`.
