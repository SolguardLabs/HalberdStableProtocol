# Arquitectura del protocolo

## Capas

Halberd separa token, custodia, precios, política, reservas y operación. Cada
contrato expone una superficie reducida y se conecta mediante interfaces Vyper.

```mermaid
flowchart TB
    subgraph Activos
        USD["HalberdUSD"]
        COL["HalberdCollateral"]
    end
    subgraph Núcleo
        VAULT["HalberdVaults"]
        STAB["StabilityModule"]
        ORACLE["Oracle"]
        RISK["RiskEngine"]
    end
    subgraph Control
        TIME["Timelock"]
        PARAM["ParameterRegistry"]
        BREAK["CircuitBreaker"]
        SHUT["EmergencyShutdown"]
    end
    subgraph Lectura
        LENS["Lens"]
        AUDIT["AuditHooks"]
        SOLV["SolvencyController"]
    end
    COL --> VAULT
    VAULT --> USD
    STAB --> USD
    STAB --> VAULT
    ORACLE --> VAULT
    RISK --> VAULT
    TIME --> PARAM
    PARAM --> RISK
    BREAK --> SHUT
    VAULT --> LENS
    VAULT --> AUDIT
    VAULT -.-> SOLV
```

## Responsabilidades

| Contrato | Escribe fondos | Configura política | Solo lectura económica |
| --- | --- | --- | --- |
| `HalberdUSD` | supply y balances | roles | no |
| `HalberdVaults` | colateral y deuda | módulos | no |
| `StabilityModule` | burn y reserva | guardian/treasury | no |
| `RiskEngine` | no | ratios, caps y fees | sí |
| `Oracle` | no | feeds y límites | sí |
| `SolvencyController` | no | haircuts y buffers | sí |

```mermaid
classDiagram
    class HalberdVaults {
        open_vault()
        mint()
        repay()
        liquidate()
        release_reserve()
    }
    class HalberdUSD {
        mint()
        burn()
        transferFrom()
    }
    class HalberdOracle {
        value_of()
        amount_for_value()
    }
    class HalberdRiskEngine {
        is_healthy()
        can_liquidate()
        redemption_fee()
    }
    HalberdVaults --> HalberdUSD
    HalberdVaults --> HalberdOracle
    HalberdVaults --> HalberdRiskEngine
```

## Fronteras de estado

Los contratos no comparten almacenamiento. La coordinación ocurre mediante
llamadas explícitas y eventos. Los módulos autorizados deben configurarse antes
de habilitar operaciones.

```mermaid
sequenceDiagram
    participant G as Gobierno
    participant R as RiskEngine
    participant O as Oracle
    participant V as Vaults
    participant U as HalberdUSD
    G->>O: set_feed
    G->>R: configure_market
    G->>U: set_vault
    G->>V: set_stability_module
    V->>R: consultar límites
    V->>O: valorar colateral
    V->>U: emitir o retirar supply
```

## Principios

- unidades WAD y basis points explícitas;
- autorización local en cada contrato;
- eventos para cambios económicos y administrativos;
- vistas sin capacidad de escritura;
- circuit breakers independientes de la lógica ordinaria;
- tests desplegados sobre un EVM local determinista.
