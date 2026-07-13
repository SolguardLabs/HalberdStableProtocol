# Halberd Stable Protocol

![banner](./assets/banner.png)

HalberdStableProtocol is a Vyper stablecoin system for overcollateralized vaults,
oracle-driven risk checks, liquidations, and reserve-backed redemptions.

The repository models the core surfaces expected in a production review target:
minting against collateral, risk-parameter management, liquidation support,
keeper registries, accounting hooks, emergency controls and a stability module
for reserve operations.

## Layout

```text
src/                 Vyper contracts
tests/               Python pytest/web3 test suite
scripts/             Local validation helpers
requirements.txt     Python toolchain
```

## Requirements

- Python 3.11 or newer.
- Vyper 0.4.x.
- pytest, web3, eth-tester and py-evm from `requirements.txt`.

## Setup

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

```bash
python -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
```

## Validation

```powershell
powershell -ExecutionPolicy Bypass -File scripts\ci.ps1
```

```bash
bash scripts/ci.sh
```

The CI flow compiles every Vyper source and runs the full Python integration
suite.

## Protocol Components

- `HalberdVaults`: collateral vault creation, debt minting, repayment and
  liquidation entrypoints.
- `HalberdUSD`: stablecoin used by vaults and the stability module.
- `HalberdRiskEngine`: market-level collateral, minting and liquidation limits.
- `HalberdOracle`: local price-feed registry for deterministic tests.
- `HalberdStabilityModule`: reserve redemption and loss absorption flows.
- `HalberdAccounting`, `HalberdReserveLedger` and `HalberdAuditHooks`: reporting
  and reconciliation helpers.
- `HalberdCircuitBreaker`, `HalberdEmergencyShutdown`, `HalberdTimelock` and
  `HalberdKeeperRegistry`: operational controls.

## License

MIT.
