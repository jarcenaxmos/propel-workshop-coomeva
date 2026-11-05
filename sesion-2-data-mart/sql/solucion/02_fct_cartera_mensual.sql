-- Paso 2 · Crear fct_cartera_mensual: particionada por fecha_corte, clusterizada por id_regional, producto
-- Reemplaza coop_trabajo por tu dataset.
-- Por qué así:
--   PARTITION BY fecha_corte  -> todo tablero filtra por corte; BigQuery salta los cortes que no pides.
--   CLUSTER BY id_regional, producto -> dentro de cada corte, ordena por lo que más se filtra.
--   Desnormalizada: el tablero no repite 3 JOIN en cada consulta.
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
