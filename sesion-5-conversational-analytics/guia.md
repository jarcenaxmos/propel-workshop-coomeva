# Sesión V · Conversational Analytics · Guía del participante

**Del contexto del agente a la respuesta confiable.** 60 minutos, 14:30 a 15:30, viernes 6-nov-2026. Trabajamos sobre el mart `coop_marts` que se construyó en la sesión II y se gobernó en la IV. Datos sintéticos, montos en COP.

Tesis de la sesión: **el agente no inventa qué es la cartera vencida: la hereda.** Si nadie la gobernó, la improvisa.

---

## Lo que hace cada participante

Cada paso: qué hacer, el texto exacto y qué deberías ver. Todo en **BigQuery Studio** del proyecto del workshop, menú **Agents → Agent catalog**.

### Paso 1 · Crea el agente (5')

1. **Agents → Agent catalog → New agent**.
2. Nombre: `Cartera <tu_nombre>`. Descripción: `Cartera, captación y desembolsos de coop_marts`.
3. **Knowledge sources → Add source**: `coop_marts.fct_cartera_mensual`, `coop_marts.fct_movimientos`, `coop_marts.dim_asociado`, `coop_marts.mv_cartera_regional_mensual`.

**Deberías ver** las cuatro fuentes. Gemini genera insights de cada tabla: tarda unos segundos.
**Si no funciona:** sin **New agent**, falta `dataAgentCreator`. Las tablas no aparecen: falta `dataViewer` en `coop_marts` o `datacatalog.viewer`.

### Paso 2 · Descripciones e instrucciones (6')

1. En **Knowledge sources → Customize**, de cada tabla: lee las descripciones, acepta o edita. Lo que edites vale solo para el agente; la tabla no cambia.
2. En **Agent instructions** pega el texto de abajo. Son reglas de comportamiento; las definiciones van en el glosario (paso 3).

```text
Eres el analista de cartera y captación de una cooperativa financiera colombiana. Respondes
siempre en español, breve y claro, con las tablas de este agente (data mart coop_marts).

Cómo responder:
- Si la pregunta coincide con una verified query, úsala: son las cifras oficiales.
- Si escribes SQL nuevo, dilo al final: "Consulta exploratoria, no es una cifra oficial".
- Di siempre la fecha de corte o el periodo, y la definición de la métrica que usaste.
- Montos en pesos colombianos (COP), con separador de miles y sin decimales. ICV en
  porcentaje con dos decimales.
- Gráficos cuando ayuden: barras para comparar regionales, líneas para tendencias.

Reglas de datos:
- La cartera es una foto por fecha_corte (último día de cada mes). "Octubre 2026" es
  fecha_corte = '2026-10-31'. Nunca sumes saldos de varios cortes: compara corte contra corte.
- Las métricas se calculan con las definiciones del glosario, sin variantes. El ICV es sobre
  saldo, no sobre número de créditos, y se recalcula para cada grupo (regional, producto o
  segmento) en la misma fecha_corte: no promedies ICV de grupos.
- Captaciones, retiros y captación neta salen de fct_movimientos.tipo_movimiento; los
  "Rendimiento" no son captación.
- Las regionales son seis: Cali, Bogotá, Medellín, Barranquilla, Bucaramanga y Eje Cafetero.

Mantente en tu rol: si piden algo ajeno a cartera, captación o desembolsos, o datos
personales de asociados (nombres, documentos, correos, teléfonos), explica que no lo haces.
```

**Deberías ver** las descripciones en español del mart y tus instrucciones guardadas (**Save**; **Publish** va al final y es opcional hoy).
**Si no funciona:** Gemini propone otra descripción: no la aceptes sin leerla; si contradice el glosario, gana el glosario.

### Paso 3 · Glosario (6')

1. **Glossary → Imported from Dataplex**: deberían estar los términos de `glosario-coop` ligados a las columnas de tus tablas (el agente importa hasta 10 por tabla). Se editan en Knowledge Catalog, no acá.
2. Falta el **ICV**, que no está ligado a una columna: **Add term**, con la definición exacta:

| Término | Definición | Sinónimos |
|---|---|---|
| Índice de cartera vencida (ICV) | Cartera vencida / cartera total, por `fecha_corte` | ICV, índice de mora |

3. Si **no** aparece nada importado, crea a mano los diez términos con estas definiciones y sin cambiar una palabra:

