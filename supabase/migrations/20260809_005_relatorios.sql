-- =====================================================================
-- Migration 005: relatórios de gestão
-- Funções tipadas, chamáveis por RPC do painel admin.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Espelho de ponto: um dia por linha
-- ---------------------------------------------------------------------
create or replace function ponto.espelho(p_emp uuid, p_ini date, p_fim date)
returns table (
  data date, dia_semana smallint, feriado text,
  carga_prev_min integer, entrada timestamptz, saida_almoco timestamptz,
  volta_almoco timestamptz, saida timestamptz, marcacoes integer,
  trabalhado_min integer, intervalo_min integer, atraso_min integer,
  saida_antec_min integer, saldo_min integer, falta boolean,
  apurado boolean, abono_min integer, noturno_min integer,
  inconsistencias text[]
)
language sql stable as $$
  select a.* from generate_series(p_ini, p_fim, '1 day') d
  cross join lateral ponto.apurar_dia(p_emp, d::date) a;
$$;

-- ---------------------------------------------------------------------
-- Resumo da equipe no período — a tela que o gestor abre primeiro
-- ---------------------------------------------------------------------
create or replace function ponto.resumo_equipe(p_ini date, p_fim date)
returns table (
  empregado_id uuid, nome text, cargo text,
  dias_previstos integer, dias_trabalhados integer, faltas integer,
  qtd_atrasos integer, atraso_total_min integer,
  trabalhado_min integer, saldo_periodo_min integer,
  saldo_banco_min integer, dias_em_aberto integer,
  intervalo_irregular integer
)
language sql stable as $$
  select
    e.id, e.nome, e.cargo,
    count(*) filter (where a.carga_prev_min > 0)::integer,
    count(*) filter (where a.marcacoes > 0)::integer,
    count(*) filter (where a.falta)::integer,
    count(*) filter (where a.atraso_min > 0)::integer,
    coalesce(sum(a.atraso_min), 0)::integer,
    coalesce(sum(a.trabalhado_min), 0)::integer,
    coalesce(sum(a.saldo_min) filter (where a.apurado), 0)::integer,
    ponto.saldo_banco(e.id, p_fim),
    count(*) filter (where not a.apurado)::integer,
    count(*) filter (
      where a.intervalo_min is not null and a.carga_prev_min > 360
        and a.intervalo_min < 60)::integer
  from ponto.empregados e
  cross join lateral ponto.espelho(e.id, p_ini, p_fim) a
  where e.ativo
  group by e.id, e.nome, e.cargo
  order by e.nome;
$$;

-- ---------------------------------------------------------------------
-- Recorrência de atraso por dia da semana.
-- Atraso espalhado é acidente. Atraso concentrado numa segunda-feira é
-- padrão, e padrão se resolve com conversa, não com desconto.
-- ---------------------------------------------------------------------
create or replace function ponto.recorrencia_atrasos(p_ini date, p_fim date)
returns table (
  empregado_id uuid, nome text, dia_semana smallint,
  ocorrencias integer, dias_no_periodo integer,
  taxa numeric, atraso_medio_min integer
)
language sql stable as $$
  select e.id, e.nome, a.dia_semana,
         count(*) filter (where a.atraso_min > 0)::integer,
         count(*) filter (where a.carga_prev_min > 0)::integer,
         round(
           count(*) filter (where a.atraso_min > 0)::numeric
           / nullif(count(*) filter (where a.carga_prev_min > 0), 0), 2),
         coalesce(avg(a.atraso_min) filter (where a.atraso_min > 0), 0)::integer
    from ponto.empregados e
    cross join lateral ponto.espelho(e.id, p_ini, p_fim) a
   where e.ativo and a.carga_prev_min > 0
   group by e.id, e.nome, a.dia_semana
  having count(*) filter (where a.atraso_min > 0) > 0
   order by 5 desc nulls last, e.nome;
$$;

-- ---------------------------------------------------------------------
-- Faltas e abonos consolidados
-- ---------------------------------------------------------------------
create or replace function ponto.relatorio_faltas(p_ini date, p_fim date)
returns table (
  empregado_id uuid, nome text, data date, dia_semana smallint,
  situacao text, justificativa text
)
language sql stable as $$
  select e.id, e.nome, a.data, a.dia_semana,
         case
           when a.falta then 'falta sem abono'
           when a.abono_min > 0 and a.marcacoes = 0 then 'ausência abonada'
           when not a.apurado then 'marcação faltando'
           else 'ok' end,
         (select string_agg(j.justificativa, ' · ')
            from ponto.ajustes j
           where j.empregado_id = e.id and j.data = a.data and j.cancelado_em is null)
    from ponto.empregados e
    cross join lateral ponto.espelho(e.id, p_ini, p_fim) a
   where e.ativo
     and (a.falta or not a.apurado or (a.abono_min > 0 and a.marcacoes = 0))
   order by a.data desc, e.nome;
$$;

-- ---------------------------------------------------------------------
-- Extrato do banco de horas
-- ---------------------------------------------------------------------
create or replace function ponto.extrato_banco(p_emp uuid, p_ini date, p_fim date)
returns table (
  data date, minutos integer, origem text,
  observacao text, acumulado integer
)
language sql stable as $$
  select l.data, l.minutos, l.origem, l.observacao,
         (ponto.saldo_banco(p_emp, p_ini - 1)
          + sum(l.minutos) over (order by l.data, l.id))::integer
    from ponto.banco_lancamentos l
   where l.empregado_id = p_emp and l.data between p_ini and p_fim
   order by l.data;
$$;

grant execute on all functions in schema ponto to authenticated;
