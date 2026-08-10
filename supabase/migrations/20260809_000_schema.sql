-- =====================================================================
-- PONTO CNA — REP-P conforme Portaria MTP 671/2021
-- Migration 000: extensões, configuração e cadastros
-- =====================================================================

create extension if not exists "pgcrypto";
create extension if not exists "vector";

create schema if not exists ponto;
comment on schema ponto is
  'REP-P (Registro Eletrônico de Ponto via Programa). Portaria MTP 671/2021.';

-- ---------------------------------------------------------------------
-- Configuração do REP-P (uma linha por empregador)
-- Campos alimentam o cabeçalho do AFD (registro tipo "1")
-- ---------------------------------------------------------------------
create table ponto.rep (
  id                    uuid primary key default gen_random_uuid(),
  apelido               text        not null,          -- "CNA Taquara"
  tipo_id_empregador    char(1)     not null default '1' check (tipo_id_empregador in ('1','2')),
  cnpj_cpf_empregador   varchar(14) not null,          -- só dígitos
  cno_caepf             varchar(14) not null default '',
  razao_social          varchar(150) not null,
  inpi                  varchar(17) not null,          -- registro do programa no INPI
  tipo_id_desenvolvedor char(1)     not null default '1',
  cnpj_cpf_desenvolvedor varchar(14) not null,
  local_prestacao       varchar(100) not null,         -- endereço da unidade
  timezone              text        not null default 'America/Sao_Paulo',
  versao_leiaute        char(3)     not null default '004',
  ativo                 boolean     not null default true,
  criado_em             timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Empregados
-- ---------------------------------------------------------------------
create table ponto.empregados (
  id           uuid primary key default gen_random_uuid(),
  rep_id       uuid not null references ponto.rep(id),
  auth_user_id uuid unique,                            -- auth.users.id
  cpf          varchar(11) not null,
  nome         varchar(52) not null,                   -- AFD tipo 5 limita a 52
  matricula    text,
  cargo        text,
  admissao     date not null,
  demissao     date,
  ativo        boolean not null default true,
  criado_em    timestamptz not null default now(),
  unique (rep_id, cpf)
);

create index on ponto.empregados (rep_id) where ativo;

-- ---------------------------------------------------------------------
-- Cercas: coordenada + raio + faixas de IP público autorizadas
-- ATENÇÃO: cerca NUNCA bloqueia marcação (art. 84, IV da Portaria 671).
-- Serve apenas para classificar a marcação para tratamento posterior.
-- ---------------------------------------------------------------------
create table ponto.cercas (
  id        uuid primary key default gen_random_uuid(),
  rep_id    uuid not null references ponto.rep(id),
  nome      text not null,
  latitude  double precision not null,
  longitude double precision not null,
  raio_m    integer not null default 90 check (raio_m between 20 and 500),
  acuracia_maxima_m integer not null default 60,
  ips       cidr[] not null default '{}',              -- IP público da unidade
  ativa     boolean not null default true
);

-- ---------------------------------------------------------------------
-- Biometria facial: guardamos APENAS o descritor (vetor), nunca a foto.
-- Dado pessoal sensível (LGPD art. 5º, II) — exige consentimento próprio.
-- ---------------------------------------------------------------------
create table ponto.biometria_facial (
  id                 uuid primary key default gen_random_uuid(),
  empregado_id       uuid not null references ponto.empregados(id) on delete cascade,
  descritor          vector(128) not null,             -- face-api.js FaceRecognitionNet
  consentimento_em   timestamptz not null,
  consentimento_ip   inet,
  consentimento_texto_versao text not null,
  revogado_em        timestamptz,
  criado_em          timestamptz not null default now()
);

create index on ponto.biometria_facial
  using hnsw (descritor vector_cosine_ops)
  where revogado_em is null;

-- ---------------------------------------------------------------------
-- Dispositivos (WebAuthn / passkey). 1 empregado pode ter 1..n aparelhos,
-- mas o vínculo novo exige aprovação da coordenação.
-- ---------------------------------------------------------------------
create table ponto.dispositivos (
  id             uuid primary key default gen_random_uuid(),
  empregado_id   uuid not null references ponto.empregados(id) on delete cascade,
  credential_id  text not null unique,                 -- base64url
  public_key     text not null,                        -- base64url (COSE)
  counter        bigint not null default 0,
  transports     text[] not null default '{}',
  apelido        text,
  aprovado_por   uuid references ponto.empregados(id),
  aprovado_em    timestamptz,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Desafios de liveness (nonce de uso único, TTL curto)
-- ---------------------------------------------------------------------
create table ponto.liveness_desafios (
  id           uuid primary key default gen_random_uuid(),
  empregado_id uuid not null references ponto.empregados(id) on delete cascade,
  nonce        text not null unique,
  acoes        text[] not null,                        -- ex.: {piscar,virar_direita}
  emitido_em   timestamptz not null default now(),
  expira_em    timestamptz not null,
  consumido_em timestamptz
);

create index on ponto.liveness_desafios (empregado_id) where consumido_em is null;