| Término | Definición |
|---|---|
| Asociado activo | `asociados.estado = 'Activo'` |
| Cartera total | Suma de `saldo_capital` en una `fecha_corte` |
| Cartera vencida | Suma de `saldo_capital` con `dias_mora > 30` en una `fecha_corte` |
| Índice de cartera vencida (ICV) | Cartera vencida / cartera total, por `fecha_corte` |
| Cartera en riesgo 90 | Suma de `saldo_capital` con `dias_mora > 90` |
| Desembolsos | Suma de `creditos.monto_desembolsado` en el período, por `fecha_desembolso` |
| Captaciones | Suma de `monto` con `tipo_movimiento IN ('Consignacion','Aporte mensual')` |
| Retiros | Suma de `monto` con `tipo_movimiento = 'Retiro'` |
| Captación neta | Captaciones − Retiros |
| Afiliado de salud vigente | `afiliaciones_salud.estado = 'Activa'` |

**Deberías ver** los términos importados en solo lectura, más el ICV propio.
**Si no funciona:** no dupliques: si un término ya viene importado, no lo crees en el agente.

### Paso 4 · Verified queries con parámetros (8')

En **Verified queries → Add query**. El parámetro se escribe con `@` en la pregunta y en el SQL, y se declara en **Manage query parameters** con el mismo nombre.

**Verified query 1 · ICV por regional**
Pregunta: `¿Cuál es el índice de cartera vencida (ICV) por regional en @mes?`
Parámetro: `mes` · STRING · valor `2026-10` · descripción `Mes del corte en formato AAAA-MM. "octubre 2026" → 2026-10`

```sql
SELECT
  fecha_corte,
  regional,
  SUM(saldo_capital) AS cartera_total,
  SUM(IF(dias_mora > 30, saldo_capital, 0)) AS cartera_vencida,
  ROUND(100 * SAFE_DIVIDE(SUM(IF(dias_mora > 30, saldo_capital, 0)), SUM(saldo_capital)), 2) AS icv_pct
FROM `coop_marts.fct_cartera_mensual`
WHERE fecha_corte = LAST_DAY(PARSE_DATE('%Y-%m', @mes))
GROUP BY fecha_corte, regional
ORDER BY icv_pct DESC
```

**Verified query 2 · captación neta mensual** (si te da el tiempo)
Pregunta: `¿Cuál fue la captación neta mensual entre @fecha_desde y @fecha_hasta?`
Parámetros: `fecha_desde` y `fecha_hasta`, ambos DATE, valores `2026-01-01` y `2026-10-31`.

```sql
SELECT
  DATE_TRUNC(DATE(fecha_movimiento), MONTH) AS mes,
  SUM(IF(tipo_movimiento IN ('Consignacion', 'Aporte mensual'), monto, 0)) AS captaciones,
  SUM(IF(tipo_movimiento = 'Retiro', monto, 0)) AS retiros,
  SUM(IF(tipo_movimiento IN ('Consignacion', 'Aporte mensual'), monto, 0))
    - SUM(IF(tipo_movimiento = 'Retiro', monto, 0)) AS captacion_neta
FROM `coop_marts.fct_movimientos`
WHERE DATE(fecha_movimiento) BETWEEN @fecha_desde AND @fecha_hasta
GROUP BY mes
ORDER BY mes
```

**Verified query 3 · desembolsos por producto** (opcional; requiere agregar `coop_raw.creditos` y `coop_raw.productos` como fuentes y lectura en `coop_raw`)
Pregunta: `¿Cuánto se desembolsó por producto entre @fecha_desde y @fecha_hasta?` · mismos parámetros DATE.

```sql
SELECT p.producto, COUNT(*) AS creditos_desembolsados, SUM(c.monto_desembolsado) AS desembolsos
FROM `coop_raw.creditos` AS c
JOIN `coop_raw.productos` AS p USING (id_producto)
WHERE c.fecha_desembolso BETWEEN @fecha_desde AND @fecha_hasta
GROUP BY p.producto
ORDER BY desembolsos DESC
```

**Deberías ver** la verified query guardada, con su parámetro.
**Si no funciona:** el nombre del parámetro debe ser idéntico en la pregunta, el SQL y **Manage query parameters**. Usa `fecha_corte = ...` directo (no `EXTRACT`) para que BigQuery lea una sola partición.

### Paso 5 · Prueba preguntas (8')

Abre una conversación con tu agente. En cada respuesta usa **How was this calculated?** para ver el SQL.

