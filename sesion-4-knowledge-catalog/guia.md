# Guía del participante · Sesión IV · Knowledge Catalog

Viernes 6-nov-2026, 13:30 a 14:30. 25 min de charla y 35 min de hands-on sobre el data mart (`coop_marts`) y las fuentes (`coop_raw`).
Idea de la sesión: un dato que se ve bien no es un dato confiable. Confiable es lo que está **definido** (glosario), **trazado** (linaje) y **medido** (calidad). Eso es lo que hereda el agente de la sesión V.

> Nombres: el producto se llama **Knowledge Catalog** (antes Dataplex Universal Catalog). La API, `gcloud` e IAM siguen diciendo `dataplex`.
> Los comandos usan tu proyecto activo de Cloud Shell a través de la variable `PROJECT_ID` (paso 0).

## Lo que hace cada participante

Cada paso: qué hacer, el comando y qué deberías ver. Tiempo total: unos 32 minutos.

### Paso 0 · Preparar la terminal (1 min)

En Cloud Shell, con tu proyecto seleccionado:

```bash
cd ~/propel-workshop-coomeva/sesion-4-knowledge-catalog
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
echo "proyecto=${PROJECT_ID} número=${PROJECT_NUMBER}"
bash scripts/scans.sh
```

Deberías ver tu proyecto y su número (no vacíos), y luego `· creo dq-asociados` … `· ejecuto perfil-movimientos`. Esos 4 scans de referencia tardan 1 a 3 minutos en terminar; los lees en el paso 5.
Si `proyecto=` sale vacío: `gcloud config set project TU_PROYECTO` y repite. Si abres otra pestaña de Cloud Shell, vuelve a correr las dos líneas `export`.

### Paso 1 · Buscar el mart en el catálogo (6 min)

Consola: BigQuery, Knowledge Catalog, Search. Escribe `cartera vencida`. O por terminal:

```bash
gcloud dataplex entries search "cartera vencida" \
  --project=${PROJECT_ID} --limit=6 \
  --format="table(entrySource.displayName,entrySource.system,fullyQualifiedName)"
```

Deberías ver: `mv_cartera_regional_mensual` y `fct_cartera_mensual` (sistema `BIGQUERY`) y los términos del glosario "Cartera vencida" e "Índice de cartera vencida (ICV)" (sistema `DATAPLEX`). La búsqueda recorre todo lo que tu cuenta puede ver, así que pueden aparecer entradas de otros proyectos.
Si sale `RESOURCE_PROJECT_INVALID`: `PROJECT_ID` está vacía, vuelve al paso 0. Este comando no acepta `--location`.

### Paso 2 · Linaje de `fct_cartera_mensual` (6 min)

Consola: abre la entrada `fct_cartera_mensual`, pestaña **Lineage**. O por API:

```bash
curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: ${PROJECT_ID}" -H "Content-Type: application/json" \
  "https://datalineage.googleapis.com/v1/projects/${PROJECT_ID}/locations/us-east1:searchLinks" \
  -d "{\"target\":{\"fullyQualifiedName\":\"bigquery:${PROJECT_ID}.coop_marts.fct_cartera_mensual\"}}"
```

Deberías ver 4 orígenes: `coop_raw.cartera_mensual`, `coop_raw.creditos`, `coop_raw.productos` y `coop_marts.dim_asociado`. Aguas abajo, `mv_cartera_regional_mensual`. Con el campo `target.field` (por ejemplo `["saldo_capital"]`) ves el linaje por columna.
Si la lista sale vacía: el linaje solo existe para tablas creadas por jobs de BigQuery.

### Paso 3 · Términos del glosario vinculados a columnas (6 min)

Consola: Knowledge Catalog, Glossaries, `glosario-coop`, término "Cartera vencida". O por API (usa el número de proyecto del paso 0):

```bash
ENTRY=projects/${PROJECT_NUMBER}/locations/us-east1/entryGroups/@bigquery/entries
ENTRY=$ENTRY/bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/coop_marts/tables/fct_cartera_mensual
curl -s -G -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://dataplex.googleapis.com/v1/projects/${PROJECT_NUMBER}/locations/us-east1:lookupEntryLinks" \
  --data-urlencode "entryMode=SOURCE" --data-urlencode "entry=$ENTRY"
```

