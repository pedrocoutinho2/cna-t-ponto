-- =====================================================================
-- Migration 002: contexto da marcação, fila de revisão e RLS
--
-- Separação deliberada: a ARP guarda o que a Portaria manda (e é
-- imutável). Esta tabela guarda o que a ESCOLA precisa para gerir
-- (onde estava, se passou no liveness, qual aparelho). O contexto pode
-- ser anotado e revisado sem jamais tocar no registro fiscal.
-- =====================================================================

create type ponto.revisao as enum ('nao_requer', 'pendente', 'aceita', 'contestada');

create table ponto.marcacao_contexto (
  arp_id              uuid primary key references ponto.arp(id),
  rep_id              uuid not null references ponto.rep(id),
  empregado_id        uuid not null references ponto.empregados(id),

  -- localização
  latitude            double precision,
  longitude           double precision,
  acuracia_m          double precision,
  distancia_cerca_m   double precision,
  dentro_cerca        boolean,
  cerca_id            uuid references ponto.cercas(id),

  -- rede
  ip                  inet,
  ip_autorizado       boolean,

  -- identidade
  dispositivo_id      uuid references ponto.dispositivos(id),
  webauthn_ok         boolean,
  face_similaridade   real,          -- cosseno, 0..1
  face_ok             boolean,
  liveness_desafio_id uuid references ponto.liveness_desafios(id),
  liveness_ok         boolean,
  liveness_evidencia  text,          -- caminho no Storage (bucket privado)

  -- resultado
  sinais_ok           smallint not null default 0,   -- 0..4
  revisao             ponto.revisao not null default 'nao_requer',
  revisado_por        uuid references ponto.empregados(id),
  revisado_em         timestamptz,
  observacao          text,

  user_agent          text,
  criado_em           timestamptz not null default now()
);

create index on ponto.marcacao_contexto (rep_id, revisao) where revisao = 'pendente';
create index on ponto.marcacao_contexto (empregado_id, criado_em desc);

-- ---------------------------------------------------------------------
-- Distância haversine em metros
-- ---------------------------------------------------------------------
create or replace function ponto.distancia_m(
  lat1 double precision, lon1 double precision,
  lat2 double precision, lon2 double precision
) returns double precision language sql immutable as $$
  select 6371000 * 2 * asin(sqrt(
      power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2))
    * power(sin(radians(lon2 - lon1) / 2), 2)
  ));
$$;

-- ---------------------------------------------------------------------
-- Match facial: maior similaridade de cosseno contra os descritores
-- ativos do próprio empregado.
-- ---------------------------------------------------------------------
create or replace function ponto.conferir_face(
  p_empregado_id uuid,
  p_descritor    vector(128)
) returns real language sql stable security definer set search_path = ponto, public as $$
  select coalesce(max(1 - (b.descritor <=> p_descritor)), 0)::real
    from ponto.biometria_facial b
   where b.empregado_id = p_empregado_id
     and b.revogado_em is null;
$$;

-- ---------------------------------------------------------------------
-- Espelho de ponto (insumo do Programa de Tratamento / AEJ)
-- ---------------------------------------------------------------------
create view ponto.v_espelho as
select
  e.id            as empregado_id,
  e.nome,
  e.cpf,
  a.nsr,
  a.dh_marcacao,
  (a.dh_marcacao at time zone r.timezone)::date as competencia,
  a.hash,
  c.dentro_cerca,
  c.ip_autorizado,
  c.face_ok,
  c.liveness_ok,
  c.sinais_ok,
  c.revisao
from ponto.arp a
join ponto.rep r         on r.id = a.rep_id
join ponto.empregados e  on e.id = a.empregado_id
left join ponto.marcacao_contexto c on c.arp_id = a.id
where a.tipo = '7'
order by e.nome, a.dh_marcacao;

-- =====================================================================
-- RLS
-- =====================================================================
alter table ponto.empregados          enable row level security;
alter table ponto.arp                 enable row level security;
alter table ponto.marcacao_contexto   enable row level security;
alter table ponto.biometria_facial    enable row level security;
alter table ponto.dispositivos        enable row level security;
alter table ponto.liveness_desafios   enable row level security;

-- quem é o empregado da sessão
create or replace function ponto.empregado_atual()
returns uuid language sql stable as $$
  select id from ponto.empregados where auth_user_id = auth.uid();
$$;

-- coordenação: claim customizado no JWT
create or replace function ponto.eh_coordenacao()
returns boolean language sql stable as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'papel') = 'coordenacao', false);
$$;

-- Empregado enxerga o próprio cadastro; coordenação enxerga todos.
create policy p_empregados_leitura on ponto.empregados
  for select to authenticated
  using (auth_user_id = auth.uid() or ponto.eh_coordenacao());

-- Marcações: cada um vê as suas. Ninguém insere direto — só via
-- Edge Function com service_role, que aplica a validação completa.
create policy p_arp_leitura on ponto.arp
  for select to authenticated
  using (empregado_id = ponto.empregado_atual() or ponto.eh_coordenacao());

create policy p_ctx_leitura on ponto.marcacao_contexto
  for select to authenticated
  using (empregado_id = ponto.empregado_atual() or ponto.eh_coordenacao());

-- Só a coordenação anota a revisão — e só a revisão.
create policy p_ctx_revisao on ponto.marcacao_contexto
  for update to authenticated
  using (ponto.eh_coordenacao())
  with check (ponto.eh_coordenacao());

-- Biometria: o titular lê e revoga a sua. Coordenação não lê descritor.
create policy p_bio_titular on ponto.biometria_facial
  for select to authenticated
  using (empregado_id = ponto.empregado_atual());

create policy p_bio_revogar on ponto.biometria_facial
  for update to authenticated
  using (empregado_id = ponto.empregado_atual())
  with check (empregado_id = ponto.empregado_atual());

create policy p_disp_titular on ponto.dispositivos
  for select to authenticated
  using (empregado_id = ponto.empregado_atual() or ponto.eh_coordenacao());

create policy p_desafio_titular on ponto.liveness_desafios
  for select to authenticated
  using (empregado_id = ponto.empregado_atual());

-- ---------------------------------------------------------------------
-- Auditoria de acesso administrativo (quem olhou o quê)
-- ---------------------------------------------------------------------
create table ponto.auditoria (
  id         bigserial primary key,
  ator       uuid,
  acao       text not null,
  alvo       text,
  detalhe    jsonb not null default '{}'::jsonb,
  ip         inet,
  criado_em  timestamptz not null default now()
);

create index on ponto.auditoria (criado_em desc);
