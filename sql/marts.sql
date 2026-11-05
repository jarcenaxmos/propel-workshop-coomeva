--# Workshop Propel · Coomeva. Todos los derechos reservados.
--
-- Marts de referencia del workshop Coomeva: coop_raw -> coop_marts (us-east1).
-- Ejecutar: bq --project_id=__PROJECT__ --location=us-east1 query --use_legacy_sql=false < marts.sql
-- Intent: las sesiones IV, V y VI trabajan sobre estas tablas; las definiciones de metricas
-- son EXACTAMENTE las del glosario del workshop.
-- Caveat: sin require_partition_filter (un agente conversacional fallaria con el).
-- edad y antiguedad se calculan a la fecha fija 2026-10-31 (fin de la historia) para que sea reproducible.

-- 1. dim_asociado: un registro por asociado (deduplicado) ----------------------------------------
CREATE OR REPLACE TABLE `__PROJECT__.coop_marts.dim_asociado` (
  id_asociado STRING OPTIONS (description = 'Identificador unico del asociado (ya deduplicado desde coop_raw.asociados).'),
  nombre_completo STRING OPTIONS (description = 'Nombre completo del asociado (ficticio).'),
  genero STRING OPTIONS (description = 'Genero: F o M.'),
  fecha_nacimiento DATE OPTIONS (description = 'Fecha de nacimiento. NULL si el origen no la trae.'),
  edad INT64 OPTIONS (description = 'Edad en anios cumplidos al 2026-10-31. NULL si no hay fecha de nacimiento.'),
  ciudad STRING OPTIONS (description = 'Ciudad de residencia del asociado.'),
  id_oficina STRING OPTIONS (description = 'Identificador de la oficina de vinculacion.'),
  oficina STRING OPTIONS (description = 'Nombre de la oficina de vinculacion.'),
  id_regional STRING OPTIONS (description = 'Identificador de la regional del asociado (la de su oficina).'),
  regional STRING OPTIONS (description = 'Nombre de la regional: Cali, Bogota, Medellin, Barranquilla, Bucaramanga, Eje Cafetero.'),
  segmento STRING OPTIONS (description = 'Segmento del asociado: Empleado, Independiente, Pensionado, Empresario.'),
  estado STRING OPTIONS (description = 'Estado del asociado: Activo, Retirado, Suspendido. Asociado activo = estado Activo.'),
  fecha_vinculacion DATE OPTIONS (description = 'Fecha de vinculacion a la cooperativa.'),
  antiguedad_meses INT64 OPTIONS (description = 'Meses completos entre la vinculacion y 2026-10-31 (minimo 0).'),
  canal_vinculacion STRING OPTIONS (description = 'Canal de vinculacion: Oficina, Digital, Asesor comercial, Convenio empresarial.'),
  rango_ingresos STRING OPTIONS (description = 'Rango de ingresos declarado en multiplos del salario minimo (SMMLV).'),
  plan_salud_vigente STRING OPTIONS (description = 'Plan de salud con afiliacion Activa (Plan Oro, Plata, Esencial, Familiar). NULL si no tiene afiliacion vigente.')
)
CLUSTER BY id_regional, segmento
OPTIONS (
  description = 'Dimension de asociados: un registro por asociado (deduplicado) con regional, oficina, segmento, estado, edad, antiguedad y plan de salud vigente. Sin documento, correo ni telefono.',
  labels = [('workshop', 'coomeva')]
) AS
SELECT
  a.id_asociado, a.nombre_completo, a.genero, a.fecha_nacimiento,
  DATE_DIFF(DATE '2026-10-31', a.fecha_nacimiento, YEAR) AS edad,
  a.ciudad, a.id_oficina, o.oficina, o.id_regional, r.regional,
  a.segmento, a.estado, a.fecha_vinculacion,
  GREATEST(0, DATE_DIFF(DATE '2026-10-31', a.fecha_vinculacion, MONTH)) AS antiguedad_meses,
  a.canal_vinculacion, a.rango_ingresos, s.plan AS plan_salud_vigente
