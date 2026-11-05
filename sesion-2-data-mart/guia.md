# Guía del participante · Sesión II · BigQuery: construcción del data mart

**Hands-on · 60 minutos · 8 pasos.** Particionado, clustering y aceleración, medido.

Vas a construir el mart de cartera y movimientos de la cooperativa en tu propio dataset y a **medir** cuánto lee BigQuery antes y después de cada decisión. Los números de esta guía (en "Deberías ver") se midieron el 4-nov-2026 en `tu proyecto`; los tuyos deben coincidir en bytes. Los milisegundos no: varían.

Todo el SQL está también en `sql/NN_*.sql`. Si te atrasas, `sql/solucion/` construye el mart completo de una vez y sigues midiendo desde ahí.

---

## Preparación (todos, 3 minutos)

1. Abre la consola de BigQuery en el proyecto `tu proyecto`. Para crear tablas y consultar usa la ubicación **us-east1**: si el editor te muestra otra, More > Query settings > Data location.
2. En el editor: **More > Query settings > desmarca "Use cached results"**. Una consulta servida desde cache lee 0 bytes y arruina la comparación.
3. Abre una pestaña nueva del editor por paso. Ejecuta **cada bloque por separado**: selecciónalo y pulsa Run (si no seleccionas nada, BigQuery corre todo el contenido de la pestaña).
4. Dónde mirar los bytes:
   - **Antes de correr**: arriba a la derecha del editor, "This query will process X" (dry run, gratis).
   - **Después de correr**: pestaña Job information, "Bytes processed" y "Bytes billed".
   - **En SQL**: `INFORMATION_SCHEMA.JOBS_BY_USER` (paso 8).
5. Anota cada número en una hoja o en un bloc: en el paso 8 los comparas con la tabla de resultados.

**Qué es `coop_trabajo`**: el dataset donde vas a crear tus tablas. Reemplaza `coop_trabajo` por su nombre en cada SQL (Buscar y reemplazar del editor, Ctrl/Cmd+H).

---

## Paso 1 · El "antes": un tablero sobre `coop_raw`

**Qué hacer.** Ejecuta la consulta del tablero de cartera sobre las tablas tal como llegaron (sin partición, sin clustering, con 3 JOIN) y anota los bytes. Después corre dos consultas más para ver qué hace el `WHERE` en una tabla sin particionar.

```sql
-- 1a. Tablero: cartera total, vencida e ICV por regional, último corte.
SELECT
  r.regional,
  SUM(c.saldo_capital) AS cartera_total,
  SUM(IF(c.dias_mora > 30, c.saldo_capital, 0)) AS cartera_vencida,
  ROUND(SAFE_DIVIDE(SUM(IF(c.dias_mora > 30, c.saldo_capital, 0)),
                    SUM(c.saldo_capital)) * 100, 2) AS icv_pct
FROM `coop_raw.cartera_mensual` AS c
JOIN `coop_raw.asociados` AS a USING (id_asociado)
JOIN `coop_raw.oficinas` AS o USING (id_oficina)
JOIN `coop_raw.regionales` AS r ON r.id_regional = o.id_regional
WHERE c.fecha_corte = '2026-10-31'
GROUP BY r.regional
ORDER BY cartera_total DESC;

-- 1b. La trampa: ¿el WHERE por fecha reduce los bytes en una tabla sin particionar?
SELECT SUM(saldo_capital) AS cartera_total
FROM `coop_raw.cartera_mensual`
WHERE fecha_corte = '2026-10-31';

-- 1c. Misma tabla, sin WHERE. Compara los bytes con 1b.
SELECT SUM(saldo_capital) AS cartera_total
FROM `coop_raw.cartera_mensual`;
```

**Por qué.** `cartera_mensual` guarda 34 cortes mensuales en una sola tabla sin particionar. Para pedir un corte, BigQuery tiene que leer la columna de los 34. El `WHERE` no ayuda: tiene que **leer** `fecha_corte` para decidir qué filas descarta, pero no se salta nada.

**Deberías ver:**

| Consulta | Bytes procesados |
|---|---:|
| 1a (tablero, 3 JOIN) | 67.632.481 (~64,5 MiB) |
| 1b (con WHERE) | 36.300.864 (~34,6 MiB) |
| 1c (sin WHERE) | 24.200.576 (~23,1 MiB) |

La sorpresa: **1b lee más que 1c.** Agregar el filtro por fecha subió los bytes. El resultado de 1a para Cali debe ser `407080839220` de cartera total y `5.67` de ICV.

