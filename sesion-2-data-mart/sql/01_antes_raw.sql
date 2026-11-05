-- Paso 1 · El "antes": la consulta del tablero de cartera sobre coop_raw
-- Ejecuta cada bloque por separado: selecciónalo en el editor y Run.
-- Antes de ejecutar: More > Query settings > desmarcar "Use cached results".
-- Mira el validador (arriba a la derecha del editor): "This query will process X".

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