FROM (
  SELECT * FROM `__PROJECT__.coop_raw.asociados`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_asociado ORDER BY fecha_vinculacion) = 1
) a
LEFT JOIN `__PROJECT__.coop_raw.oficinas` o USING (id_oficina)
LEFT JOIN `__PROJECT__.coop_raw.regionales` r USING (id_regional)
LEFT JOIN (
  SELECT id_asociado, plan FROM `__PROJECT__.coop_raw.afiliaciones_salud`
  WHERE estado = 'Activa'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_asociado ORDER BY fecha_inicio DESC) = 1
) s USING (id_asociado);

-- 2. fct_cartera_mensual ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `__PROJECT__.coop_marts.fct_cartera_mensual` (
  fecha_corte DATE OPTIONS (description = 'Ultimo dia del mes de la foto de cartera. Columna de particion.'),
  id_credito STRING OPTIONS (description = 'Identificador del credito.'),
  id_asociado STRING OPTIONS (description = 'Asociado titular del credito.'),
  id_producto STRING OPTIONS (description = 'Producto de credito.'),
  producto STRING OPTIONS (description = 'Nombre del producto de credito (consumo, libranza, vivienda, vehiculo, rotativo, educativo).'),
  linea STRING OPTIONS (description = 'Linea de negocio del producto (siempre Credito en esta tabla).'),
  id_regional STRING OPTIONS (description = 'Identificador de la regional del asociado.'),
  regional STRING OPTIONS (description = 'Regional del asociado.'),
  segmento STRING OPTIONS (description = 'Segmento del asociado: Empleado, Independiente, Pensionado, Empresario.'),
  saldo_capital NUMERIC OPTIONS (description = 'Saldo de capital en COP a la fecha de corte. Cartera total = suma de saldo_capital en una fecha_corte.'),
  cuota_mes NUMERIC OPTIONS (description = 'Cuota contractual del mes en COP.'),
  valor_pagado NUMERIC OPTIONS (description = 'Valor pagado en el mes en COP.'),
  dias_mora INT64 OPTIONS (description = 'Dias de mora a la fecha de corte.'),
  en_mora_30 BOOL OPTIONS (description = 'Verdadero si dias_mora > 30. Cartera vencida = suma de saldo_capital con en_mora_30 en una fecha_corte.'),
  en_mora_90 BOOL OPTIONS (description = 'Verdadero si dias_mora > 90. Cartera en riesgo 90 = suma de saldo_capital con en_mora_90.')
)
PARTITION BY fecha_corte
CLUSTER BY id_regional, producto
OPTIONS (
  description = 'Hecho de cartera: un registro por credito y mes (fin de mes). Incluye producto, regional y segmento. Cartera total = suma de saldo_capital por fecha_corte; cartera vencida = saldo con dias_mora > 30; ICV = cartera vencida / cartera total.',
  labels = [('workshop', 'coomeva')]
) AS
SELECT
  c.fecha_corte, c.id_credito, c.id_asociado, cr.id_producto, p.producto, p.linea,
  d.id_regional, d.regional, d.segmento,
  c.saldo_capital, c.cuota_mes, c.valor_pagado, c.dias_mora,
  c.dias_mora > 30 AS en_mora_30,
  c.dias_mora > 90 AS en_mora_90
FROM `__PROJECT__.coop_raw.cartera_mensual` c
JOIN `__PROJECT__.coop_raw.creditos` cr USING (id_credito)
JOIN `__PROJECT__.coop_raw.productos` p ON p.id_producto = cr.id_producto
LEFT JOIN `__PROJECT__.coop_marts.dim_asociado` d ON d.id_asociado = c.id_asociado;