**Errores comunes.**
- *Salen 0 bytes o "cache hit"*: no desmarcaste "Use cached results".
- *`Not found: Dataset coop_raw`*: no tienes el proyecto `tu proyecto` seleccionado o la ubicación del editor no es `us-east1`.
- *`Access Denied`* sobre `coop_raw`: falta el rol `bigquery.dataViewer` (avisar al facilitador).

---

## Paso 2 · Crear `fct_cartera_mensual`: partición + clustering

**Qué hacer.** Crea la tabla de hechos del mart. Es una `CREATE TABLE ... AS SELECT` desde `coop_raw`; tarda unos 7 segundos.

```sql
CREATE OR REPLACE TABLE `coop_trabajo.fct_cartera_mensual`
PARTITION BY fecha_corte
CLUSTER BY id_regional, producto
OPTIONS (
  description = 'Cartera de crédito por crédito y corte mensual, con producto, línea, regional y segmento del asociado.',
  labels = [('workshop', 'coomeva')]
) AS
WITH asociado AS (
  -- coop_raw.asociados trae id_asociado duplicados: nos quedamos con un registro por asociado
  SELECT id_asociado, id_oficina, segmento
  FROM `coop_raw.asociados`
  WHERE TRUE
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_asociado ORDER BY fecha_vinculacion DESC) = 1
)
SELECT
  c.fecha_corte,
  c.id_credito,
  c.id_asociado,
  cr.id_producto,
  p.producto,
  p.linea,
  o.id_regional,
  r.regional,
  a.id_oficina,
  a.segmento,
  c.saldo_capital,
  c.cuota_mes,
  c.valor_pagado,
  c.dias_mora,
  c.dias_mora > 30 AS en_mora_30,
  c.dias_mora > 90 AS en_mora_90
FROM `coop_raw.cartera_mensual` AS c
JOIN `coop_raw.creditos` AS cr USING (id_credito)
JOIN `coop_raw.productos` AS p ON p.id_producto = cr.id_producto
LEFT JOIN asociado AS a ON a.id_asociado = c.id_asociado
LEFT JOIN `coop_raw.oficinas` AS o ON o.id_oficina = a.id_oficina
LEFT JOIN `coop_raw.regionales` AS r ON r.id_regional = o.id_regional;

-- Verifica: filas por corte (deberías ver 34 cortes, de 2024-01-31 a 2026-10-31)
SELECT COUNT(*) AS filas, COUNT(DISTINCT fecha_corte) AS cortes,
       MIN(fecha_corte) AS primer_corte, MAX(fecha_corte) AS ultimo_corte
FROM `coop_trabajo.fct_cartera_mensual`;
```

**Por qué cada decisión.**
- `PARTITION BY fecha_corte`: todo tablero de cartera pide un corte o un rango de cortes. BigQuery sabe **antes de correr** qué particiones puede saltar.
- `CLUSTER BY id_regional, producto`: dentro de cada partición ordena los bloques por las columnas que más se filtran después de la fecha. El orden importa: un filtro por `producto` solo (sin `id_regional`) aprovecha poco.
- **Desnormalizada** (producto, línea, regional, segmento dentro de la tabla): BigQuery es columnar; una columna repetida cuesta poco y evita 3 JOIN en cada consulta del tablero.
- **Dedup de asociados** con `QUALIFY ROW_NUMBER()`: `coop_raw.asociados` trae 20 `id_asociado` repetidos; sin esto, cada JOIN duplicaría su cartera.
- `en_mora_30` y `en_mora_90` precalculados con las definiciones del glosario (cartera vencida = `dias_mora > 30`).

**Deberías ver.** "Created `coop_trabajo.fct_cartera_mensual`" y, en la consulta de verificación: `1512536` filas, `34` cortes, de `2024-01-31` a `2026-10-31`. En la pestaña Details de la tabla: Partitioned by Day, field `fecha_corte`; Clustered by `id_regional, producto`.

**Errores comunes.**
- *`Not found: Dataset coop_trabajo`*: no reemplazaste el placeholder o el dataset está en otra ubicación (debe ser `us-east1`).
- *`Access Denied: ... bigquery.tables.create`*: falta `dataEditor` en tu dataset.
- *Tienes menos de 34 cortes o menos filas*: corriste solo una parte del script; selecciona todo el `CREATE` hasta el `;`.

---