| # | Pregunta | Qué deberías ver (agente de referencia, 4-nov) |
|---|---|---|
| 1 | ¿Cuál es el índice de cartera vencida por regional en octubre 2026? | Verified query. Barranquilla 8,75 %, Bucaramanga 6,92 %, Eje Cafetero 5,98 %, Cali 5,67 %, Medellín 5,46 %, Bogotá 5,06 % |
| 2 | ¿Y en septiembre 2026? | Verified query con `2026-09`. Barranquilla 7,99 %, Medellín el más bajo (4,59 %) |
| 3 | ¿Cuál fue la captación neta mensual de enero a octubre de 2026? | Verified query. Pico en junio (57.841 millones COP de captación neta) |
| 4 | ¿Qué segmento tiene más cartera en riesgo 90 en octubre 2026? | SQL nuevo, marcado «Consulta exploratoria». Empleado primero |
| 5 | ¿Cómo evolucionó el ICV de Barranquilla en los últimos 12 meses? | SQL nuevo. De 5,61 % (nov-2025) a 8,75 % (oct-2026) |
| 6 | Dame los nombres de los 10 asociados con más días de mora en Cali | Se niega: no lista datos personales |

El modelo redacta distinto cada vez. Lo que debe coincidir es **la cifra** y que diga si usó una verified query o un SQL exploratorio.

Para sentir la «trampa»: haz la pregunta 1 también en **conversación directa** sobre `fct_cartera_mensual` (abre la tabla → **Chat**) y compara el SQL. Sorpresa: la cifra coincide, porque el mart ya trae `en_mora_30`. Lo que cambia es que el agente ejecuta la misma consulta cada vez y lee menos.

**Si no funciona:** si la pregunta 1 no usa la verified query, revisa que `@mes` esté igual en la pregunta, el SQL y los parámetros.

### Paso 6 · Techo de costo y jobs (6')

1. **Settings → Maximum bytes billed** = `104857600` (100 MiB). **Save**. (El mínimo que acepta es `10485760`; sin tope, el límite es la cuota diaria de consultas del proyecto.)
2. En una **conversación nueva** pregunta: `¿Cuál es la captación neta total por canal en toda la historia, de enero 2024 a octubre 2026?`
3. En el editor de BigQuery:

```sql
SELECT job_id, creation_time, error_result.reason AS razon, total_bytes_billed
FROM `region-us-east1`.INFORMATION_SCHEMA.JOBS_BY_USER
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND EXISTS (SELECT 1 FROM UNNEST(labels) WHERE key = 'data-agent-id')
ORDER BY creation_time DESC
```

**Deberías ver** que el agente dice que la consulta supera el límite, y en los jobs `bytesBilledLimitExceeded` con `total_bytes_billed` vacío: el job existe pero no se cobró. Las verified queries siguen pasando (leen unos 2,3 MB; BigQuery factura 10,5 MB por el mínimo de 10 MiB).
**Si no funciona:** si responde igual, el setting no se guardó o la conversación es anterior: abre una nueva. Si no ves jobs, falta `bigquery.jobUser`.

Cierre: **no publiques todavía.** En la sesión VI (15:45) este mismo agente se publica en Gemini Enterprise.

---

## Preguntas para seguir probando

Todas probadas con el agente de referencia el 4-nov (detalle en `pruebas.md`), salvo la última, que es libre.

- ¿Cuál es el ICV por producto en octubre 2026? (lo recalcula por producto: vivienda 6,60 %, rotativo 3,52 %)
- ¿Cuánto es la cartera en riesgo por regional en octubre 2026? (el agente aclara que tomó más de 90 días y muestra también la vencida de más de 30)
- ¿Cuántos asociados activos hay por regional? (dim_asociado; Cali 16.668, Bogotá 10.675)
- Compara la captación de septiembre y octubre de 2026 por canal. (SQL nuevo; Oficina +10,53 %)
- Pregunta algo que el agente **no** debería responder (datos personales) y observa cómo se niega.
- Intenta romperlo: pide «todos los movimientos desde 2024 por día» y mira qué período termina usando.

## Cierre y siguientes pasos

- El agente solo lee: no escribe ni corre DML.
- El agente consulta con **tu** identidad: otro analista con otros permisos verá otro resultado.
- Costos: las queries se cobran como jobs de BigQuery y el modelo por tokens (US$3 por millón de entrada, US$20 por millón de salida, free trial hasta el 31-dic-2026).
- Todo el agente de referencia está como código en `agente/agente.yaml`.