-- 3. fct_movimientos -------------------------------------------------------------------------------
CREATE OR REPLACE TABLE `__PROJECT__.coop_marts.fct_movimientos` (
  id_movimiento STRING OPTIONS (description = 'Identificador del movimiento.'),
  id_asociado STRING OPTIONS (description = 'Asociado dueno del movimiento.'),
  id_producto STRING OPTIONS (description = 'Producto de aportes o ahorro.'),
  producto STRING OPTIONS (description = 'Nombre del producto (Aportes sociales, Ahorro a la vista, Ahorro programado, CDAT).'),
  linea STRING OPTIONS (description = 'Linea de negocio: Aportes o Ahorro.'),
  fecha_movimiento TIMESTAMP OPTIONS (description = 'Fecha y hora del movimiento (UTC). DATE(fecha_movimiento) es la columna de particion.'),
  tipo_movimiento STRING OPTIONS (description = 'Tipo: Consignacion, Retiro, Aporte mensual, Rendimiento.'),
  monto NUMERIC OPTIONS (description = 'Monto en COP, positivo (el tipo da el signo). Captaciones = suma de monto con tipo Consignacion o Aporte mensual; Retiros = suma con tipo Retiro; Captacion neta = Captaciones - Retiros.'),
  canal STRING OPTIONS (description = 'Canal: Oficina, App, Web, PSE, Debito automatico.'),
  id_regional STRING OPTIONS (description = 'Identificador de la regional del asociado.'),
  regional STRING OPTIONS (description = 'Regional del asociado.'),
  segmento STRING OPTIONS (description = 'Segmento del asociado: Empleado, Independiente, Pensionado, Empresario.')
)
PARTITION BY DATE(fecha_movimiento)
CLUSTER BY id_regional, tipo_movimiento
OPTIONS (
  description = 'Hecho de movimientos de aportes y ahorro con producto, linea, regional y segmento del asociado. Captaciones = Consignacion + Aporte mensual; Retiros = tipo Retiro; Captacion neta = Captaciones - Retiros.',
  labels = [('workshop', 'coomeva')]
) AS
SELECT
  m.id_movimiento, m.id_asociado, m.id_producto, p.producto, p.linea,
  m.fecha_movimiento, m.tipo_movimiento, m.monto, m.canal,
  d.id_regional, d.regional, d.segmento
FROM `__PROJECT__.coop_raw.movimientos_aportes_ahorro` m
JOIN `__PROJECT__.coop_raw.productos` p USING (id_producto)
LEFT JOIN `__PROJECT__.coop_marts.dim_asociado` d ON d.id_asociado = m.id_asociado;

-- 4. mv_cartera_regional_mensual -------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS `__PROJECT__.coop_marts.mv_cartera_regional_mensual`;
CREATE MATERIALIZED VIEW `__PROJECT__.coop_marts.mv_cartera_regional_mensual`
OPTIONS (
  -- Caveat: icv es un cociente de agregados; una MV incremental no lo admite, por eso es no incremental
  -- (con max_staleness). La base es estatica, asi que el resultado no cambia entre refrescos.
  allow_non_incremental_definition = TRUE,
  max_staleness = INTERVAL 1 HOUR,
  enable_refresh = TRUE,
  refresh_interval_minutes = 60,
  -- Caveat: BigQuery no admite descripciones de columna en vistas materializadas ni ALTER COLUMN sobre ellas;
  -- por eso las definiciones de cada columna viajan en la descripcion de la vista.
  description = 'Cartera por regional y mes (fin de mes). Columnas: fecha_corte = ultimo dia del mes; regional; cartera_total = suma de saldo_capital en la fecha_corte (COP); cartera_vencida = suma de saldo_capital con dias_mora > 30 (COP); icv = indice de cartera vencida = cartera_vencida / cartera_total, en fraccion (0.05 = 5%).',
  labels = [('workshop', 'coomeva')]
) AS
SELECT
  fecha_corte, regional,
  SUM(saldo_capital) AS cartera_total,
  SUM(IF(dias_mora > 30, saldo_capital, 0)) AS cartera_vencida,
  SUM(IF(dias_mora > 30, saldo_capital, 0)) / SUM(saldo_capital) AS icv
FROM `__PROJECT__.coop_marts.fct_cartera_mensual`
GROUP BY fecha_corte, regional;