## Paso 3 · El "después": la misma pregunta, medida

**Qué hacer.** Repite el tablero sobre `fct_cartera_mensual` y compara los bytes con el paso 1.

```sql
-- 3a. Tablero: mismo cálculo que 1a, sin JOIN y leyendo un solo corte.
--     Ojo: las cifras salen un poco distintas a las de 1a. No es un error: el mart deduplica
--     los 20 asociados repetidos de coop_raw y el JOIN directo del paso 1 los contaba dos veces.
SELECT
  regional,
  SUM(saldo_capital) AS cartera_total,
  SUM(IF(en_mora_30, saldo_capital, 0)) AS cartera_vencida,
  ROUND(SAFE_DIVIDE(SUM(IF(en_mora_30, saldo_capital, 0)),
                    SUM(saldo_capital)) * 100, 2) AS icv_pct
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte = '2026-10-31'
GROUP BY regional
ORDER BY cartera_total DESC;

-- 3b. Equivalente a 1b: ahora el WHERE sí poda particiones.
SELECT SUM(saldo_capital) AS cartera_total
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte = '2026-10-31';

-- 3c. Clustering: un año, una regional. El dry run da un techo; el real puede ser menor.
SELECT producto, SUM(saldo_capital) AS cartera_total
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte BETWEEN '2025-11-30' AND '2026-10-31'
  AND id_regional = 'R01'   -- Cali. Literal: un valor de subconsulta no poda bloques
GROUP BY producto
ORDER BY cartera_total DESC;

-- 3d. Clustering, medido: el mismo año SIN filtrar regional. Compara el real de 3c y 3d en
--     Job information (el dry run de ambos es un techo). Ojo: con tablas tan chicas el efecto es pequeño.
SELECT producto, SUM(saldo_capital) AS cartera_total
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte BETWEEN '2025-11-30' AND '2026-10-31'
GROUP BY producto
ORDER BY cartera_total DESC;
```

**Por qué.** La partición se ve **en el dry run** (BigQuery sabe qué particiones lee). El clustering no: con tablas clusterizadas el número del validador es un **techo**; los bytes reales se ven después de correr, en Job information.

**Deberías ver:**

| Consulta | Antes | Después |
|---|---:|---:|
| Tablero (1a → 3a) | 67.632.481 | **1.882.637** (-97 %) |
| Suma de un corte (1b → 3b) | 36.300.864 | **1.302.936** (-96 %) |
| 3c: 12 cortes, solo regional R01 | | 28.500.574 |
| 3d: 12 cortes, todas las regionales | | 26.837.445 |

Tres cosas para notar:
1. Las cifras de 3a **no son idénticas** a las de 1a (Cali: `406863649751` vs `407080839220`). No es un error: el mart deduplicó los 20 asociados repetidos y el JOIN del paso 1 los contaba dos veces.
2. **Bytes facturados**: 3a y 3b salen en 10 MiB aunque procesen ~1 MiB, porque on-demand cobra mínimo 10 MiB por consulta. Con tablas de este tamaño el ahorro en pesos es chico; lo que ves es el comportamiento que escala con la tabla.
3. **3c vs 3d casi iguales**: el clustering casi no se nota. Cada partición pesa pocos MiB y la documentación dice que con tablas o particiones de menos de 64 MB la mejora del clustering es despreciable. Con tablas de cientos de GB sí se nota.

**Errores comunes.**
- *Los bytes no bajan*: estás consultando `coop_raw.cartera_mensual` en vez de `coop_trabajo.fct_cartera_mensual`.
- *3c muestra un número distinto al dry run*: normal; el dry run es un techo con clustering (el de 3c dice ~28,5 MiB, el real 27,2).
- *`id_regional = 'R01'` no devuelve nada*: los ids van de `R01` a `R06` (R01 = Cali, R02 = Bogotá, R03 = Medellín, R04 = Barranquilla, R05 = Bucaramanga, R06 = Eje Cafetero).

---

## Paso 4 · `require_partition_filter`: que nadie lea toda la historia por accidente

**Qué hacer.** Actívalo en **tu copia** y mira qué pasa cuando alguien se olvida del filtro.

