-- Solo en las copias de los participantes. NO en coop_marts: un agente conversacional que olvida el filtro fallaría.
ALTER TABLE `coop_trabajo.fct_cartera_mensual`
SET OPTIONS (require_partition_filter = TRUE);
