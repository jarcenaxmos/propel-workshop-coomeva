#!/usr/bin/env bash
# Workshop Propel · Coomeva. Todos los derechos reservados.
# Borra los tres datasets del workshop (coop_raw, coop_marts, coop_trabajo) de tu proyecto.
# El glosario y el data product de la sesion IV no se borran con este script: se van si borras el proyecto.
set -euo pipefail
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
LOCATION="${LOCATION:-us-east1}"
[[ -n "${PROJECT_ID}" && "${PROJECT_ID}" != "(unset)" ]] || { echo "No hay proyecto activo."; exit 1; }
echo "Se borraran los datasets coop_raw, coop_marts y coop_trabajo del proyecto ${PROJECT_ID}."
read -r -p "Para confirmar escribe el id del proyecto: " r
[[ "${r}" == "${PROJECT_ID}" ]] || { echo "No coincide. Cancelado."; exit 0; }
for ds in coop_raw coop_marts coop_trabajo; do
  bq --project_id="${PROJECT_ID}" --location="${LOCATION}" rm -r -f -d "${PROJECT_ID}:${ds}" || true
done
echo "Listo."
