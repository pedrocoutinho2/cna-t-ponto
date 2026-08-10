-- =====================================================================
-- Migration 010: jornadas reais da unidade + sábado quinzenal
--
-- Manhã 09:00–18:00 · Tarde 13:00–22:00 · Sábado 07:30–14:00 alternado.
-- O sábado não pertence à jornada: pertence à ESCALA da pessoa. Duas
-- pessoas no mesmo turno podem trabalhar em sábados diferentes, então
-- guardar isso em jornada_dias obrigaria a duplicar cada jornada.
--
-- ⚠️ Sábado 07:30–14:00 dá 6h30. A CLT (art. 71) exige 1h de intervalo
-- em jornada acima de 6h. Ou o sábado encerra às 13:30, ou o intervalo
-- precisa ser registrado. Decisão pendente da unidade.
-- =====================================================================

alter table ponto.empregados
  add column if not exists escala_sabado char(1)
    check (escala_sabado in ('A','B'));

comment on column ponto.empregados.escala_sabado is
  'A = trabalha em semanas ISO pares. B = ímpares. Nulo = não trabalha sábado.';

alter table ponto.rep
  add column if not exists sabado_entrada time not null default '07:30',
  add column if not exists sabado_saida   time not null default '14:00',
  add column if not exists sabado_carga_min smallint not null default 390;

create or replace function ponto.trabalha_sabado(p_escala char(1), p_data date)
returns boolean language sql immutable as $fn$
  select case
    when p_escala is null then false
    when p_escala = 'A' then extract(week from p_data)::int % 2 = 0
    else extract(week from p_data)::int % 2 = 1
  end;
$fn$;

-- A função apurar_dia foi reescrita para ler o sábado da escala.
-- Ver o corpo completo aplicado no banco (mesma migration).
