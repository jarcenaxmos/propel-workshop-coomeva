#!/usr/bin/env bash
# Workshop Propel · Coomeva. Todos los derechos reservados.
# Deja coop_trabajo vacio (tus tablas de la sesion II) sin tocar coop_raw ni coop_marts.
set -euo pipefail
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
LOCATION="${LOCATION:-us-east1}"
[[ -n "${PROJECT_ID}" && "${PROJECT_ID}" != "(unset)" ]] || { echo "No hay proyecto activo."; exit 1; }
read -r -p "Se borraran TODAS las tablas de coop_trabajo en ${PROJECT_ID}. Continuar? [s/N] " r
[[ "${r}" =~ ^[sSyY]$ ]] || { echo "Cancelado."; exit 0; }
bq --project_id="${PROJECT_ID}" --location="${LOCATION}" rm -r -f -d "${PROJECT_ID}:coop_trabajo" || true
bq --project_id="${PROJECT_ID}" --location="${LOCATION}" mk --dataset --label=workshop:coomeva \
  --description="Dataset libre para tus pruebas del workshop." "${PROJECT_ID}:coop_trabajo"
echo "coop_trabajo quedo vacio."
