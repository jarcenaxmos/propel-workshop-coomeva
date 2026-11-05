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
