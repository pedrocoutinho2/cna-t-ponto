-- =====================================================================
-- Migration 004: jornada, tratamento e banco de horas
--
-- Princípio que atravessa este arquivo: a ARP nunca é tocada. Tudo que
-- é interpretação (qual marcação é entrada, qual é volta do almoço,
-- o que foi abonado, o que foi inserido à mão) vive aqui, com autor e
-- justificativa. Se um dia a apuração precisar ser refeita com outra
-- regra, a marcação original continua intacta para recalcular.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Jornada contratual
-- ---------------------------------------------------------------------
create table ponto.jornadas (
  id             uuid primary key default gen_random_uuid(),
  rep_id         uuid not null references ponto.rep(id),
  nome           text not null,                        -- "Administrativo 44h"
  tolerancia_min smallint not null default 10,         -- CLT art. 58, §1º
  intervalo_min  smallint not null default 60,         -- CLT art. 71
  ativa          boolean not null default true
);

create table ponto.jornada_dias (
  jornada_id     uuid not null references ponto.jornadas(id) on delete cascade,
  dia_semana     smallint not null check (dia_semana between 0 and 6), -- 0 = domingo
  entrada        time,
  saida_almoco   time,
  volta_almoco   time,
  saida          time,
  carga_min      smallint not null default 0,
  primary key (jornada_id, dia_semana)
);

-- Vínculo com vigência: trocar de escala não reescreve o passado.
-- btree_gist permite combinar uuid (=) com daterange (&&) no mesmo EXCLUDE.
create extension if not exists btree_gist;

create table ponto.empregado_jornada (
  id           uuid primary key default gen_random_uuid(),
  empregado_id uuid not null references ponto.empregados(id) on delete cascade,
  jornada_id   uuid not null references ponto.jornadas(id),
  vigencia     daterange not null,
  exclude using gist (empregado_id with =, vigencia with &&)
);

create table ponto.feriados (
  rep_id uuid not null references ponto.rep(id),
  data   date not null,
  nome   text not null,
  tipo   text not null default 'nacional'
         check (tipo in ('nacional','estadual','municipal','facultativo','recesso')),
  primary key (rep_id, data)
);

-- ---------------------------------------------------------------------
-- Camada de tratamento — append-only, cancelamento em vez de exclusão
-- ---------------------------------------------------------------------
create type ponto.ajuste_tipo as enum (
  'insercao',        -- marcação esquecida, inserida pela coordenação
  'desconsiderar',   -- marcação duplicada ou indevida
  'abono',           -- falta ou atraso abonado
  'atestado',
  'ferias',
  'folga',
  'compensacao'      -- uso de saldo do banco de horas
);

create table ponto.ajustes (
  id            uuid primary key default gen_random_uuid(),
  empregado_id  uuid not null references ponto.empregados(id),
  data          date not null,
  tipo          ponto.ajuste_tipo not null,
  horario       timestamptz,          -- para 'insercao'
  arp_id        uuid references ponto.arp(id),   -- para 'desconsiderar'
  minutos       integer,              -- para abono/compensacao
  justificativa text not null,
  criado_por    uuid not null references ponto.empregados(id),
  criado_em     timestamptz not null default now(),
  cancelado_por uuid references ponto.empregados(id),
  cancelado_em  timestamptz,
  cancelamento_motivo text,
  check (tipo <> 'insercao'      or horario is not null),
  check (tipo <> 'desconsiderar' or arp_id  is not null),
  check (length(justificativa) >= 5)
);

create index on ponto.ajustes (empregado_id, data) where cancelado_em is null;

create or replace function ponto.ajustes_sem_delete()
returns trigger language plpgsql as $$
begin
  raise exception 'Ajuste não se apaga: cancele preenchendo cancelado_por e cancelamento_motivo.';
end;
$$;

create trigger t_ajustes_sem_delete before delete on ponto.ajustes
  for each row execute function ponto.ajustes_sem_delete();

-- ---------------------------------------------------------------------
-- Banco de horas
-- ---------------------------------------------------------------------
create table ponto.banco_config (
  rep_id            uuid primary key references ponto.rep(id),
  prazo_meses       smallint not null default 6,   -- acordo individual: até 6 meses
  teto_positivo_min integer  not null default 2400, -- 40 h
  teto_negativo_min integer  not null default -1200,
  ativo             boolean  not null default true
);

create table ponto.banco_lancamentos (
  id            uuid primary key default gen_random_uuid(),
  empregado_id  uuid not null references ponto.empregados(id),
  data          date not null,
  minutos       integer not null,       -- positivo credita, negativo debita
  origem        text not null check (origem in ('apuracao','compensacao','expiracao','acerto')),
  referencia    uuid,
  observacao    text,
  criado_em     timestamptz not null default now(),
  unique (empregado_id, data, origem)
);