Deberías ver: `Schema.saldo_capital` con Cartera total, `Schema.en_mora_30` con Cartera vencida y `Schema.en_mora_90` con Cartera en riesgo 90.

Mapa completo término a columna:

| Término | Columna |
|---|---|
| Asociado activo | `coop_marts.dim_asociado.estado` |
| Afiliado de salud vigente | `coop_marts.dim_asociado.plan_salud_vigente` |
| Cartera total | `coop_marts.fct_cartera_mensual.saldo_capital`, `coop_marts.mv_cartera_regional_mensual.cartera_total` |
| Cartera vencida | `coop_marts.fct_cartera_mensual.en_mora_30`, `coop_marts.mv_cartera_regional_mensual.cartera_vencida` |
| Índice de cartera vencida (ICV) | `coop_marts.mv_cartera_regional_mensual.icv` |
| Cartera en riesgo 90 | `coop_marts.fct_cartera_mensual.en_mora_90` |
| Captaciones, Retiros, Captación neta | `coop_marts.fct_movimientos.monto` |
| Desembolsos | `coop_raw.creditos.monto_desembolsado` |

Opcional (si tu cuenta puede editar): en la consola, vincula un término a otra columna desde la pestaña de la tabla.

### Paso 4 · Crear un scan de calidad sobre `coop_raw.asociados` (8 min)

Usa el archivo `reglas/dq-asociados.yaml` (lo genera `setup.sh` con tu proyecto; 10 reglas: completitud, validez, unicidad, consistencia y volumen).

```bash
gcloud dataplex datascans create data-quality dq-asociados-<tu_id> \
  --project=${PROJECT_ID} --location=us-east1 \
  --data-source-resource=//bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/coop_raw/tables/asociados \
  --data-quality-spec-file=reglas/dq-asociados.yaml --labels=workshop=coomeva
gcloud dataplex datascans run dq-asociados-<tu_id> \
  --project=${PROJECT_ID} --location=us-east1
```

Deberías ver `state: ACTIVE` al crear y el nombre de un job al correr. El job tarda 1 a 3 minutos: mientras tanto, lee el paso 5 sobre el scan de referencia.
Si falla: `ALREADY_EXISTS`, cambia `<tu_id>`; `PERMISSION_DENIED`, tu cuenta no puede crear scans (usa `dq-asociados`, el que creó el paso 0).

### Paso 5 · Leer lo que encontró el scan (6 min)

Consola: BigQuery, `coop_raw.asociados`, pestaña **Data quality**. O por terminal (scan de referencia `dq-asociados` del paso 0, o el tuyo):

```bash
gcloud dataplex datascans jobs list --datascan=dq-asociados \
  --project=${PROJECT_ID} --location=us-east1 --limit=1 \
  --format="value(name.basename())"
gcloud dataplex datascans jobs describe <job_id> --datascan=dq-asociados --view=FULL \
  --project=${PROJECT_ID} --location=us-east1 \
  --format="value(dataQualityResult.score)"
```

Deberías ver score **50** y 5 reglas que fallan: 600 fechas de nacimiento nulas, 180 emails inválidos, 20 `id_asociado` repetidos, 10 vinculaciones con fecha futura. Y en `coop_raw.movimientos_aportes_ahorro` (scan `dq-movimientos`, score 88,89): 50 montos negativos. El detalle está en `resultados.md`.
Pregunta para cerrar: ¿qué tabla le daríamos al agente de las 14:30, `coop_raw.asociados` o `coop_marts.dim_asociado`?

### Si da el tiempo · Data product

Consola: Knowledge Catalog, Data products, `Cartera y captaciones · Coop (workshop)`. Mira los 4 assets (los objetos de `coop_marts`); `setup.sh` lo creó en tu proyecto.

## Para llevarte

- Un glosario con una sola definición de "cartera vencida" evita dos tableros con dos números.
- El linaje responde "¿de dónde sale?" y "¿qué se rompe si cambio esto?".
- Las reglas de calidad son un archivo en el repo: se revisan y se versionan como el SQL.
