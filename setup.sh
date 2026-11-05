#!/usr/bin/env bash
# Workshop Propel · Coomeva. Todos los derechos reservados.
#
# Carga los datos de practica en TU proyecto de Google Cloud.
#   ./setup.sh             coop_raw + coop_marts + glosario (sesiones II, IV y V)
#   ./setup.sh raw         solo coop_raw (sesion II)
#   ./setup.sh --yes       sin pedir confirmacion
#   ./setup.sh --dry-run   muestra lo que haria, sin ejecutar nada
# Variables opcionales: PROJECT_ID (por defecto, tu proyecto activo) y LOCATION (por defecto us-east1).
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
MODO="all"; SI=0; SECO=0
for a in "$@"; do
  case "$a" in
    raw|all) MODO="$a" ;;
    --yes|-y) SI=1 ;;
    --dry-run) SECO=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Opcion desconocida: $a (usa --help)"; exit 1 ;;
  esac
done

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
LOCATION="${LOCATION:-us-east1}"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "No hay un proyecto activo."
  echo "Ejecuta: gcloud config set project TU_PROYECTO   (o: PROJECT_ID=TU_PROYECTO ./setup.sh)"
  exit 1
fi
export PROJECT_ID LOCATION

echo "Proyecto: ${PROJECT_ID}   Ubicacion: ${LOCATION}   Modo: ${MODO}"
if (( ! SI && ! SECO )); then
  read -r -p "Se crearan los datasets coop_raw, coop_marts y coop_trabajo en ese proyecto. Continuar? [s/N] " r
  [[ "${r}" =~ ^[sSyY]$ ]] || { echo "Cancelado."; exit 0; }
fi

run() { if (( SECO )); then echo "[dry-run] $*"; else "$@"; fi; }
bqx() { run bq --project_id="${PROJECT_ID}" --location="${LOCATION}" "$@"; }

echo "== APIs"
run gcloud services enable bigquery.googleapis.com bigquerystorage.googleapis.com \
  dataplex.googleapis.com datalineage.googleapis.com geminidataanalytics.googleapis.com \
  cloudaicompanion.googleapis.com aiplatform.googleapis.com --project="${PROJECT_ID}" \
  || echo "[!] No se pudieron habilitar todas las APIs. Revisa que seas Owner o Editor del proyecto y que tenga billing."

echo "== Datasets"
for ds in coop_raw coop_marts coop_trabajo; do
  if (( ! SECO )) && bq --project_id="${PROJECT_ID}" show --dataset "${PROJECT_ID}:${ds}" >/dev/null 2>&1; then
    echo "dataset ${ds}: ya existe"
  else
    bqx mk --dataset --label=workshop:coomeva \
      --description="Workshop Propel Coomeva (datos sinteticos): ${ds}" "${PROJECT_ID}:${ds}"
  fi
done
bqx update --description="Fuentes crudas tal como llegaron de on-premise y Azure. Sin particionar ni clusterizar a proposito." "${PROJECT_ID}:coop_raw"
bqx update --description="Marts de referencia (particionados y clusterizados) construidos desde coop_raw." "${PROJECT_ID}:coop_marts"
bqx update --description="Dataset libre para tus pruebas del workshop." "${PROJECT_ID}:coop_trabajo"

echo "== coop_raw"
DATA="${AQUI}/data"
for t in regionales oficinas asociados productos movimientos_aportes_ahorro creditos cartera_mensual afiliaciones_salud; do
  echo "-- ${t}"
  # La tabla se recrea para que el script se pueda repetir y quede con descripciones, sin PARTITION ni CLUSTER.
  bqx rm -f -t "${PROJECT_ID}:coop_raw.${t}" || true
  bqx mk --table --label=workshop:coomeva --description="$(cat "${DATA}/descripciones/${t}.txt")" \
    "${PROJECT_ID}:coop_raw.${t}" "${DATA}/schemas/${t}.json"
  # El upload local a veces falla con BrokenPipe: se reintenta una vez.
  bqx --quiet load --source_format=PARQUET --replace "${PROJECT_ID}:coop_raw.${t}" "${DATA}/${t}.parquet" \
    || bqx --quiet load --source_format=PARQUET --replace "${PROJECT_ID}:coop_raw.${t}" "${DATA}/${t}.parquet"
  # load --replace pisa el esquema con el del Parquet y pierde las descripciones: se reaplican.
  bqx --quiet update "${PROJECT_ID}:coop_raw.${t}" "${DATA}/schemas/${t}.json"
done

if [[ "${MODO}" == "all" ]]; then
  echo "== coop_marts"
  if (( SECO )); then
    echo "[dry-run] ejecutar sql/marts.sql con el proyecto ${PROJECT_ID}"
  else
    sed "s/__PROJECT__/${PROJECT_ID}/g" "${AQUI}/sql/marts.sql" \
      | bq --project_id="${PROJECT_ID}" --location="${LOCATION}" query --use_legacy_sql=false --nouse_cache
  fi
  echo "== Reglas de calidad (sesion IV)"
  REG="${AQUI}/sesion-4-knowledge-catalog/reglas"
  for f in "${REG}"/plantillas/*.yaml.tpl; do
    sed "s/__PROJECT__/${PROJECT_ID}/g" "${f}" > "${REG}/$(basename "${f}" .tpl)"
    echo "generada: reglas/$(basename "${f}" .tpl)"
  done
  echo "== Glosario y data product (sesion IV)"
  ( cd "${AQUI}/sesion-4-knowledge-catalog" \
    && run python3 -I scripts/kc.py glosario \
    && run python3 -I scripts/kc.py vincular \
    && run python3 -I scripts/kc.py data-product ) \
    || echo "[!] El glosario no se pudo crear (los datos si estan cargados). Puedes reintentar: cd sesion-4-knowledge-catalog && python3 -I scripts/kc.py glosario"
fi

echo "== Verificacion"
if (( SECO )); then echo "[dry-run] conteos de filas"; else
  bq --project_id="${PROJECT_ID}" --location="${LOCATION}" query --use_legacy_sql=false --format=pretty "
    SELECT 'asociados' AS tabla, COUNT(*) AS filas FROM \`${PROJECT_ID}.coop_raw.asociados\`
    UNION ALL SELECT 'creditos', COUNT(*) FROM \`${PROJECT_ID}.coop_raw.creditos\`
    UNION ALL SELECT 'cartera_mensual', COUNT(*) FROM \`${PROJECT_ID}.coop_raw.cartera_mensual\`
    UNION ALL SELECT 'movimientos_aportes_ahorro', COUNT(*) FROM \`${PROJECT_ID}.coop_raw.movimientos_aportes_ahorro\`
    UNION ALL SELECT 'afiliaciones_salud', COUNT(*) FROM \`${PROJECT_ID}.coop_raw.afiliaciones_salud\`"
fi
echo
echo "Listo. Abre BigQuery Studio en el proyecto ${PROJECT_ID} y sigue la guia de tu sesion."
