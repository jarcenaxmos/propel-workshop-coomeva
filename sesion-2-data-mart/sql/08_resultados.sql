-- Paso 8 · Tu tabla de resultados: bytes y tiempos de todo lo que corriste en la sesión
-- Lee tu propio historial de jobs (JOBS_BY_USER: solo tus jobs, sin permisos extra).
SELECT
  FORMAT_TIMESTAMP('%H:%M:%S', creation_time, 'America/Bogota') AS hora,
  REGEXP_EXTRACT(query, r'FROM `([^`]+)`') AS primera_tabla,
  ROUND(total_bytes_processed / POW(1024, 2), 1) AS mib_procesados,
  ROUND(total_bytes_billed / POW(1024, 2), 1) AS mib_facturados,
  TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) AS duracion_ms,
  total_slot_ms,
  cache_hit,
  bi_engine_statistics.bi_engine_mode AS bi_engine,
  error_result.reason AS error
FROM `region-us-east1`.INFORMATION_SCHEMA.JOBS_BY_USER
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)
  AND job_type = 'QUERY'
  AND statement_type = 'SELECT'
  AND query NOT LIKE '%INFORMATION_SCHEMA%'
ORDER BY creation_time;