```sql
ALTER TABLE `coop_trabajo.fct_cartera_mensual`
SET OPTIONS (require_partition_filter = TRUE);

-- 4a. Sin filtro de partición: debe FALLAR (y no cobra nada).
SELECT regional, SUM(saldo_capital) AS cartera_total
FROM `coop_trabajo.fct_cartera_mensual`
GROUP BY regional;

-- 4b. La trampa: hay filtro de fecha, pero dinámico (subconsulta). ¿Pasa?
SELECT regional, SUM(saldo_capital) AS cartera_total
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte = (SELECT MAX(fecha_corte) FROM `coop_raw.cartera_mensual`)
GROUP BY regional;

-- 4c. Filtro constante sobre la columna de partición: pasa y poda.
SELECT fecha_corte, regional, SUM(saldo_capital) AS cartera_total
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte >= DATE_SUB(DATE '2026-10-31', INTERVAL 11 MONTH)
GROUP BY fecha_corte, regional
ORDER BY fecha_corte, regional;

-- 4d. Parámetro de script: también cuenta como constante.
DECLARE corte DATE DEFAULT (SELECT MAX(fecha_corte) FROM `coop_raw.cartera_mensual`);
SELECT regional, SUM(saldo_capital) AS cartera_total
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte = corte
GROUP BY regional;
```

**Por qué.** Con la opción activa, una consulta sin un filtro **usable** sobre la columna de partición **falla antes de leer nada** (cuesta 0). Protege de un `SELECT *` sin `WHERE` sobre una tabla de años. Se activa con `ALTER TABLE`: la consola no deja cambiarla después de crear la tabla. **No va en `coop_marts`**: un agente conversacional que olvida el filtro fallaría.

**Deberías ver:**
- 4a: error `Cannot query over table 'coop_trabajo.fct_cartera_mensual' without a filter over column(s) 'fecha_corte' that can be used for partition elimination`.
- 4b: **el mismo error**, aunque sí tiene `WHERE fecha_corte = ...`. La trampa: el valor sale de una subconsulta (dinámico) y BigQuery no puede podar antes de ejecutar.
- 4c: pasa, procesa 20.496.160 bytes (12 cortes), con filtro constante.
- 4d: pasa. Una variable `DECLARE` del script cuenta como constante.

**Errores comunes.**
- *4a funciona (no falla)*: el `ALTER` no se ejecutó, o lo corriste sobre otra tabla.
- *Tu herramienta de BI o tu agente falla con ese error*: es lo esperado; que el filtro sea una constante o un parámetro.
- *Un filtro con `OR` o con función sobre la columna tampoco poda*: ver paso 5.

---

## Paso 5 · `fct_movimientos`: partición diaria sobre un TIMESTAMP

**Qué hacer.** Crea la segunda tabla de hechos (tarda ~27 s), mide el antes y el después de la captación neta de octubre y prueba la trampa de la función.

```sql
CREATE OR REPLACE TABLE `coop_trabajo.fct_movimientos`
PARTITION BY DATE(fecha_movimiento)
CLUSTER BY id_regional, tipo_movimiento
OPTIONS (
  description = 'Movimientos de aportes y ahorro con producto, línea, regional y segmento del asociado.',
  labels = [('workshop', 'coomeva')]
) AS
WITH asociado AS (
  SELECT id_asociado, id_oficina, segmento
  FROM `coop_raw.asociados`
  WHERE TRUE
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_asociado ORDER BY fecha_vinculacion DESC) = 1
)
SELECT
  m.id_movimiento,
  m.fecha_movimiento,
  m.id_asociado,
  m.id_producto,
  p.producto,
  p.linea,
  o.id_regional,
  r.regional,
  a.segmento,
  m.tipo_movimiento,
  m.canal,
  m.monto
FROM `coop_raw.movimientos_aportes_ahorro` AS m
JOIN `coop_raw.productos` AS p USING (id_producto)
LEFT JOIN asociado AS a USING (id_asociado)
LEFT JOIN `coop_raw.oficinas` AS o ON o.id_oficina = a.id_oficina
LEFT JOIN `coop_raw.regionales` AS r ON r.id_regional = o.id_regional;

-- 5a. Antes (raw): captación neta de octubre 2026 por regional.
SELECT r.regional,
  SUM(IF(m.tipo_movimiento IN ('Consignacion', 'Aporte mensual'), m.monto, 0))
  - SUM(IF(m.tipo_movimiento = 'Retiro', m.monto, 0)) AS captacion_neta
FROM `coop_raw.movimientos_aportes_ahorro` AS m
JOIN `coop_raw.asociados` AS a USING (id_asociado)
JOIN `coop_raw.oficinas` AS o USING (id_oficina)
JOIN `coop_raw.regionales` AS r ON r.id_regional = o.id_regional
WHERE m.fecha_movimiento >= '2026-10-01' AND m.fecha_movimiento < '2026-11-01'
GROUP BY r.regional
ORDER BY captacion_neta DESC;

-- 5b. Después: la misma pregunta sobre fct_movimientos.
SELECT regional,
  SUM(IF(tipo_movimiento IN ('Consignacion', 'Aporte mensual'), monto, 0))
  - SUM(IF(tipo_movimiento = 'Retiro', monto, 0)) AS captacion_neta
FROM `coop_trabajo.fct_movimientos`
WHERE fecha_movimiento >= '2026-10-01' AND fecha_movimiento < '2026-11-01'
GROUP BY regional
ORDER BY captacion_neta DESC;

-- 5c. La trampa: envolver la columna en una función. ¿Poda?
SELECT SUM(monto) AS monto
FROM `coop_trabajo.fct_movimientos`
WHERE FORMAT_TIMESTAMP('%Y-%m', fecha_movimiento) = '2026-10';
```

