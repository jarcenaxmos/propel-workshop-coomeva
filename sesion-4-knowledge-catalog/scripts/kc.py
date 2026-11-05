#!/usr/bin/env python3
"""Knowledge Catalog para la Sesión IV · workshop Propel Coomeva.

Uso (desde la carpeta sesion-4-knowledge-catalog; usa tu proyecto activo o PROJECT_ID):
  python3 -I scripts/kc.py glosario      # glosario + categorías + términos (idempotente)
  python3 -I scripts/kc.py vincular      # términos -> columnas de coop_marts (idempotente)
  python3 -I scripts/kc.py ver-vinculos  # lista los vínculos término -> columna
  python3 -I scripts/kc.py data-product  # data product sobre coop_marts (idempotente)
  python3 -I scripts/kc.py linaje TABLA  # links de linaje (tabla y columnas) hacia TABLA de coop_marts
  python3 -I scripts/kc.py resultados    # último job de cada scan de calidad (o solo SCAN_ID) -> markdown

La API sigue llamándose `dataplex` aunque el producto se llame Knowledge Catalog.
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PROJECT = os.environ.get("PROJECT_ID") or subprocess.check_output(
    ["gcloud", "config", "get-value", "project"], text=True, stderr=subprocess.DEVNULL).strip()
REGION = os.environ.get("LOCATION", "us-east1")
API = "https://dataplex.googleapis.com/v1"
LINEAGE_API = "https://datalineage.googleapis.com/v1"
AQUI = Path(__file__).resolve().parent
LABELS = {"workshop": "coomeva"}

_token = None
_numero = None


def token():
    global _token
    if _token is None:
        _token = subprocess.check_output(
            ["gcloud", "auth", "print-access-token"], text=True
        ).strip()
    return _token


def cuenta():
    return subprocess.check_output(
        ["gcloud", "config", "get-value", "account"], text=True, stderr=subprocess.DEVNULL).strip()


def numero_proyecto():
    global _numero
    if _numero is None:
        _numero = subprocess.check_output(
            ["gcloud", "projects", "describe", PROJECT,
             "--format=value(projectNumber)"], text=True).strip()
    return _numero


def llamar(metodo, url, cuerpo=None, ok404=False):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(url, data=datos, method=metodo, headers={
        "Authorization": f"Bearer {token()}",
        "Content-Type": "application/json",
        "x-goog-user-project": PROJECT,
    })
    try:
        with urllib.request.urlopen(req) as r:
            txt = r.read().decode()
            return r.status, (json.loads(txt) if txt else {})
    except urllib.error.HTTPError as e:
        txt = e.read().decode()
        if ok404 and e.code in (404, 409):
            return e.code, (json.loads(txt) if txt else {})
        raise SystemExit(f"[!] {metodo} {url} -> {e.code}\n{txt}")


def esperar(op):
    """Espera una long-running operation de Dataplex."""
    if op.get("done") or "name" not in op or "/operations/" not in op.get("name", ""):
        return op
    for _ in range(60):
        _, op = llamar("GET", f"{API}/{op['name']}")
        if op.get("done"):
            if "error" in op:
                raise SystemExit(f"[!] operación falló: {op['error']}")
            return op
        time.sleep(2)
    raise SystemExit(f"[!] timeout esperando {op['name']}")


def cfg():
    return json.loads((AQUI / "glosario.json").read_text())


# ---------------------------------------------------------------- glosario
def asegurar(url_recurso, url_crear, cuerpo, campos):
    """GET; si no existe, POST; si existe y difiere, PATCH de los campos."""
    st, actual = llamar("GET", url_recurso, ok404=True)
    if st == 404:
        esperar(llamar("POST", url_crear, cuerpo)[1])
        print(f"  creado      {url_recurso.split('/v1/')[1]}")
        return
    distintos = [c for c in campos if actual.get(c) != cuerpo.get(c)]
    if distintos:
        esperar(llamar("PATCH", f"{url_recurso}?update_mask={','.join(distintos)}", cuerpo)[1])
        print(f"  actualizado {url_recurso.split('/v1/')[1]} ({', '.join(distintos)})")
    else:
        print(f"  sin cambios {url_recurso.split('/v1/')[1]}")


def glosario():
    c = cfg()
    g = c["glosario"]
    base = f"{API}/projects/{PROJECT}/locations/{g['location']}"
    gname = f"projects/{PROJECT}/locations/{g['location']}/glossaries/{g['id']}"
    print(f"Glosario {gname}")
    asegurar(f"{API}/{gname}", f"{base}/glossaries?glossary_id={g['id']}",
             {"displayName": g["displayName"], "description": g["description"], "labels": LABELS},
             ["displayName", "description", "labels"])
    for cat in c["categorias"]:
        asegurar(f"{API}/{gname}/categories/{cat['id']}",
                 f"{API}/{gname}/categories?category_id={cat['id']}",
                 {"displayName": cat["displayName"], "description": cat["description"],
                  "parent": gname, "labels": LABELS},
                 ["displayName", "description", "labels"])
    for t in c["terminos"]:
        asegurar(f"{API}/{gname}/terms/{t['id']}",
                 f"{API}/{gname}/terms?term_id={t['id']}",
                 {"displayName": t["displayName"], "description": t["description"],
                  "parent": f"{gname}/categories/{t['categoria']}", "labels": LABELS},
                 ["displayName", "description", "labels"])


# ---------------------------------------------------------------- vínculos
def entrada_bq(dataset, tabla):
    n = numero_proyecto()
    return (f"projects/{n}/locations/{REGION}/entryGroups/@bigquery/entries/"
            f"bigquery.googleapis.com/projects/{PROJECT}/datasets/{dataset}/tables/{tabla}")


def entrada_termino(term_id):
    g = cfg()["glosario"]
    n = numero_proyecto()
    loc = g["location"]
    return (f"projects/{n}/locations/{loc}/entryGroups/@dataplex/entries/"
            f"projects/{n}/locations/{loc}/glossaries/{g['id']}/terms/{term_id}")


def vincular():
    n = numero_proyecto()
    padre = f"{API}/projects/{n}/locations/{REGION}/entryGroups/@bigquery/entryLinks"
    for v in cfg()["vinculos"]:
        link_id = f"def-{v['tabla']}-{v['columna']}-{v['termino']}".replace("_", "-")[:63].rstrip("-")
        cuerpo = {
            "entryLinkType": "projects/dataplex-types/locations/global/entryLinkTypes/definition",
            "entryReferences": [
                {"name": entrada_bq(v["dataset"], v["tabla"]), "path": f"Schema.{v['columna']}", "type": "SOURCE"},
                {"name": entrada_termino(v["termino"]), "type": "TARGET"},
            ],
        }
        st, _ = llamar("POST", f"{padre}?entry_link_id={link_id}", cuerpo, ok404=True)
        estado = "ya existía" if st == 409 else "creado"
        print(f"  {estado:10} {v['dataset']}.{v['tabla']}.{v['columna']} -> {v['termino']}")


def ver_vinculos():
    """Lista columna -> término. lookupEntryLinks es GET, sobre la entrada de la tabla (modo SOURCE)."""
    n = numero_proyecto()
    tablas = sorted({(v["dataset"], v["tabla"]) for v in cfg()["vinculos"]})
    for ds, t in tablas:
        url = (f"{API}/projects/{n}/locations/{REGION}:lookupEntryLinks?"
               + urllib.parse.urlencode({"entry": entrada_bq(ds, t), "entryMode": "SOURCE"}))
        _, r = llamar("GET", url)
        for el in r.get("entryLinks", []):
            col = term = ""
            for ref in el.get("entryReferences", []):
                if ref.get("type") == "SOURCE":
                    col = ref.get("path", "").replace("Schema.", "")
                else:
                    term = ref["name"].split("/terms/")[-1]
            print(f"{ds}.{t}.{col} -> {term}")


# ---------------------------------------------------------------- data product
def data_product():
    dp = cfg().get("data_product")
    if not dp:
        raise SystemExit("[!] falta 'data_product' en glosario.json")
    base = f"{API}/projects/{PROJECT}/locations/{REGION}/dataProducts"
    url = f"{base}/{dp['id']}"
    st, _ = llamar("GET", url, ok404=True)
    if st == 404:
        cuerpo = {"displayName": dp["displayName"], "description": dp["description"],
                  "ownerEmails": dp["ownerEmails"] or [cuenta()], "labels": LABELS}
        esperar(llamar("POST", f"{base}?data_product_id={dp['id']}", cuerpo)[1])
        print(f"  creado      {url.split('/v1/')[1]}")
    else:
        print(f"  ya existía  {url.split('/v1/')[1]}")
    for tabla in dp["tablas"]:
        aid = tabla.replace("_", "-")
        st, _ = llamar("GET", f"{url}/dataAssets/{aid}", ok404=True)
        if st == 404:
            res = f"//bigquery.googleapis.com/projects/{PROJECT}/datasets/{dp['dataset']}/tables/{tabla}"
            esperar(llamar("POST", f"{url}/dataAssets?data_asset_id={aid}", {"resource": res})[1])
            print(f"  asset       {tabla}")
        else:
            print(f"  asset ok    {tabla}")


# ---------------------------------------------------------------- linaje
def linaje(tabla):
    fqn = f"bigquery:{PROJECT}.coop_marts.{tabla}"
    url = f"{LINEAGE_API}/projects/{PROJECT}/locations/{REGION}:searchLinks"
    _, r = llamar("POST", url, {"target": {"fullyQualifiedName": fqn}, "pageSize": 100})
    links = r.get("links", [])
    print(f"Links hacia {fqn}: {len(links)}")
    for l in links:
        s, t = l["source"], l["target"]
        sf = s.get("field", [])
        tf = t.get("field", [])
        print(f"  {s['fullyQualifiedName']}{'.' + ','.join(sf) if sf else ''}  ->  "
              f"{t['fullyQualifiedName']}{'.' + ','.join(tf) if tf else ''}")


# ---------------------------------------------------------------- resultados
def resultados(solo=None):
    _, r = llamar("GET", f"{API}/projects/{PROJECT}/locations/{REGION}/dataScans?pageSize=100")
    for s in r.get("dataScans", []):
        if s.get("type") != "DATA_QUALITY" or s.get("labels", {}).get("workshop") != "coomeva":
            continue
        sid = s["name"].split("/")[-1]
        if solo and sid != solo:
            continue
        _, jobs = llamar("GET", f"{API}/{s['name']}/jobs?pageSize=1")
        if not jobs.get("dataScanJobs"):
            print(f"## {sid}\n(sin jobs)\n")
            continue
        _, job = llamar("GET", f"{API}/{jobs['dataScanJobs'][0]['name']}?view=FULL")
        dq = job.get("dataQualityResult", {})
        print(f"## {sid} · job {job['name'].split('/')[-1]} · {job.get('state')} · "
              f"{job.get('endTime', '')}")
        print(f"Tabla: {s['data'].get('resource', '')}")
        print(f"Score: {dq.get('score')} · filas={dq.get('rowCount')} · "
              f"publicación en catálogo: {dq.get('catalogPublishingStatus', {}).get('state')}")
        dims = ", ".join(f"{d['dimension']['name']}={d.get('score')}" for d in dq.get("dimensions", []))
        print(f"Score por dimensión: {dims}\n")
        print("| Regla | Dimensión | Columna | Pasa | Evaluadas | Fallan | % OK |")
        print("|---|---|---|---|---|---|---|")
        for rr in dq.get("rules", []):
            rule = rr["rule"]
            ev = rr.get("evaluatedCount", "")
            if "passedCount" in rr:          # regla por fila (o uniqueness)
                falla = int(ev) - int(rr["passedCount"])
            elif "assertionRowCount" in rr:  # sqlAssertion: filas devueltas
                falla = f"{rr['assertionRowCount']} filas devueltas"
            else:                            # condición de tabla
                falla = "—"
            pct = rr.get("passRatio")
            pct = f"{float(pct) * 100:.4f}%" if pct is not None else "—"
            print(f"| {rule.get('name', '')} | {rule.get('dimension', '')} | {rule.get('column', '—')} | "
                  f"{'sí' if rr.get('passed') else 'NO'} | {ev or '—'} | {falla} | {pct} |")
        print()


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "glosario":
        glosario()
    elif cmd == "vincular":
        vincular()
    elif cmd == "ver-vinculos":
        ver_vinculos()
    elif cmd == "data-product":
        data_product()
    elif cmd == "linaje":
        linaje(sys.argv[2] if len(sys.argv) > 2 else "fct_cartera_mensual")
    elif cmd == "resultados":
        resultados(sys.argv[2] if len(sys.argv) > 2 else None)
    else:
        print(__doc__)
