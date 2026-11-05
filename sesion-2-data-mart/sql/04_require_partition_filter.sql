-- Paso 4 · require_partition_filter: que nadie lea toda la historia por accidente
-- En tu copia, no en coop_marts (un agente conversacional que olvida el filtro fallaría).
-- Ejecuta cada bloque por separado: selecciónalo en el editor y Run (4a falla a propósito).
ALTER TABLE `coop_trabajo.fct_cartera_mensual`
SET OPTIONS (require_partition_filter = TRUE);

-- 4a. Sin filtro de partición: debe FALLAR (y no cobra nada).
SELECT regional, SUM(saldo_capital) AS cartera_total
FROM `coop_trabajo.fct_cartera_mensual`
GROUP BY regional;

-- 4b. La trampa: hay filtro de fecha, pero dinámico (subconsulta). ¿Pasa?
SELECT regional, SUM(saldo_capital) AS cartera_total
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte = (SELECT MAX(fecha_corte) FROM `coop_raw.cartera_mensual`)
GROUP BY regional;

-- 4c. Filtro constante sobre la columna de partición: pasa y poda.
SELECT fecha_corte, regional, SUM(saldo_capital) AS cartera_total
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte >= DATE_SUB(DATE '2026-10-31', INTERVAL 11 MONTH)
GROUP BY fecha_corte, regional
ORDER BY fecha_corte, regional;

-- 4d. Parámetro de script: también cuenta como constante.
DECLARE corte DATE DEFAULT (SELECT MAX(fecha_corte) FROM `coop_raw.cartera_mensual`);
SELECT regional, SUM(saldo_capital) AS cartera_total
FROM `coop_trabajo.fct_cartera_mensual`
WHERE fecha_corte = corte
GROUP BY regional;
