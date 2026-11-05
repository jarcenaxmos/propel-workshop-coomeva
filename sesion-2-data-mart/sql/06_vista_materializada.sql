-- Paso 6 · Vista materializada con refresco incremental + smart tuning
-- Ejecuta cada bloque por separado: selecciónalo en el editor y Run.
-- Por qué así:
--   Solo SUM: la MV incremental acepta agregados como salida, no cálculos SOBRE agregados.
--   El ICV (vencida / total) se calcula al leer. Si lo pones dentro, la MV deja de ser incremental.
--   PARTITION BY fecha_corte: alineada con la tabla base, refresca por partición.
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
