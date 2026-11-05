#!/usr/bin/env bash
# Crea (o actualiza) y ejecuta los scans de calidad y de perfil de la Sesión IV.
# Idempotente: si el scan existe, actualiza su spec desde reglas/ y lo vuelve a correr.
# Uso (desde sesion-4-knowledge-catalog):  bash scripts/scans.sh [--sin-ejecutar]
# Usa tu proyecto activo (o PROJECT_ID). Respaldo por si tu propio scan no corre.
set -euo pipefail

readonly PROYECTO="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
readonly REGION="${LOCATION:-us-east1}"
readonly AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly G=(--project="${PROYECTO}" --location="${REGION}")
EJECUTAR=1
[[ "${1:-}" == "--sin-ejecutar" ]] && EJECUTAR=0

tabla() { echo "//bigquery.googleapis.com/projects/${PROYECTO}/datasets/coop_raw/tables/$1"; }

existe() { gcloud dataplex datascans describe "$1" "${G[@]}" --format="value(name)" >/dev/null 2>&1; }

dq() {  # dq <scan_id> <tabla> <archivo_reglas>
  local id="$1" t="$2" spec="${AQUI}/reglas/$3"
  if existe "${id}"; then
    echo "· actualizo ${id}"
    gcloud dataplex datascans update data-quality "${id}" "${G[@]}" \
      --data-quality-spec-file="${spec}" --labels=workshop=coomeva --quiet
  else
    echo "· creo ${id}"
    gcloud dataplex datascans create data-quality "${id}" "${G[@]}" \
      --data-source-resource="$(tabla "${t}")" --data-quality-spec-file="${spec}" \
      --display-name="DQ ${t}" --description="Reglas de calidad (Sesión IV, workshop Coomeva) sobre coop_raw.${t}" \
      --labels=workshop=coomeva --quiet
  fi
}

perfil() {  # perfil <scan_id> <tabla>
  local id="$1" t="$2"
  if existe "${id}"; then
    echo "· ${id} ya existe"
  else
    echo "· creo ${id}"
    gcloud dataplex datascans create data-profile "${id}" "${G[@]}" \
      --data-source-resource="$(tabla "${t}")" --data-profile-spec-file="${AQUI}/reglas/perfil.yaml" \
      --display-name="Perfil ${t}" --description="Data profile (Sesión IV, workshop Coomeva) de coop_raw.${t}" \
      --labels=workshop=coomeva --quiet
  fi
}

dq dq-asociados asociados dq-asociados.yaml
dq dq-movimientos movimientos_aportes_ahorro dq-movimientos.yaml
perfil perfil-asociados asociados
perfil perfil-movimientos movimientos_aportes_ahorro

if (( EJECUTAR )); then
  for id in dq-asociados dq-movimientos perfil-asociados perfil-movimientos; do
    echo "· ejecuto ${id}"
    gcloud dataplex datascans run "${id}" "${G[@]}" --format="value(job.name)"
  done
  echo "Resultados: python3 -I scripts/kc.py resultados  (los jobs tardan 1–3 min)"
fi
