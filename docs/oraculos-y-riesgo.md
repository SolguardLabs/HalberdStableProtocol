# Oráculos y motor de riesgo

## Registro de feeds

Cada feed conserva precio, heartbeat, desviación máxima, versión y timestamp.
Los precios deben ser positivos y estar dentro del máximo del contrato.

```mermaid
flowchart LR
    NEW["Nuevo precio"] --> RANGE{"Rango válido"}
    RANGE -- No --> REJECT["Rechazar"]
    RANGE -- Sí --> DEV{"Desviación permitida"}
    DEV -- No --> QUEUE["Actualización diferida"]
    DEV -- Sí --> STORE["Guardar precio y versión"]
    STORE --> FRESH{"Heartbeat vigente"}
```

## Política por mercado

```mermaid
classDiagram
    class MarketPolicy {
        min_collateral_ratio_bps
        liquidation_ratio_bps
        liquidation_bonus_bps
        issuance_fee_bps
        redemption_fee_bps
        debt_ceiling
        min_debt
        max_vault_debt
    }
    class MarketStatus {
        enabled
        minting_paused
        redemption_paused
        liquidation_paused
    }
    MarketPolicy --> MarketStatus
```

La configuración exige `min_ratio >= liquidation_ratio >= 10.000`, bonus
acotado y caps coherentes. Las pausas se aplican por superficie para evitar que
una contención de emisión bloquee necesariamente repagos.

## Decisión de emisión

```mermaid
sequenceDiagram
    participant V as Vaults
    participant O as Oracle
    participant R as RiskEngine
    V->>O: value_of(asset, collateral)
    O-->>V: collateral_value
    V->>R: debt_within_caps
    R-->>V: bool
    V->>R: is_healthy(value, next_debt)
    R-->>V: bool
    V->>R: issuance_fee(amount)
    R-->>V: fee
```

## Procedimiento de actualización

1. simular el nuevo precio y ratios;
2. comprobar desviación y heartbeat;
3. revisar deuda total y concentración;
4. aplicar el cambio con la cuenta autorizada;
5. verificar evento, versión y timestamp;
6. recalcular salud, liquidaciones y matriz de solvencia.

No mezcles una actualización de precio extraordinaria con un cambio de caps en
la misma revisión operativa.
