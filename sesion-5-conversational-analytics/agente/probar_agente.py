#!/usr/bin/env python3
"""Prueba el agente por la Conversational Analytics API y registra qué hizo.

    python3 -I probar_agente.py agente  "pregunta" ["otra pregunta" ...]   # conversación con el agente
    python3 -I probar_agente.py directo "pregunta" ["otra" ...]            # sin agente: solo la tabla del mart
    python3 -I probar_agente.py directo-raw "pregunta" ["otra" ...]        # sin agente: tablas crudas de coop_raw

`agente` crea una conversación con coop-cartera (contexto publicado) y hace las
preguntas en orden, en la misma conversación. `directo` es la "conversación directa
sobre la tabla" de BigQuery Studio: chat sin estado con fct_cartera_mensual como
única fuente, sin instrucciones, glosario ni verified queries.

Por cada pregunta imprime y guarda en pruebas/<marca>.json: texto final, SQL
generado o verified query usada (con sus parámetros), filas, jobs de BigQuery
con bytes facturados y labels, y segundos de punta a punta. El agente
consulta con la identidad de quien pregunta (tu sesión de gcloud).
"""
from __future__ import annotations

import datetime
import json
import sys
import pathlib
import time

# python -I no agrega la carpeta del script a sys.path; aplicar_agente.py vive al lado.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from aplicar_agente import AQUI, CFG, cargar, endpoint, nombre_agente, sesion

# Fuentes de la conversación directa: el mart (descripciones gobernadas) o el crudo.
DIRECTO = {
    "directo": [("coop_marts", "fct_cartera_mensual")],
    "directo-raw": [("coop_raw", t) for t in ("cartera_mensual", "creditos", "productos",
                                               "asociados", "oficinas", "regionales")],
}


def job_bq(s, ref: dict) -> dict:
    """Bytes facturados y labels del job que corrió el agente."""
    url = (f"https://bigquery.googleapis.com/bigquery/v2/projects/{ref['projectId']}/jobs/"
           f"{ref['jobId']}")
    r = s.get(url, params={"location": ref.get("location", CFG["bq_location"])})
    if r.status_code != 200:
        return {"jobId": ref["jobId"], "error": r.status_code}
    j = r.json()
    st = j.get("statistics", {})
    return {"jobId": ref["jobId"], "location": j["jobReference"].get("location"),
            "bytes_procesados": int(st.get("query", {}).get("totalBytesProcessed", 0)),
            "bytes_facturados": int(st.get("query", {}).get("totalBytesBilled", 0)),
            "cache": st.get("query", {}).get("cacheHit", False),
            "labels": j.get("configuration", {}).get("labels", {})}


def resumir(s, mensajes: list[dict]) -> dict:
    out = {"texto": [], "sql": [], "verified_query": [], "filas": [], "jobs": [],
           "errores": [], "grafico": False, "seguimiento": []}
    for m in mensajes:
        sm = m.get("systemMessage", {})
        d = sm.get("data", {})
        if "matchedQuery" in d:
            mq = d["matchedQuery"]
            out["verified_query"].append({
                "pregunta": mq.get("exampleQuery", {}).get("naturalLanguageQuestion"),
                "parametros": {p["name"]: p["value"] for p in mq.get("queryParameterValues", [])}})
        if "generatedSql" in d:
            out["sql"].append(d["generatedSql"])
        if "bigQueryJob" in d:
            out["jobs"].append(job_bq(s, d["bigQueryJob"]))
        if "result" in d:
            out["filas"].append(d["result"].get("data", [])[:12])
        if "chart" in sm and sm["chart"].get("result", {}).get("vegaConfig"):
            out["grafico"] = True
        if "error" in sm:
            out["errores"].append(sm["error"])
        t = sm.get("text", {})
        tipo = t.get("textType", "TEXT_TYPE_UNSPECIFIED")
        if tipo in ("FINAL_RESPONSE", "TEXT_TYPE_UNSPECIFIED") and t.get("parts"):
            out["texto"].append("".join(t["parts"]))
        if tipo == "FOLLOWUP_QUESTIONS":
            out["seguimiento"].append("".join(t.get("parts", [])))
    out["texto"] = "\n".join(out["texto"]).strip()
    return out


def imprimir(pregunta: str, r: dict) -> None:
    print(f"\n▶ {pregunta}  ({r['segundos']:.1f}s)")
    for vq in r["verified_query"]:
        print(f"  · VERIFIED QUERY: {vq['pregunta'][:90]}  {vq['parametros']}")
    for q in r["sql"]:
        print("  · SQL: " + " ".join(q.split())[:400])
    for j in r["jobs"]:
        print(f"  · JOB {j.get('jobId')} facturado {j.get('bytes_facturados', 0) / 1e6:.1f} MB "
              f"labels {j.get('labels')}")
    for f in r["filas"]:
        print(f"  · filas: {json.dumps(f, ensure_ascii=False)[:500]}")
    for e in r["errores"]:
        print("  · ERROR:", json.dumps(e, ensure_ascii=False)[:300])
    print("  respuesta:\n    " + "\n    ".join(r["texto"][:1500].splitlines()))


def main(modo: str, preguntas: list[str]) -> None:
    agente = cargar()
    padre, data_agent = nombre_agente(agente)
    api = endpoint(agente["location"])
    s = sesion()
    conv = None
    if modo == "agente":
        conv = s.post(f"{api}/{padre}/conversations", json={
            "agents": [data_agent], "labels": {"workshop": "coomeva", "origen": "probar-agente"}}).json()
        if "name" not in conv:
            sys.exit(json.dumps(conv, indent=2)[:1500])
        print("conversación:", conv["name"])
    registros = []
    for pregunta in preguntas:
        cuerpo = {"messages": [{"userMessage": {"text": pregunta}}]}
        if modo == "agente":
            cuerpo["conversationReference"] = {"conversation": conv["name"],
                                               "dataAgentContext": {"dataAgent": data_agent}}
        else:
            cuerpo["inlineContext"] = {"datasourceReferences": {"bq": {"tableReferences": [
                {"projectId": CFG["data_project"], "datasetId": ds, "tableId": t}
                for ds, t in DIRECTO[modo]]}}}
        t0 = time.monotonic()
        r = s.post(f"{api}/{padre}:chat", json=cuerpo, timeout=600)
        seg = time.monotonic() - t0
        if r.status_code != 200:
            print(f"\n▶ {pregunta}\n  ERROR {r.status_code} {r.text[:800]}")
            registros.append({"pregunta": pregunta, "error": r.status_code, "detalle": r.text[:2000]})
            continue
        res = resumir(s, r.json())
        res.update({"pregunta": pregunta, "segundos": round(seg, 1)})
        imprimir(pregunta, res)
        registros.append(res)
    carpeta = AQUI / "pruebas"
    carpeta.mkdir(exist_ok=True)
    marca = datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%SZ")
    destino = carpeta / f"{modo}_{marca}.json"
    destino.write_text(json.dumps({"modo": modo, "agente": data_agent if modo == "agente" else None,
                                   "conversacion": conv and conv["name"], "registros": registros},
                                  ensure_ascii=False, indent=2), encoding="utf-8")
    print("\nguardado:", destino)


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("agente", *DIRECTO):
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2:])
