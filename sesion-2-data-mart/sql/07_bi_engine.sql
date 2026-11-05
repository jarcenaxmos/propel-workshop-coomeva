-- Paso 7 · BI Engine: qué acelera y dónde se apaga
-- Ejecuta cada bloque por separado: selecciónalo en el editor y Run.
-- La reserva de BI Engine es del PROYECTO y la crea el facilitador antes (ver guia.md).
-- Tú solo consultas y miras bi_engine_statistics en el job.

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