**Por qué.** `fecha_movimiento` es TIMESTAMP; `PARTITION BY DATE(fecha_movimiento)` da una partición por día. `CLUSTER BY id_regional, tipo_movimiento`: los tableros de captación filtran por regional y por tipo (Consignacion, Retiro...). La captación neta sigue el glosario: Consignacion + Aporte mensual - Retiro.

**Deberías ver:**

| Consulta | Bytes procesados |
|---|---:|
| 5a (raw, 3 JOIN) | 216.479.498 (~206,5 MiB) |
| 5b (fct_movimientos) | **6.688.586** (~6,4 MiB, -97 %) |
| 5c (función en el WHERE) | 105.210.384 (~100,3 MiB) |

5c devuelve el mismo dato que un filtro de octubre, pero **lee 16 veces más** y gasta ~60 veces más slot-ms (18.560 vs 302): `FORMAT_TIMESTAMP(...)` sobre la columna de partición impide la poda y obliga a calcular la función en 4,4 millones de filas. Regla: la columna de partición va **sola** a un lado de la comparación, contra constantes.

Cifras de 5a/5b: Cali `5602991000` vs `5600459000` (diferencia por los duplicados, como en el paso 3).

**Errores comunes.**
- *La creación tarda más que los ~27 s medidos*: probablemente muchos participantes creando a la vez; esperar.
- *5b da cifras algo distintas a 5a*: esperado, por los asociados duplicados de `coop_raw` (ver paso 3).

---

## Paso 6 · Vista materializada con refresco incremental

**Qué hacer.** Crea `mv_cartera_regional_mensual`, léela, y comprueba que BigQuery **la usa sola** cuando consultas la tabla base.

```sql
CREATE MATERIALIZED VIEW `coop_trabajo.mv_cartera_regional_mensual`
PARTITION BY fecha_corte
CLUSTER BY regional
OPTIONS (
  enable_refresh = TRUE,
  refresh_interval_minutes = 30,
  description = 'Cartera total y vencida (dias_mora > 30) por regional y corte. ICV = cartera_vencida / cartera_total.',
  labels = [('workshop', 'coomeva')]
) AS
SELECT
  fecha_corte,
  regional,
  SUM(saldo_capital) AS cartera_total,
  SUM(IF(en_mora_30, saldo_capital, 0)) AS cartera_vencida,
  COUNT(*) AS creditos
FROM `coop_trabajo.fct_cartera_mensual`
GROUP BY fecha_corte, regional;

-- 6a. La trampa: intenta meter el ICV dentro de la MV. Debe fallar.
CREATE MATERIALIZED VIEW `coop_trabajo.mv_icv_intento`
AS
SELECT fecha_corte, regional,
  SAFE_DIVIDE(SUM(IF(en_mora_30, saldo_capital, 0)), SUM(saldo_capital)) AS icv
FROM `coop_trabajo.fct_cartera_mensual`
GROUP BY fecha_corte, regional;

-- 6b. Leer la MV: el ICV se calcula al leer (12 cortes x 6 regionales).
SELECT fecha_corte, regional, cartera_total, cartera_vencida,
       ROUND(SAFE_DIVIDE(cartera_vencida, cartera_total) * 100, 2) AS icv_pct
FROM `coop_trabajo.mv_cartera_regional_mensual`
WHERE fecha_corte >= '2025-11-30'
ORDER BY fecha_corte, regional;

-- 6c. Smart tuning: consulta a la TABLA BASE, no a la MV. Mira "Execution details":
--     si BigQuery la reescribió, verás la MV leída en lugar de fct_cartera_mensual.
SELECT fecha_corte, regional,
  ROUND(SAFE_DIVIDE(SUM(IF(en_mora_30, saldo_capital, 0)), SUM(saldo_capital)) * 100, 2) AS icv_pct
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte >= '2025-11-30'
GROUP BY fecha_corte, regional
ORDER BY fecha_corte, regional;

-- 6d. Filtro por una columna que la MV NO tiene (segmento): no hay reescritura.
SELECT fecha_corte, regional, SUM(saldo_capital) AS cartera_total
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte >= '2025-11-30' AND segmento = 'Pensionado'
GROUP BY fecha_corte, regional;
```

