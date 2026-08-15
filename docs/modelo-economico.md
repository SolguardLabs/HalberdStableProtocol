# Modelo económico

## Emisión sobrecolateralizada

Un vault deposita colateral y emite HUSD dentro del ratio mínimo y de los caps de
mercado. La comisión de emisión se calcula en basis points.

```mermaid
flowchart LR
    C["Colateral"] --> V["Valor por oráculo"]
    P["Precio e18"] --> V
    V --> CAP["Capacidad por ratio"]
    R["Ratio mínimo"] --> CAP
    D["Deuda existente"] --> AV["Capacidad disponible"]
    CAP --> AV
    AV --> MINT["Mint permitido"]
```

```text
valor = collateral_amount × price_e18 / 10^18
deuda_máxima = valor × 10.000 / min_ratio_bps
fee = mint_amount × issuance_fee_bps / 10.000
```

## Liquidación

Cuando `health_bps` cae por debajo de `liquidation_ratio_bps`, un liquidator
puede repagar deuda y recibir colateral con bonus limitado.

```mermaid
sequenceDiagram
    participant L as Liquidator
    participant V as Vaults
    participant R as RiskEngine
    participant O as Oracle
    participant U as HUSD
    L->>V: liquidate(vault, repay)
    V->>O: value_of(collateral)
    V->>R: is_liquidatable
    V->>U: burn_from(liquidator)
    V->>R: liquidation_seize_value
    V-->>L: colateral limitado
```

El seize nunca excede la garantía disponible. La deuda y el colateral se
reducen en la misma transacción.

## Recursos estresados

```mermaid
flowchart TD
    RES["Reserva"] --> RH["Reserva tras haircut"]
    REC["Colateral recuperable"] --> LR["Recuperación esperada"]
    RH --> TOTAL["Recursos"]
    LR --> TOTAL
    SUP["Supply"] --> OBL["Obligaciones"]
    Q["Cola"] --> OBL
    BAD["Deuda reconocida"] --> OBL
    BUF["Buffer"] --> OBL
    TOTAL --> COV["coverage_bps"]
    OBL --> COV
```

```text
stressed_reserve = reserve × (10.000 - haircut_bps) / 10.000
recovered = collateral × recovery_bps / 10.000
buffer = supply × capital_buffer_bps / 10.000
resources = stressed_reserve + recovered
obligations = supply + queued + bad_debt + buffer
```

La proyección devuelve liquidez neta o gap, nunca ambos. `mint_headroom` exige
el target de cobertura y no concede capacidad si el supply ya lo supera.

## Unidades

- activos fungibles: WAD de 18 decimales;
- ratios y fees: basis points;
- tiempo: segundos de bloque;
- precios: valor e18 por unidad de colateral.

Los integradores deben conservar estas unidades hasta el último paso de
presentación.
