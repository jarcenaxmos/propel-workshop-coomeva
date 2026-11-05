-- dim_asociado: un registro por asociado (deduplicado) con regional, oficina y plan de salud vigente
CREATE OR REPLACE TABLE `coop_trabajo.dim_asociado`
CLUSTER BY id_regional, segmento
OPTIONS (
  description = 'Un registro por asociado (deduplicado desde coop_raw.asociados), con regional, oficina, segmento, estado, edad, antigüedad y plan de salud vigente.',
  labels = [('workshop', 'coomeva')]
) AS
WITH asociado AS (
  SELECT * FROM `coop_raw.asociados`
  WHERE TRUE
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_asociado ORDER BY fecha_vinculacion DESC) = 1
),
salud AS (
  SELECT id_asociado, ANY_VALUE(plan) AS plan_salud_vigente
  FROM `coop_raw.afiliaciones_salud`
  WHERE estado = 'Activa'
  GROUP BY id_asociado
)
SELECT
  a.id_asociado,
  o.id_regional,
  r.regional,
  a.id_oficina,
  o.oficina,
  a.segmento,
  a.estado,
  DATE_DIFF(DATE '2026-10-31', a.fecha_nacimiento, YEAR)
    - IF(FORMAT_DATE('%m%d', a.fecha_nacimiento) > '1031', 1, 0) AS edad,
  DATE_DIFF(DATE '2026-10-31', a.fecha_vinculacion, MONTH) AS antiguedad_meses,
  s.plan_salud_vigente
FROM asociado AS a
LEFT JOIN `coop_raw.oficinas` AS o USING (id_oficina)
LEFT JOIN `coop_raw.regionales` AS r ON r.id_regional = o.id_regional
LEFT JOIN salud AS s USING (id_asociado);