**Por qué.**
- Una MV guarda el resultado de una consulta y la mantiene al día. Si es **incremental**, procesa solo lo que cambió en la tabla base (la tabla particionada hace que refresque por partición).
- **Solo `SUM`/`COUNT`**: en una MV incremental los agregados deben ser la salida; no se puede calcular **sobre** un agregado. El ICV (vencida / total) es un cociente de dos `SUM`, así que se calcula **al leer**. 6a lo intenta y falla a propósito.
- **Smart tuning**: si consultas la tabla base y la MV cubre la consulta, BigQuery la reescribe para leer la MV, sin que cambies el SQL.
- Por defecto se refresca como máximo cada 30 minutos (`refresh_interval_minutes = 30`); puedes forzarlo con `CALL BQ.REFRESH_MATERIALIZED_VIEW('coop_trabajo.mv_cartera_regional_mensual')`.

**Deberías ver:**
- 6a: error `BigQuery does not support incremental materialized views with this query shape. Incremental materialized views with aggregation ... must output the result of the aggregation directly, without further transformation`.
- 6b: 72 filas (12 cortes x 6 regionales) con el ICV; procesa **3.684 bytes**.
- 6c: consulta la **tabla base** (`fct_cartera_mensual`) pero el dry run ya dice **3.684 bytes**: BigQuery la reescribió a la MV. Sin la MV esa misma consulta procesa 21.104.747 bytes. En Job information (Execution details), el paso de lectura es la MV. En SQL: `materialized_view_statistics`.
- 6d: filtra por `segmento`, columna que la MV no tiene: **no hay reescritura**, procesa 27.612.524 bytes.

Honestidad sobre los tiempos: con tablas de este tamaño la consulta contra la MV **no fue más rápida** (mediana 240 ms vs 137 ms). La ganancia aquí está en bytes; en latencia aparece cuando la consulta base es lenta de verdad.

**Nota sobre `coop_marts`.** La `mv_cartera_regional_mensual` de `coop_marts` incluye la columna `icv` (para que los agentes de la tarde la lean directo); por eso es una MV *no incremental* (`allow_non_incremental_definition`, `max_staleness`). La que construyes tú es incremental y calcula el ICV al leer. Los números del ICV son iguales.

**Errores comunes.**
- *6c no muestra la reescritura*: revisa que el `FROM` sea tu `fct_cartera_mensual` y que la consulta use solo columnas que la MV tiene (`fecha_corte`, `regional`, y `saldo_capital`/`en_mora_30` agregados). Con otro filtro, como 6d (`segmento`), no hay reescritura.
- *La MV y `require_partition_filter`*: probado: la MV se crea bien aunque la tabla base ya exija el filtro. Al leer la MV directamente, usa un filtro constante sobre `fecha_corte` (6b lo tiene).
- *6a no falla*: copiaste la MV del paso 6 en vez del intento con `SAFE_DIVIDE`; son dos sentencias distintas.

---

## Paso 7 · BI Engine: qué acelera y dónde se apaga

**Qué hacer.** Corre un tablero dos veces, mira si BI Engine lo aceleró y prueba la trampa de row-level security (RLS).

