#!/usr/bin/env python3
"""Valida y aplica el agente de Conversational Analytics definido en agente.yaml.

    python3 -I aplicar_agente.py validar      # corre cada verified query en BigQuery (dry run + ejecución)
    python3 -I aplicar_agente.py aplicar      # crea o actualiza el agente (staging = publicado)
    python3 -I aplicar_agente.py verificar    # compara el agente vivo con agente.yaml
    python3 -I aplicar_agente.py respaldar    # guarda el agente vivo en respaldos/ (JSON)

Un solo ambiente (workshop): tu proyecto activo (o PROJECT_ID), datos en coop_marts.
Usa el token de tu sesión de gcloud (gcloud auth print-access-token).
- Ubicación `us`: los datos están en us-east1, que no es una ubicación de CA, y la regla de
  la documentación manda fuentes en regiones de EE. UU. al multirregión US. El endpoint
  de `us` es el regional geminidataanalytics.us.rep.googleapis.com.

Uso típico:
    uv run --with google-cloud-bigquery --with pyyaml --with requests \
        python -I aplicar_agente.py validar
"""
from __future__ import annotations

import datetime
import json
import os
import pathlib
import re
import subprocess
import sys

import requests
import yaml

AQUI = pathlib.Path(__file__).resolve().parent

PROYECTO = os.environ.get("PROJECT_ID") or subprocess.check_output(
    ["gcloud", "config", "get-value", "project"], text=True, stderr=subprocess.DEVNULL).strip()

CFG = {
    "agent_project": PROYECTO,
    "data_project": PROYECTO,
    "dataset": "coop_marts",
    "bq_location": "us-east1",
}

# Valores para probar las verified queries con parámetros (validar).
EJEMPLOS = {
    "mes": "2026-10",
    "fecha_desde": datetime.date(2026, 1, 1),
    "fecha_hasta": datetime.date(2026, 10, 31),
}


def endpoint(location: str) -> str:
    if location == "global":
        return "https://geminidataanalytics.googleapis.com/v1"
    return f"https://geminidataanalytics.{location}.rep.googleapis.com/v1"


def token() -> str:
    return subprocess.run(
        ["gcloud", "auth", "print-access-token"],
        check=True, capture_output=True, text=True).stdout.strip()


def sesion() -> requests.Session:
    s = requests.Session()
    s.headers.update({"Authorization": f"Bearer {token()}",
                      "x-goog-user-project": CFG["agent_project"],
                      "Content-Type": "application/json"})
    return s


def cargar() -> dict:
    texto = (AQUI / "agente.yaml").read_text(encoding="utf-8")
    texto = re.sub(r"\{\{t:([\w.]+)\}\}",
                   lambda m: f"`{CFG['data_project']}.{ref_tabla(m.group(1))[0]}.{ref_tabla(m.group(1))[1]}`",
                   texto)
    return yaml.safe_load(texto)


def ref_tabla(nombre: str) -> tuple[str, str]:
    """'tabla' -> (coop_marts, tabla); 'dataset.tabla' -> (dataset, tabla)."""
    return tuple(nombre.split(".", 1)) if "." in nombre else (CFG["dataset"], nombre)


def nombre_agente(agente: dict) -> tuple[str, str]:
    padre = f"projects/{CFG['agent_project']}/locations/{agente['location']}"
    return padre, f"{padre}/dataAgents/{agente['agent_id']}"


def contexto(agente: dict) -> dict:
    ctx = {
        "systemInstruction": agente["system_instruction"],
        "datasourceReferences": {"bq": {"tableReferences": [
            {"projectId": CFG["data_project"], "datasetId": ref_tabla(t)[0], "tableId": ref_tabla(t)[1]}
            for t in agente["tables"]]}},
        "exampleQueries": [
            {"naturalLanguageQuestion": q["question"], "sqlQuery": q["sql"].strip(),
             **({"parameters": [{"name": p["name"], "dataType": p["type"],
                                 "description": p.get("description", "")}
                                for p in q["parameters"]]} if q.get("parameters") else {})}
            for q in agente["verified_queries"]],
        "options": {"datasource": {"bigQueryMaxBilledBytes": str(agente["max_bytes_por_consulta"])}},
    }
    # Intent: si el glosario vive en Knowledge Catalog (sesión IV), el agente lo importa solo
    # desde las columnas de sus tablas; no se duplica acá (la doc lo desaconseja).
    if agente.get("glossary"):
        ctx["glossaryTerms"] = [
            {"displayName": g["term"], "description": g["description"], "labels": g.get("labels", [])}
            for g in agente["glossary"]]
    return ctx


