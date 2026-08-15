# Vaults y liquidaciones

## Apertura y depósito

Cada vault tiene owner, activo, garantía, deuda y timestamps. `open_vault`
asigna un identificador monotónico; `deposit` requiere allowance y actualiza los
agregados por activo.

```mermaid
sequenceDiagram
    participant U as Usuario
    participant C as Colateral
    participant V as Vaults
    U->>V: open_vault(asset)
    V-->>U: vault_id
    U->>C: approve(vaults, amount)
    U->>V: deposit(vault_id, amount)
    V->>C: transferFrom
    V-->>U: CollateralDeposited
```

## Emisión y repago

```mermaid
flowchart TD
    REQ["Solicitud mint"] --> ENABLED{"Mercado habilitado"}
    ENABLED -- No --> DENY["Rechazar"]
    ENABLED -- Sí --> CAPS{"Caps válidos"}
    CAPS -- No --> DENY
    CAPS -- Sí --> HEALTH{"Ratio mínimo"}
    HEALTH -- No --> DENY
    HEALTH -- Sí --> MINT["Emitir HUSD"]
    REPAY["Repay"] --> BURN["Burn HUSD"]
    BURN --> DEBT["Reducir deuda"]
```

El repago se limita a la deuda existente. Tras reducir deuda, el owner puede
retirar garantía si el vault conserva la cobertura exigida.

## Liquidación parcial

```mermaid
stateDiagram-v2
    [*] --> Healthy
    Healthy --> Unsafe: caída de precio
    Unsafe --> Healthy: depósito o repago
    Unsafe --> PartiallyLiquidated: liquidate parcial
    PartiallyLiquidated --> Healthy: ratio recuperado
    PartiallyLiquidated --> Liquidated: deuda agotada
    Unsafe --> Liquidated: liquidate total
```

La ruta calcula el valor a incautar con el bonus configurado y lo convierte a
cantidad de colateral mediante el oráculo. Si el resultado supera el saldo, se
limita al colateral del vault.

## Conciliación

Después de una operación compara:

- deuda del vault y deuda total por activo;
- garantía del vault y colateral total;
- supply de HUSD y eventos de mint/burn;
- balances de owner y liquidator;
- precio y versión del feed utilizados.

Una integración debe esperar el receipt antes de leer el estado posterior.
