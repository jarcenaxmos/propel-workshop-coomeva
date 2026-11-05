-- Paso 5 · fct_movimientos: particionada por día (DATE de un TIMESTAMP) + clustering
-- Ejecuta cada bloque por separado: selecciónalo en el editor y Run.
-- Por qué así:
--   PARTITION BY DATE(fecha_movimiento) -> fecha_movimiento es TIMESTAMP; la partición diaria sale de él.
--   CLUSTER BY id_regional, tipo_movimiento -> los tableros de captación filtran por regional y tipo.
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