create index on ponto.banco_lancamentos (empregado_id, data);

-- =====================================================================
-- MOTOR DE APURAÇÃO
-- =====================================================================

-- Marcações efetivas do dia: ARP menos as desconsideradas, mais as
-- inserções manuais. Ordenadas por horário.
create or replace function ponto.marcacoes_efetivas(p_emp uuid, p_data date)
returns table (horario timestamptz, origem text, arp_id uuid)
language sql stable as $$
  with cfg as (select timezone from ponto.rep limit 1)
  select a.dh_marcacao, 'ponto', a.id
    from ponto.arp a, cfg
   where a.empregado_id = p_emp and a.tipo = '7'
     and (a.dh_marcacao at time zone cfg.timezone)::date = p_data
     and not exists (
       select 1 from ponto.ajustes j
        where j.arp_id = a.id and j.tipo = 'desconsiderar' and j.cancelado_em is null)
  union all
  select j.horario, 'inserida', null
    from ponto.ajustes j
   where j.empregado_id = p_emp and j.data = p_data
     and j.tipo = 'insercao' and j.cancelado_em is null
   order by 1;
$$;

-- Apuração de um dia.
create or replace function ponto.apurar_dia(p_emp uuid, p_data date)
returns table (
  data              date,
  dia_semana        smallint,
  feriado           text,
  carga_prev_min    integer,
  entrada           timestamptz,
  saida_almoco      timestamptz,
  volta_almoco      timestamptz,
  saida             timestamptz,
  marcacoes         integer,
  trabalhado_min    integer,
  intervalo_min     integer,
  atraso_min        integer,
  saida_antec_min   integer,
  saldo_min         integer,
  falta             boolean,
  apurado           boolean,
  abono_min         integer,
  noturno_min       integer,
  inconsistencias   text[]
)
language plpgsql stable as $$
declare
  tz        text;
  jd        ponto.jornada_dias%rowtype;
  v_dow     smallint;
  m         timestamptz[];
  n         integer;
  tol       smallint;
  int_min   smallint;
  prev_ent  timestamptz;
  prev_sai  timestamptz;
  probs     text[] := '{}';
