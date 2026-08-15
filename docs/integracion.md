# Integración

## Compilación

Los artefactos se generan directamente desde las fuentes Vyper; no se versionan
ABIs o bytecode derivados.

```mermaid
flowchart LR
    SOURCE["Contrato .vy"] --> VYPER["compile_code"]
    VYPER --> ABI["ABI"]
    VYPER --> BYTE["Bytecode"]
    ABI --> WEB3["web3.py"]
    BYTE --> WEB3
    WEB3 --> EVM["EVM destino"]
```

```python
artifact = compile_code(source, output_formats=["abi", "bytecode"])
factory = w3.eth.contract(abi=artifact["abi"], bytecode=artifact["bytecode"])
tx = factory.constructor(*args).transact({"from": admin})
receipt = w3.eth.wait_for_transaction_receipt(tx)
```

## Orden de configuración

```mermaid
sequenceDiagram
    participant A as Admin
    participant U as HUSD
    participant O as Oracle
    participant R as RiskEngine
    participant V as Vaults
    participant S as StabilityModule
    A->>U: set_vault(V)
    A->>U: set_stability_module(S)
    A->>V: set_stability_module(S)
    A->>O: set_feed(asset, price, heartbeat, deviation)
    A->>R: configure_market(asset, ratios, caps)
    A->>R: set_fees(asset, issuance, redemption)
```

Verifica cada receipt antes de continuar. Un address no nulo no demuestra que
la contraparte exponga la interfaz esperada.

## Flujo cliente

```mermaid
flowchart TD
    INPUT["Importe humano"] --> UNIT["Convertir a WAD"]
    UNIT --> READ["Leer precio, policy y allowance"]
    READ --> SIM["Simular llamada"]
    SIM --> TX["Enviar transacción"]
    TX --> RECEIPT["Esperar receipt"]
    RECEIPT --> EVENTS["Decodificar eventos"]
    EVENTS --> RECON["Conciliar balances y deuda"]
```

## Reglas de consumo

- no uses `float` para importes o ratios;
- establece slippage explícito en redenciones;
- no reutilices cotizaciones tras un cambio de bloque o precio;
- trata pausas y reverts como resultados operativos esperables;
- valida chain ID, addresses y bytecode antes de firmar;
- registra la versión del contrato y el bloque de lectura.

## Lecturas agregadas

`HalberdLens` y `HalberdAuditHooks` reducen llamadas para interfaces y
conciliación. No sustituyen lecturas autoritativas cuando se prepara una
transacción económica.
