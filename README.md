# Workshop Propel · Coomeva

Datos y guías para los ejercicios prácticos del workshop de Data Analytics del 6 de noviembre de 2026.
Todos los datos son **sintéticos**: una cooperativa ficticia, sin ninguna persona real.

<img src="assets/qr-repo.png" alt="QR del repositorio" width="220">

`https://github.com/jarcenaxmos/propel-workshop-coomeva`

## Antes de empezar

Necesitas un proyecto de Google Cloud con billing activo en el que seas **Owner** o **Editor**.
Abre **Cloud Shell** (el ícono `>_` arriba a la derecha de la consola de Google Cloud) con ese proyecto seleccionado y ejecuta:

```bash
git clone https://github.com/jarcenaxmos/propel-workshop-coomeva.git
cd propel-workshop-coomeva
gcloud config set project TU_PROYECTO      # solo si Cloud Shell no tiene tu proyecto activo
./setup.sh
```

El script te muestra el proyecto y te pide confirmación antes de crear nada. **Tarda unos 7 minutos** (medido en un proyecto nuevo), así que conviene lanzarlo al comenzar el día y seguir con la charla mientras corre.

## Qué crea `setup.sh`

Todo en la ubicación `us-east1`, con la etiqueta `workshop=coomeva`.

| Dataset | Contenido | Lo usan |
|---|---|---|
| `coop_raw` | 8 tablas "tal como llegaron" de los sistemas de origen, **sin particionar ni clusterizar** | Sesiones II, IV y V |
| `coop_marts` | `dim_asociado`, `fct_cartera_mensual`, `fct_movimientos` y `mv_cartera_regional_mensual`, ya particionadas y clusterizadas | Sesiones IV y V |
| `coop_trabajo` | Vacío: es tu espacio para los ejercicios | Sesión II |

Además habilita las APIs necesarias y crea en Knowledge Catalog el glosario `glosario-coop`, sus vínculos a columnas y un data product (sesión IV).
Si solo necesitas la sesión II, usa `./setup.sh raw`: carga únicamente `coop_raw`.

## Guías por sesión

| Sesión | Guía | Otros archivos |
|---|---|---|
| II · BigQuery: construcción del data mart | [`sesion-2-data-mart/guia.md`](sesion-2-data-mart/guia.md) | `sql/` con una consulta por paso y `sql/solucion/` por si te atrasas |
| IV · Knowledge Catalog | [`sesion-4-knowledge-catalog/guia.md`](sesion-4-knowledge-catalog/guia.md) | `reglas/` y `scripts/` |
| V · Conversational Analytics | [`sesion-5-conversational-analytics/guia.md`](sesion-5-conversational-analytics/guia.md) | `agente/` con el agente de referencia |

## Si algo falla

- **"No hay un proyecto activo"**: ejecuta `gcloud config set project TU_PROYECTO` o `PROJECT_ID=TU_PROYECTO ./setup.sh`.
- **No se pueden habilitar las APIs o crear datasets**: tu usuario necesita ser Owner o Editor del proyecto y el proyecto debe tener billing.
- **`Not found: Dataset coop_raw` en la consola**: selecciona tu proyecto y usa la ubicación `us-east1` en el editor de consultas.
- **El glosario no se creó** (los datos sí quedaron cargados): `cd sesion-4-knowledge-catalog && python3 -I scripts/kc.py glosario`.
- **Quieres repetir**: `./setup.sh` vuelve a cargar `coop_raw` y a reconstruir `coop_marts`.

## Empezar de cero y limpiar

- `./reset.sh` deja `coop_trabajo` vacío sin tocar `coop_raw` ni `coop_marts`.
- `./cleanup.sh` borra los tres datasets (pide que escribas el id del proyecto para confirmar). El glosario y el data product de la sesión IV se van si borras el proyecto.

## Uso del material

Material preparado por Axmos Technologies para este workshop. Todos los derechos reservados: puedes clonarlo y ejecutarlo para seguir el workshop, pero no se concede licencia para reutilizarlo ni redistribuirlo.