begin
  select r.timezone into tz from ponto.rep r limit 1;

  data       := p_data;
  v_dow      := extract(dow from p_data)::smallint;
  dia_semana := v_dow;

  select f.nome into feriado
    from ponto.feriados f where f.data = p_data limit 1;

  select jdd.* into jd
    from ponto.empregado_jornada ej
    join ponto.jornadas j       on j.id = ej.jornada_id
    join ponto.jornada_dias jdd on jdd.jornada_id = j.id and jdd.dia_semana = v_dow
   where ej.empregado_id = p_emp and ej.vigencia @> p_data
   limit 1;

  select j.tolerancia_min, j.intervalo_min into tol, int_min
    from ponto.empregado_jornada ej
    join ponto.jornadas j on j.id = ej.jornada_id
   where ej.empregado_id = p_emp and ej.vigencia @> p_data
   limit 1;

  tol     := coalesce(tol, 10);
  int_min := coalesce(int_min, 60);

  carga_prev_min := case when feriado is not null then 0 else coalesce(jd.carga_min, 0) end;

  select array_agg(me.horario order by me.horario) into m
    from ponto.marcacoes_efetivas(p_emp, p_data) me;

  n := coalesce(array_length(m, 1), 0);
  marcacoes := n;

  select coalesce(sum(a.minutos), 0) into abono_min
    from ponto.ajustes a
   where a.empregado_id = p_emp and a.data = p_data
     and a.tipo in ('abono','atestado','ferias','folga') and a.cancelado_em is null;

  -- pareamento: 1ª entrada, 2ª saída almoço, 3ª volta, 4ª saída
  if n >= 1 then entrada      := m[1]; end if;
  if n >= 2 then saida_almoco := m[2]; end if;
  if n >= 3 then volta_almoco := m[3]; end if;
  if n >= 4 then saida        := m[4]; end if;

  if n = 2 then                       -- sem almoço registrado
    saida := m[2]; saida_almoco := null; volta_almoco := null;
  end if;

  trabalhado_min := 0;
  if n >= 2 and n <= 2 then
    trabalhado_min := extract(epoch from (m[2] - m[1]))/60;
  elsif n >= 4 then
    trabalhado_min := extract(epoch from (m[2] - m[1]))/60
                    + extract(epoch from (m[4] - m[3]))/60;
  end if;

  intervalo_min := case when n >= 3
    then (extract(epoch from (m[3] - m[2]))/60)::integer else null end;

  -- atraso e saída antecipada, contra o horário contratual
  atraso_min := 0; saida_antec_min := 0;
  if jd.entrada is not null and entrada is not null then
    prev_ent := (p_data + jd.entrada) at time zone tz;
    atraso_min := greatest(0, (extract(epoch from (entrada - prev_ent))/60)::integer);
    if atraso_min <= tol then atraso_min := 0; end if;
  end if;
  if jd.saida is not null and saida is not null then
    prev_sai := (p_data + jd.saida) at time zone tz;
    saida_antec_min := greatest(0, (extract(epoch from (prev_sai - saida))/60)::integer);
    if saida_antec_min <= tol then saida_antec_min := 0; end if;
  end if;

  falta := carga_prev_min > 0 and n = 0 and abono_min = 0;

  -- Dia com marcação faltando ou sobrando não é apurável. O sistema NÃO
  -- chuta: zera nada, credita nada, debita nada. Fica em aberto até a
  -- coordenação inserir a marcação que falta, com justificativa. Debitar
  -- uma jornada inteira de quem trabalhou e só esqueceu de bater é pior
  -- que não apurar.
  apurado := (n = 0 or n = 2 or n = 4);

  if not apurado then
    trabalhado_min := null;
    intervalo_min  := null;
    saldo_min      := null;
  else
    saldo_min := trabalhado_min + abono_min - carga_prev_min;
  end if;

  -- adicional noturno: 22h às 5h (CLT art. 73)
  noturno_min := 0;
  if n >= 2 then
    select coalesce(sum(
      greatest(0, extract(epoch from (
        least(fim, (d::date + time '05:00') at time zone tz)
        - greatest(ini, (d::date - 1 + time '22:00') at time zone tz)))/60))::integer, 0)
      into noturno_min
      from (values (m[1], m[2]), (case when n>=4 then m[3] end, case when n>=4 then m[4] end))
             as p(ini, fim),
           generate_series(p_data, p_data + 1, '1 day') d
     where p.ini is not null;
  end if;

  -- inconsistências
  if n % 2 = 1 then
    probs := probs || 'número ímpar de marcações'::text;
  end if;
  if carga_prev_min > 360 and n >= 3 and intervalo_min < int_min then
    probs := probs || format('intervalo de %s min, abaixo do mínimo de %s', intervalo_min, int_min)::text;
  end if;
  if carga_prev_min > 360 and n = 2 then
    probs := probs || 'jornada acima de 6h sem intervalo registrado'::text;
  end if;
  if saldo_min > 120 then
    probs := probs || 'mais de 2h extras no dia (CLT art. 59)'::text;
  end if;
  if n > 4 then
    probs := probs || format('%s marcações no dia', n)::text;
  end if;

  inconsistencias := probs;
  return next;
end;
$$;

-- Apuração de um período inteiro.
create or replace function ponto.apurar_periodo(p_emp uuid, p_ini date, p_fim date)
returns setof record
language sql stable as $$
  select a.* from generate_series(p_ini, p_fim, '1 day') d
  cross join lateral ponto.apurar_dia(p_emp, d::date) a;
$$;

-- Fecha o dia no banco de horas. Idempotente: reprocessar não duplica.
create or replace function ponto.fechar_banco(p_emp uuid, p_ini date, p_fim date)
returns integer
language plpgsql as $$
declare r record; total integer := 0;
begin
  for r in
    select * from generate_series(p_ini, p_fim, '1 day') d
    cross join lateral ponto.apurar_dia(p_emp, d::date) a
  loop
    if r.apurado and r.saldo_min is not null and r.saldo_min <> 0 then
      insert into ponto.banco_lancamentos (empregado_id, data, minutos, origem)
      values (p_emp, r.data, r.saldo_min, 'apuracao')
      on conflict (empregado_id, data, origem)
        do update set minutos = excluded.minutos;
      total := total + 1;
    end if;
  end loop;
  return total;
end;
$$;

create or replace function ponto.saldo_banco(p_emp uuid, p_ate date default current_date)
returns integer
language sql stable as $$
  select coalesce(sum(minutos), 0)::integer
    from ponto.banco_lancamentos
   where empregado_id = p_emp and data <= p_ate;
$$;

-- ---------------------------------------------------------------------
-- Painel de gestão
-- ---------------------------------------------------------------------
create view ponto.v_pendencias as
select c.arp_id, e.nome, a.dh_marcacao, c.sinais_ok,
       c.dentro_cerca, c.ip_autorizado, c.face_ok, c.liveness_ok,
       c.distancia_cerca_m, c.observacao
  from ponto.marcacao_contexto c
  join ponto.arp a        on a.id = c.arp_id
  join ponto.empregados e on e.id = c.empregado_id
 where c.revisao = 'pendente'
 order by a.dh_marcacao desc;