```sql
-- 7a. Consulta de tablero, ahora con detalle por producto. Corre dos veces.
--     (Se agrupa por producto a propósito: la MV del paso 6 no tiene producto, así BigQuery
--     no la reescribe y la consulta lee la tabla, que es lo que BI Engine acelera.)
SELECT regional, producto,
  SUM(saldo_capital) AS cartera_total,
  ROUND(SAFE_DIVIDE(SUM(IF(en_mora_30, saldo_capital, 0)), SUM(saldo_capital)) * 100, 2) AS icv_pct
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte = '2026-10-31'
GROUP BY regional, producto
ORDER BY regional, producto;

-- 7b. ¿La aceleró? Modo y motivos de BI Engine de tus últimos jobs.
SELECT creation_time, job_id,
  bi_engine_statistics.bi_engine_mode AS modo_bi_engine,
  (SELECT STRING_AGG(r.message, ' | ') FROM UNNEST(bi_engine_statistics.bi_engine_reasons) AS r) AS motivos,
  total_bytes_processed, total_slot_ms,
  TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) AS duracion_ms
FROM `region-us-east1`.INFORMATION_SCHEMA.JOBS_BY_USER
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 15 MINUTE)
  AND statement_type = 'SELECT'
  AND query LIKE '%fct_cartera_mensual%'
  AND query NOT LIKE '%INFORMATION_SCHEMA%'
ORDER BY creation_time DESC
LIMIT 5;

-- 7c. La trampa: row-level security. Copia la tabla y ponle una política por regional.
CREATE OR REPLACE TABLE `coop_trabajo.fct_cartera_mensual_rls`
PARTITION BY fecha_corte
CLUSTER BY id_regional, producto
OPTIONS (labels = [('workshop', 'coomeva')])
AS SELECT * FROM `coop_trabajo.fct_cartera_mensual` WHERE fecha_corte >= '2026-01-31';

CREATE OR REPLACE ROW ACCESS POLICY solo_cali
ON `coop_trabajo.fct_cartera_mensual_rls`
GRANT TO ('user:<tu_usuario>')
FILTER USING (regional = 'Cali');

-- 7d. La misma consulta de tablero sobre la tabla con RLS. Luego repite 7b
--     cambiando fct_cartera_mensual por fct_cartera_mensual_rls: modo DISABLED.
SELECT regional, producto,
  SUM(saldo_capital) AS cartera_total,
  ROUND(SAFE_DIVIDE(SUM(IF(en_mora_30, saldo_capital, 0)), SUM(saldo_capital)) * 100, 2) AS icv_pct
FROM `coop_trabajo.fct_cartera_mensual_rls`
WHERE fecha_corte = '2026-10-31'
GROUP BY regional, producto
ORDER BY regional, producto;
```

**Por qué.**
- BI Engine es una caché en memoria **por proyecto y región** (la reserva la creó el facilitador; mínimo 1 GiB) que acelera consultas de tableros hechos en Looker, Data Studio, Tableau o Power BI, o consultas directas. Acelera de forma selectiva: lo que no puede acelerar corre normal, sin fallar.
- **Limitación: no acelera consultas a tablas con row-level security.** Column-level security y data masking sí funcionan. Para Coomeva importa: si el tablero depende de políticas por regional (cada jefe ve su regional), esa tabla no se acelera.
- 7a agrupa por producto a propósito: la MV del paso 6 no tiene producto, así que BigQuery no reescribe la consulta y esta lee la tabla.

**Deberías ver (con reserva de BI Engine, según la documentación):** en 7b, `modo_bi_engine` = FULL o PARTIAL en la segunda corrida de 7a; sobre la tabla con RLS (repite 7b cambiando el nombre de la tabla en el `LIKE`), `DISABLED` con el motivo en la columna `motivos`. 7d: devuelve **solo Cali** (tu política `solo_cali`) y en Job information los bytes procesados aparecen **vacíos** (BigQuery no los informa en tablas con row access policies).

**Qué se verificó y qué no.** Sin reserva, 7b muestra `NULL` en `modo_bi_engine` y `motivos` (así lo medimos); el comportamiento con reserva (FULL/PARTIAL/DISABLED) **no se probó** y sale de la documentación. 7c/7d sí se probaron: la política se crea y filtra, y los bytes salen vacíos.

**Errores comunes.**
- *`modo_bi_engine` sale NULL*: el proyecto no tiene reserva de BI Engine (así salió en nuestra prueba sin reserva) o el job es anterior a que se creó. Avisar al facilitador; la lección de RLS se explica igual.
- *7c: `Access Denied` al crear la política*: según la documentación, `bigquery.rowAccessPolicies.create` está en `roles/bigquery.dataOwner` (y `admin`); con solo `dataEditor` puede fallar. Avisar al facilitador.
- *7d devuelve cero filas*: pusiste en `GRANT TO` un usuario distinto al que ejecuta la consulta. Debe ser tu propio correo (`user:<tu_usuario>`).
- *Cuidado con la política*: con RLS, quien no está en ninguna política **no ve ninguna fila** de la tabla.

