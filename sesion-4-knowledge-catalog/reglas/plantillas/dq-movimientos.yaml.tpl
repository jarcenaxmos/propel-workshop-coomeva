# Reglas de calidad para coop_raw.movimientos_aportes_ahorro
# Formato: DataQualitySpec (dataplex v1) en YAML. Uso: bash scripts/scans.sh
samplingPercent: 100
catalogPublishingEnabled: true
rules:
# --- Validez -------------------------------------------------------------
- name: monto-no-negativo
  description: Los montos llegan siempre positivos; el tipo de movimiento dice el signo.
  column: monto
  dimension: VALIDITY
  threshold: 1.0
  rangeExpectation:
    minValue: '0'
- name: tipo-movimiento-en-catalogo
  column: tipo_movimiento
  dimension: VALIDITY
  threshold: 1.0
  setExpectation:
    values: [Consignacion, Retiro, Aporte mensual, Rendimiento]
- name: canal-en-catalogo
  column: canal
  dimension: VALIDITY
  threshold: 1.0
  setExpectation:
    values: [Oficina, App, Web, PSE, Debito automatico]
- name: fecha-en-historia
  description: La historia va de 2024-01-01 a 2026-10-31.
  column: fecha_movimiento
  dimension: VALIDITY
  threshold: 1.0
  rowConditionExpectation:
    sqlExpression: fecha_movimiento >= TIMESTAMP '2024-01-01' AND fecha_movimiento < TIMESTAMP '2026-11-01'
# --- Completitud ---------------------------------------------------------
- name: id-asociado-no-nulo
  column: id_asociado
  dimension: COMPLETENESS
  threshold: 1.0
  nonNullExpectation: {}
- name: monto-no-nulo
  column: monto
  dimension: COMPLETENESS
  threshold: 1.0
  nonNullExpectation: {}
# --- Unicidad ------------------------------------------------------------
- name: id-movimiento-unico
  column: id_movimiento
  dimension: UNIQUENESS
  uniquenessExpectation: {}
# --- Consistencia --------------------------------------------------------
- name: asociado-existe
  description: Todo movimiento es de un asociado que existe en coop_raw.asociados.
  column: id_asociado
  dimension: CONSISTENCY
  threshold: 1.0
  rowConditionExpectation:
    sqlExpression: id_asociado IN (SELECT id_asociado FROM `__PROJECT__.coop_raw.asociados`)
# --- Frescura ------------------------------------------------------------
- name: frescura-corte-octubre
  description: El último movimiento debe ser del corte (31-oct-2026). En producción se compara con CURRENT_TIMESTAMP().
  column: fecha_movimiento
  dimension: FRESHNESS
  tableConditionExpectation:
    sqlExpression: MAX(fecha_movimiento) >= TIMESTAMP '2026-10-31'