def validar() -> None:
    from google.cloud import bigquery
    from google.oauth2.credentials import Credentials
    agente = cargar()
    bq = bigquery.Client(project=CFG["agent_project"], location=CFG["bq_location"],
                         credentials=Credentials(token()))
    for q in agente["verified_queries"]:
        params = []
        for p in q.get("parameters", []):
            params.append(bigquery.ScalarQueryParameter(p["name"], p["type"], EJEMPLOS[p["name"]]))
        cfg = bigquery.QueryJobConfig(query_parameters=params, labels={"workshop": "coomeva"},
                                      maximum_bytes_billed=int(agente["max_bytes_por_consulta"]))
        try:
            seco = bq.query(q["sql"], job_config=bigquery.QueryJobConfig(
                query_parameters=params, dry_run=True, use_query_cache=False))
            job = bq.query(q["sql"], job_config=cfg)
            filas = list(job.result())
            print(f"OK   {len(filas):4d} filas  dry-run {seco.total_bytes_processed / 1e6:8.1f} MB"
                  f"  facturado {(job.total_bytes_billed or 0) / 1e6:8.1f} MB  {q['question'][:60]}")
            for f in filas[:3]:
                print(f"       {json.dumps(dict(f), default=str, ensure_ascii=False)[:200]}")
        except Exception as e:  # pylint: disable=broad-except
            print(f"ERR  {q['question'][:70]}\n       {str(e)[:400]}")


def aplicar() -> None:
    agente = cargar()
    padre, nombre = nombre_agente(agente)
    ctx = contexto(agente)
    cuerpo = {"displayName": agente["display_name"], "description": agente["description"].strip(),
              "labels": {"workshop": "coomeva"},
              "dataAnalyticsAgent": {"stagingContext": ctx, "publishedContext": ctx}}
    mask = ("displayName,description,labels,dataAnalyticsAgent.stagingContext,"
            "dataAnalyticsAgent.publishedContext")
    api = endpoint(agente["location"])
    s = sesion()
    existe = s.get(f"{api}/{nombre}").status_code == 200
    if existe:
        r = s.patch(f"{api}/{nombre}:updateSync", json=cuerpo, params={"updateMask": mask})
    else:
        r = s.post(f"{api}/{padre}/dataAgents:createSync", json=cuerpo,
                   params={"dataAgentId": agente["agent_id"]})
    print(("actualizado" if existe else "creado"), r.status_code)
    if r.status_code >= 300:
        print(r.text[:2000])
        sys.exit(1)
    print(nombre)


def vivo() -> tuple[dict, dict]:
    agente = cargar()
    _, nombre = nombre_agente(agente)
    r = sesion().get(f"{endpoint(agente['location'])}/{nombre}")
    if r.status_code != 200:
        sys.exit(f"No se pudo leer el agente ({r.status_code}): {r.text[:300]}")
    return agente, r.json()


def verificar() -> None:
    """Detecta ediciones hechas fuera del repo (p. ej. en BigQuery Studio)."""
    agente, actual = vivo()
    esperado = contexto(agente)
    partes = {
        "instrucciones": lambda c: c.get("systemInstruction", "").strip(),
        "tablas": lambda c: sorted(t["tableId"] for t in c.get("datasourceReferences", {}).get("bq", {}).get("tableReferences", [])),
        "glosario": lambda c: sorted((g["displayName"], g["description"]) for g in c.get("glossaryTerms", [])),
        "verified queries": lambda c: sorted((q["naturalLanguageQuestion"], q["sqlQuery"].strip()) for q in c.get("exampleQueries", [])),
        "tope por consulta": lambda c: c.get("options", {}).get("datasource", {}).get("bigQueryMaxBilledBytes"),
    }
    diferencias = 0
    for version in ("publishedContext", "stagingContext"):
        ctx = actual.get("dataAnalyticsAgent", {}).get(version, {})
        for parte, f in partes.items():
            if f(ctx) != f(esperado):
                diferencias += 1
                print(f"DIFERENTE  {version:16s} {parte}")
    print("Sin diferencias con agente.yaml." if not diferencias else
          f"{diferencias} diferencia(s). Revisar con 'respaldar' y restaurar con 'aplicar'.")
    print(f"Última actualización del agente: {actual.get('updateTime')}")
    sys.exit(1 if diferencias else 0)


def respaldar() -> None:
    _, actual = vivo()
    carpeta = AQUI / "respaldos"
    carpeta.mkdir(exist_ok=True)
    marca = datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%SZ")
    destino = carpeta / f"{actual['name'].split('/')[-1]}_{marca}.json"
    destino.write_text(json.dumps(actual, ensure_ascii=False, indent=2), encoding="utf-8")
    print(destino)


if __name__ == "__main__":
    COMANDOS = {"validar": validar, "aplicar": aplicar, "verificar": verificar, "respaldar": respaldar}
    if len(sys.argv) != 2 or sys.argv[1] not in COMANDOS:
        sys.exit(__doc__)
    COMANDOS[sys.argv[1]]()
