# Reglas de calidad para coop_raw.asociados (Knowledge Catalog · auto data quality)
# Formato: DataQualitySpec de la API dataplex v1, en YAML.
# Uso: bash scripts/scans.sh  (crea o actualiza el scan dq-asociados y lo ejecuta)
# Cada regla lleva dimensión, umbral (threshold = fracción mínima de filas que deben pasar)
# y nombre en kebab-case para leerla en los resultados.
samplingPercent: 100
catalogPublishingEnabled: true   # publica el resultado en la entrada de la tabla (pestaña Data quality)
rules:
# --- Completitud ---------------------------------------------------------
- name: fecha-nacimiento-no-nula
  description: Todo asociado debe tener fecha de nacimiento (edad = segmentación y riesgo).
  column: fecha_nacimiento
  dimension: COMPLETENESS
  threshold: 1.0
  nonNullExpectation: {}
# --- Validez -------------------------------------------------------------
- name: email-formato-valido
  description: El email, si viene, debe tener formato usuario@dominio.tld.
  column: email
  dimension: VALIDITY
  threshold: 1.0
  ignoreNull: true
  regexExpectation:
    regex: '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
- name: fecha-vinculacion-no-futura
  description: Nadie se vincula en el futuro. Se compara con la fecha de corte de los datos (2026-10-31).
  column: fecha_vinculacion
  dimension: VALIDITY
  threshold: 1.0
  rowConditionExpectation:
    sqlExpression: fecha_vinculacion <= DATE '2026-10-31'
- name: tipo-documento-en-catalogo
  column: tipo_documento
  dimension: VALIDITY
  threshold: 1.0
  setExpectation:
    values: [CC, CE, PA]
- name: estado-en-catalogo
  column: estado
  dimension: VALIDITY
  threshold: 1.0
  setExpectation:
    values: [Activo, Retirado, Suspendido]
- name: segmento-en-catalogo
  column: segmento
  dimension: VALIDITY
  threshold: 1.0
  setExpectation:
    values: [Empleado, Independiente, Pensionado, Empresario]
# --- Unicidad ------------------------------------------------------------
- name: id-asociado-unico
  description: Un registro por asociado. Los duplicados inflan conteos de asociados activos.
  column: id_asociado
  dimension: UNIQUENESS
  uniquenessExpectation: {}
- name: id-asociado-sin-duplicados-conteo
  description: Cuántos id_asociado aparecen más de una vez (SQL assertion; falla si devuelve filas).
  column: id_asociado
  dimension: UNIQUENESS
  sqlAssertion:
    sqlStatement: |-
      SELECT id_asociado, COUNT(*) AS veces
      FROM ${data()}
      GROUP BY id_asociado
      HAVING COUNT(*) > 1
# --- Consistencia (integridad referencial) -------------------------------
- name: id-oficina-existe
  description: Toda oficina del asociado existe en coop_raw.oficinas.
  column: id_oficina
  dimension: CONSISTENCY
  threshold: 1.0
  rowConditionExpectation:
    sqlExpression: id_oficina IN (SELECT id_oficina FROM `__PROJECT__.coop_raw.oficinas`)
# --- Volumen -------------------------------------------------------------
- name: volumen-minimo
  description: Esperamos del orden de 60.000 asociados; menos de 50.000 indica una carga incompleta.
  dimension: VOLUME
  tableConditionExpectation:
    sqlExpression: COUNT(*) >= 50000
