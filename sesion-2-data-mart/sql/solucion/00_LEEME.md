# Solución completa · Sesión II

Si te atrasas, esta carpeta construye el mart entero en `coop_trabajo`. Ejecuta los archivos **en este orden** en BigQuery Studio, con tu proyecto seleccionado y la ubicación `us-east1`:

1. `01_dim_asociado.sql` (no es un paso del hands-on, pero completa el mart)
2. `02_fct_cartera_mensual.sql`
3. `03_fct_movimientos.sql`
4. `04_mv_cartera_regional_mensual.sql`
5. `05_require_partition_filter.sql` (activa el filtro obligatorio de partición en tus copias)

Crean las tablas con `CREATE OR REPLACE`, así que sobrescriben las que hayas hecho tú en `coop_trabajo`.
