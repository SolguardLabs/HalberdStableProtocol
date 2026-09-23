# HalberdStableProtocol

[![CI](https://github.com/SolguardLabs/HalberdStableProtocol/actions/workflows/ci.yml/badge.svg)](https://github.com/SolguardLabs/HalberdStableProtocol/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/SolguardLabs/HalberdStableProtocol?display_name=tag)](https://github.com/SolguardLabs/HalberdStableProtocol/releases)
[![Vyper](https://img.shields.io/badge/Vyper-0.4.3-9f4cf4)](https://vyperlang.org/)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB)](https://www.python.org/)

![HalberdStableProtocol](./assets/banner.png)

HalberdStableProtocol es un sistema de moneda estable sobrecolateralizada escrito
en Vyper. Integra vaults, oráculo, límites por mercado, liquidaciones, reservas,
redenciones, gobernanza diferida, respuesta de emergencia y observabilidad
contable en contratos de responsabilidades acotadas.

La versión `1.0.0` fija Vyper `0.4.3`, Python `3.12` y una suite determinista
sobre PyEVM. Los contratos usan enteros de 18 decimales y basis points; ninguna
decisión económica depende de coma flotante.

## Arquitectura

```mermaid
flowchart LR
    U["Usuario"] --> VAULT["HalberdVaults"]
    U --> STAB["StabilityModule"]
    VAULT --> USD["HalberdUSD"]
    VAULT --> ORACLE["HalberdOracle"]
    VAULT --> RISK["RiskEngine"]
    STAB --> USD
    STAB --> VAULT
    STAB --> ORACLE
    STAB --> RISK
    VAULT --> ACCOUNT["Accounting"]
    VAULT --> RESERVE["ReserveLedger"]
    SOLV["SolvencyController"] -. observación .-> VAULT
    SOLV -. escenarios .-> STAB
```

| Dominio | Contratos principales | Responsabilidad |
| --- | --- | --- |
| emisión | `HalberdUSD`, `HalberdVaults` | supply, deuda y garantía |
| precios | `HalberdOracle` | feeds, heartbeat y desviación |
| riesgo | `HalberdRiskEngine` | ratios, caps, fees y pausas |
| reservas | `HalberdStabilityModule`, `HalberdReserveLedger` | redenciones y conciliación |
| liquidación | `HalberdVaults`, `HalberdAuctionHouse` | cierre de posiciones inseguras |
| gobierno | `HalberdTimelock`, `HalberdParameterRegistry` | cambios diferidos y límites |
| operación | `CircuitBreaker`, `EmergencyShutdown`, `KeeperRegistry` | contención y automatización |
| análisis | `HalberdLens`, `HalberdAuditHooks`, `SolvencyController` | lectura y escenarios |

## Ciclo de un vault

```mermaid
stateDiagram-v2
    [*] --> Open: open_vault
    Open --> Funded: deposit
    Funded --> Active: mint
    Active --> Active: repay / deposit
    Active --> Funded: repay total
    Funded --> Closed: withdraw total
    Active --> Unsafe: precio o ratio
    Unsafe --> Active: recapitalización
    Unsafe --> Liquidated: liquidate
    Closed --> [*]
    Liquidated --> [*]
```

La capacidad de emisión deriva del valor de garantía y el ratio mínimo:

```text
valor_garantía = cantidad × precio_e18 / 10^18
deuda_máxima = valor_garantía × 10.000 / ratio_mínimo_bps
salud_bps = valor_garantía × 10.000 / deuda
```

La liquidación solo se habilita por debajo del ratio configurado y limita el
colateral incautado al saldo real del vault.

## Redenciones y reservas

```mermaid
sequenceDiagram
    participant R as Redeemer
    participant S as StabilityModule
    participant U as HalberdUSD
    participant V as Vaults
    participant O as Oracle
    participant K as RiskEngine
    R->>S: redeem(HUSD, minOut)
    S->>K: can_redeem(asset)
    S->>U: transferFrom + burn
    S->>O: amount_for_value
    S->>V: release_reserve
    V-->>R: colateral
    S-->>R: evento Redemption
```

La redención aplica la comisión configurada, respeta `min_collateral_out` y no
puede entregar más colateral del disponible. El estado expone supply, valor de
reserva, volumen redimido y ratio de backing para conciliación.

## Control de solvencia

`HalberdSolvencyController` proyecta recursos y obligaciones con haircut de
reserva, recuperación de liquidaciones, buffer de capital, deuda reconocida y
concentración. Es un plano de lectura independiente: no emite, quema ni mueve
colateral.

```mermaid
flowchart TD
    RV["Valor de reserva"] --> HR["Haircut"]
    LC["Colateral recuperable"] --> RR["Tasa de recuperación"]
    HR --> RES["Recursos estresados"]
    RR --> RES
    SUP["Supply"] --> OBL["Obligaciones"]
    QUEUE["Redenciones en cola"] --> OBL
    BAD["Deuda reconocida"] --> OBL
    BUF["Buffer de capital"] --> OBL
    RES --> VIEW["Cobertura, gap y banda"]
    OBL --> VIEW
    CONC["Mayor bucket"] --> VIEW
```

Bandas: `0 deficit`, `1 constrained`, `2 guarded` y `3 resilient`.

## Inicio rápido

```bash
python -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
python scripts/ci.py
```

En PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\scripts\ci.ps1
```

La validación compila los 19 contratos, revisa los archivos Python y ejecuta 22
casos públicos sobre un EVM local.

## Ejemplo de integración

```python
from pathlib import Path
from vyper import compile_code

source = Path("src/HalberdSolvencyController.vy").read_text(encoding="utf-8")
artifact = compile_code(source, output_formats=["abi", "bytecode"])

assert artifact["abi"]
assert artifact["bytecode"].startswith("0x")
```

## Documentación

- [Arquitectura](./docs/arquitectura.md)
- [Modelo económico](./docs/modelo-economico.md)
- [Vaults y liquidaciones](./docs/vaults-y-liquidaciones.md)
- [Oráculos y riesgo](./docs/oraculos-y-riesgo.md)
- [Operaciones](./docs/operaciones.md)
- [Integración](./docs/integracion.md)
- [Despliegue seguro](./docs/despliegue-seguro.md)

Consulta [SECURITY.md](./SECURITY.md) para el proceso de reporte privado y las
versiones soportadas.

## Licencia

MIT. Consulta [LICENSE](./LICENSE).
