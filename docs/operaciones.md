# Operaciones

## Preparación

La ejecución operativa parte de un commit aprobado, dependencias fijadas y un
entorno Python aislado.

```mermaid
flowchart LR
    COMMIT["Commit aprobado"] --> VENV["Python 3.12 venv"]
    VENV --> DEPS["pip install -r requirements.txt"]
    DEPS --> COMPILE["Compilar 19 contratos"]
    COMPILE --> TEST["22 pruebas"]
    TEST --> READY["Artefacto preparado"]
```

```bash
python -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
python scripts/ci.py
```

## Monitoreo

| Señal | Fuente | Acción |
| --- | --- | --- |
| heartbeat vencido | `HalberdOracle` | pausar superficie dependiente |
| health bajo | `HalberdVaults` | priorizar keeper/liquidación |
| backing bajo | `StabilityModule` | revisar reservas y redenciones |
| gap positivo | `SolvencyController` | bloquear expansión y recapitalizar |
| concentración alta | proyección | reducir cap del bucket |
| operación pendiente | `Timelock` | revisar ETA y predecessor |

```mermaid
flowchart TD
    OBS["Lecturas on-chain"] --> ORA{"Oracle fresco"}
    ORA -- No --> PAUSE["Contención"]
    ORA -- Sí --> COV{"Cobertura suficiente"}
    COV -- No --> LIMIT["Limitar emisión"]
    COV -- Sí --> GAP{"Gap de solvencia"}
    GAP -- Sí --> LIMIT
    GAP -- No --> NORMAL["Operación normal"]
```

## Cambios administrativos

```mermaid
sequenceDiagram
    participant P as Proponente
    participant T as Timelock
    participant R as Revisor
    participant C as Contrato
    P->>T: queue(operation)
    T-->>R: evento + ETA
    R->>R: simular efectos
    R-->>T: aprobación operativa
    T->>C: execute tras demora
    C-->>R: evento de configuración
```

## Incidentes

Conserva bloque, transacción, calldata, receipts, eventos, parámetros y precios.
Aplica la pausa más estrecha disponible. Reproduce sobre un EVM local antes de
proponer cambios y utiliza el canal privado de `SECURITY.md`.
