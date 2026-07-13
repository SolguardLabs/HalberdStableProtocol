# Security Policy

## Security Model

HalberdStableProtocol assumes separated roles for governance, keepers,
liquidators, borrowers and reserve operators. The main review surface is the
interaction between vault collateralization, oracle pricing, risk limits,
liquidation accounting and stability-module redemptions.

## Invariants

- Vault debt must remain bounded by configured collateral ratios.
- Liquidations must reduce debt and never seize more collateral than available.
- Oracle updates must affect mint capacity and liquidation eligibility.
- Stability redemptions must respect reserve availability and slippage limits.
- Administrative changes must pass through bounded parameter and emergency
  controls.
- Accounting modules must reconcile supply, reserve value and collateral state.

## Scope

In scope:

- Vyper contracts under `src/`;
- Python tests under `tests/`;
- scripts under `scripts/`;
- CI and dependency-management configuration.

Out of scope:

- external price feeds not included in the repository;
- production token integrations;
- frontends or dashboards;
- deployments to public networks.

## Automated Validation

Run:

```bash
bash scripts/ci.sh
```

The CI flow installs Python dependencies, compiles all Vyper contracts and runs
pytest.

## Reporting

Reports should include:

- observed behavior;
- affected contracts and functions;
- economic impact;
- reproduction steps;
- recommended mitigation;
- expected regression coverage.