---

## Paso 8 · Tu tabla de resultados

**Qué hacer.** Lee tu propio historial de jobs con SQL y arma la tabla antes/después.

```sql
-- Paso 8 · Tu tabla de resultados: bytes y tiempos de todo lo que corriste en la sesión
-- Lee tu propio historial de jobs (JOBS_BY_USER: solo tus jobs, sin permisos extra).
SELECT
  FORMAT_TIMESTAMP('%H:%M:%S', creation_time, 'America/Bogota') AS hora,
  REGEXP_EXTRACT(query, r'FROM `([^`]+)`') AS primera_tabla,
  ROUND(total_bytes_processed / POW(1024, 2), 1) AS mib_procesados,
  ROUND(total_bytes_billed / POW(1024, 2), 1) AS mib_facturados,
  TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) AS duracion_ms,
  total_slot_ms,
  cache_hit,
  bi_engine_statistics.bi_engine_mode AS bi_engine,
  error_result.reason AS error
FROM `region-us-east1`.INFORMATION_SCHEMA.JOBS_BY_USER
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)
  AND job_type = 'QUERY'
  AND statement_type = 'SELECT'
  AND query NOT LIKE '%INFORMATION_SCHEMA%'
ORDER BY creation_time;
```

**Por qué.** `INFORMATION_SCHEMA.JOBS_BY_USER` trae lo mismo que Job information, pero como tabla que puedes cruzar, filtrar y exportar: `total_bytes_processed`, `total_bytes_billed`, `total_slot_ms`, `cache_hit`, `bi_engine_statistics`. Solo ves tus jobs (no requiere permisos extra) y guarda 180 días.

**Deberías ver.** Una fila por consulta de la última hora (las de error aparecen con `error` = `invalidQuery`, bytes vacíos). Compara contra esta tabla (medido el 4-nov-2026; tus bytes deben ser iguales):

| Qué | Antes (raw) | Después |
|---|---:|---:|
| Tablero de cartera (1a → 3a) | 64,5 MiB | 1,8 MiB (-97 %) |
| Captación neta del mes (5a → 5b) | 206,5 MiB | 6,4 MiB (-97 %) |
| ICV por regional y corte, 12 cortes (6c) | 20,1 MiB (tabla) | 0,004 MiB (MV, 3.684 bytes) |
| Función en la columna de partición (5c) | | 100,3 MiB (vs 6,4) |
| Sin filtro de partición (4a) | | error, 0 bytes |

Detalle completo con slot-ms y duraciones en `resultados.md`.

**Errores comunes.**
- *La tabla viene vacía*: `JOBS_BY_USER` muestra tus jobs por `creation_time`; revisa la ventana (`INTERVAL 2 HOUR`) y que estés en la región `region-us-east1`.
- *`Not found` sobre `region-us-east1.INFORMATION_SCHEMA`*: el editor está en otra ubicación.
- *La columna `primera_tabla` sale vacía en algunas filas*: la extrae una expresión regular sobre el texto de la consulta y no la encuentra en todas (por ejemplo, las de `INFORMATION_SCHEMA`). No afecta los bytes.
- *Ves jobs que no son tuyos*: `JOBS_BY_USER` filtra por usuario; si varias personas comparten cuenta, verán los jobs de todas (pasó en la prueba, donde la cuenta se usó en paralelo).

---

## Si te atrasas

`sql/solucion/` tiene el mart completo en el orden correcto (`00_LEEME.md` explica cómo correrlo). Con las tablas ya creadas, retoma en el paso 3 (o 6) y sigue midiendo: lo importante es la medición, no el tipeo.

## Lo que te llevas

1. La partición por la fecha que filtra el tablero baja los bytes **antes** de correr; el filtro tiene que ser constante y la columna sola.
2. El clustering ordena dentro de la partición; con tablas chicas no se nota.
3. `require_partition_filter` protege tu copia; no va en tablas que consumen agentes.
4. Una MV incremental precalcula lo que el tablero pide siempre; BigQuery la usa sola, si la consulta cabe en ella.
5. BI Engine acelera en memoria, pero no consultas a tablas con row-level security.
6. Mide siempre: dry run, Job information, `INFORMATION_SCHEMA.JOBS`.

Fuentes de cada afirmación sobre el producto: `FUENTES.md`.
