-- Paso 3 · El "después": la misma pregunta sobre fct_cartera_mensual
-- Ejecuta cada bloque por separado: selecciónalo en el editor y Run.
-- Cache desactivado. Compara "This query will process" con el paso 1.

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
