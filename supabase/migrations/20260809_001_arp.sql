-- =====================================================================
-- Migration 001: ARP (Armazenamento de Registro de Ponto)
-- Append-only. Nada aqui pode ser alterado ou apagado. Portaria 671,
-- Anexo IX: "os dados armazenados na ARP não devem ser apagados ou
-- alterados, direta ou indiretamente, pelo prazo mínimo legal".
-- =====================================================================

-- ---------------------------------------------------------------------
-- CRC-16/KERMIT (CCITT-TRUE) — obrigatório nos registros tipo 1 a 5.
-- Confere: crc16_kermit('123456789') = '2189'
-- ---------------------------------------------------------------------
create or replace function ponto.crc16_kermit(txt text)
returns text
language plpgsql
immutable
as $$
declare
  bytes bytea := convert_to(txt, 'LATIN1');
  crc   int   := 0;
  i     int;
  j     int;
begin
  for i in 0 .. octet_length(bytes) - 1 loop
    crc := crc # get_byte(bytes, i);
    for j in 1 .. 8 loop
      if (crc & 1) = 1 then
        crc := (crc >> 1) # 33800;   -- 0x8408 (polinômio 0x1021 refletido)
      else
        crc := crc >> 1;
      end if;
    end loop;
  end loop;
  return upper(lpad(to_hex(crc & 65535), 4, '0'));
end;
$$;

-- ---------------------------------------------------------------------
-- Campo tipo DH do AFD: "AAAA-MM-ddThh:mm:00ZZZZZ" (24 caracteres)
-- Segundos são fixos em "00" por determinação do leiaute.
-- ---------------------------------------------------------------------
create or replace function ponto.afd_dh(ts timestamptz, tz text)
returns text
language plpgsql
immutable
as $$
declare
  minutos int;
  sinal   text;
begin
  minutos := extract(epoch from ((ts at time zone tz) - (ts at time zone 'UTC'))) / 60;
  sinal   := case when minutos < 0 then '-' else '+' end;
  return to_char(ts at time zone tz, 'YYYY-MM-DD"T"HH24:MI:"00"')
       || sinal
       || lpad((abs(minutos) / 60)::int::text, 2, '0')
       || lpad((abs(minutos) % 60)::int::text, 2, '0');
end;
$$;

-- ---------------------------------------------------------------------
-- Coletor da marcação (campo 6 do registro tipo 7)
-- ---------------------------------------------------------------------
create type ponto.coletor as enum (
  'app_mobile',       -- 01
  'browser',          -- 02  <- nosso PWA
  'app_desktop',      -- 03
  'dispositivo',      -- 04
  'outro'             -- 05
);

create or replace function ponto.coletor_codigo(c ponto.coletor)
returns char(2) language sql immutable as $$
  select case c
    when 'app_mobile'  then '01'
    when 'browser'     then '02'
    when 'app_desktop' then '03'
    when 'dispositivo' then '04'
    else '05' end::char(2);
$$;

-- ---------------------------------------------------------------------
-- Contador de NSR — sequencial e sem buracos, por REP.
-- Sequence do Postgres não serve: rollback deixa buraco no AFD.
-- ---------------------------------------------------------------------
create table ponto.nsr_contador (
  rep_id     uuid primary key references ponto.rep(id),
  ultimo_nsr bigint not null default 0 check (ultimo_nsr >= 0)
);

-- ---------------------------------------------------------------------
-- ARP: log append-only de todos os tipos de registro do AFD
-- ---------------------------------------------------------------------
create table ponto.arp (
  id             uuid primary key default gen_random_uuid(),
  rep_id         uuid   not null references ponto.rep(id),
  nsr            bigint not null,
  tipo           char(1) not null check (tipo in ('2','3','4','5','6','7')),

  -- comuns
  dh_gravacao    timestamptz not null default now(),   -- SEMPRE hora do servidor

  -- tipo 7 (marcação REP-P)
  empregado_id   uuid references ponto.empregados(id),
  cpf            varchar(11),
  dh_marcacao    timestamptz,
  coletor        ponto.coletor,
  offline        boolean not null default false,

  -- cadeia de integridade (campo 8 do tipo 7)
  hash           char(64),
  hash_anterior  char(64),

  -- tipos 2/4/5/6
  payload        jsonb not null default '{}'::jsonb,

  -- linha pronta do AFD, congelada no momento da gravação
  linha_afd      text not null default '',

  unique (rep_id, nsr)
);

create index on ponto.arp (rep_id, dh_marcacao) where tipo = '7';
create index on ponto.arp (empregado_id, dh_marcacao desc) where tipo = '7';

-- ---------------------------------------------------------------------
-- Trigger: atribui NSR, encadeia o hash e congela a linha do AFD
-- ---------------------------------------------------------------------
create or replace function ponto.arp_before_insert()
returns trigger
language plpgsql
as $$
declare
  cfg        ponto.rep%rowtype;
  h_anterior char(64);
  base       text;
  dh_marc    text;
  dh_grav    text;
begin
  select * into cfg from ponto.rep where id = new.rep_id;
  if not found then
    raise exception 'REP % não cadastrado', new.rep_id;
  end if;

  -- serializa a numeração por REP: NSR sem buracos e hash sem corrida
  perform pg_advisory_xact_lock(hashtextextended(new.rep_id::text, 0));

  insert into ponto.nsr_contador (rep_id, ultimo_nsr)
       values (new.rep_id, 0)
  on conflict (rep_id) do nothing;

  update ponto.nsr_contador
     set ultimo_nsr = ultimo_nsr + 1
   where rep_id = new.rep_id
  returning ultimo_nsr into new.nsr;

  if new.tipo = '7' then
    if new.cpf is null or new.dh_marcacao is null then
      raise exception 'Marcação tipo 7 exige cpf e dh_marcacao';
    end if;

    select a.hash into h_anterior
      from ponto.arp a
     where a.rep_id = new.rep_id and a.tipo = '7'
     order by a.nsr desc
     limit 1;

    new.hash_anterior := h_anterior;

    dh_marc := ponto.afd_dh(new.dh_marcacao, cfg.timezone);
    dh_grav := ponto.afd_dh(new.dh_gravacao,  cfg.timezone);

    -- Campos 1 a 7 concatenados exatamente como saem no AFD,
    -- seguidos do hash do registro anterior (campo 8, se existir).
    base := lpad(new.nsr::text, 9, '0')      -- campo 1  (pos 001-009)
         || '7'                              -- campo 2  (pos 010)
         || dh_marc                          -- campo 3  (pos 011-034)
         || lpad(new.cpf, 12, '0')           -- campo 4  (pos 035-046)
         || dh_grav                          -- campo 5  (pos 047-070)
         || ponto.coletor_codigo(new.coletor)-- campo 6  (pos 071-072)
         || case when new.offline then '1' else '0' end  -- campo 7 (pos 073)
         || coalesce(h_anterior, '');

    new.hash := upper(encode(digest(convert_to(base, 'LATIN1'), 'sha256'), 'hex'));

    new.linha_afd := lpad(new.nsr::text, 9, '0')
                  || '7' || dh_marc || lpad(new.cpf, 12, '0') || dh_grav
                  || ponto.coletor_codigo(new.coletor)
                  || case when new.offline then '1' else '0' end
                  || new.hash;                -- campo 8 (pos 074-137)

  elsif new.tipo = '6' then
    -- eventos sensíveis: "07" disponibilidade / "08" indisponibilidade
    new.linha_afd := lpad(new.nsr::text, 9, '0') || '6'
                  || ponto.afd_dh(new.dh_gravacao, cfg.timezone)
                  || lpad(coalesce(new.payload->>'evento', '08'), 2, '0');

  elsif new.tipo = '5' then
    -- inclusão/alteração/exclusão de empregado
    base := lpad(new.nsr::text, 9, '0') || '5'
         || ponto.afd_dh(new.dh_gravacao, cfg.timezone)
         || upper(coalesce(new.payload->>'operacao', 'I'))
         || lpad(coalesce(new.payload->>'cpf', ''), 12, '0')
         || rpad(substr(upper(coalesce(new.payload->>'nome', '')), 1, 52), 52, ' ')
         || rpad(coalesce(new.payload->>'identificacao', ''), 4, ' ')
         || lpad(coalesce(new.payload->>'cpf_responsavel', ''), 11, '0');
    new.linha_afd := base || ponto.crc16_kermit(base);

  elsif new.tipo = '2' then
    base := lpad(new.nsr::text, 9, '0') || '2'
         || ponto.afd_dh(new.dh_gravacao, cfg.timezone)
         || lpad(coalesce(new.payload->>'cpf_responsavel', ''), 14, '0')
         || cfg.tipo_id_empregador
         || rpad(cfg.cnpj_cpf_empregador, 14, ' ')
         || rpad(cfg.cno_caepf, 14, ' ')
         || rpad(substr(cfg.razao_social, 1, 150), 150, ' ')
         || rpad(substr(cfg.local_prestacao, 1, 100), 100, ' ');
    new.linha_afd := base || ponto.crc16_kermit(base);
  end if;

  return new;
end;
$$;

create trigger t_arp_before_insert
  before insert on ponto.arp
  for each row execute function ponto.arp_before_insert();

-- ---------------------------------------------------------------------
-- Imutabilidade: nem o service_role, nem o dono da tabela alteram.
-- ---------------------------------------------------------------------
create or replace function ponto.arp_imutavel()
returns trigger language plpgsql as $$
begin
  raise exception
    'ARP é imutável (Portaria 671/2021, Anexo IX). Operação % bloqueada no NSR %.',
    tg_op, coalesce(old.nsr, new.nsr);
end;
$$;

create trigger t_arp_sem_update before update on ponto.arp
  for each row execute function ponto.arp_imutavel();

create trigger t_arp_sem_delete before delete on ponto.arp
  for each row execute function ponto.arp_imutavel();

-- TRUNCATE não dispara trigger de linha: precisa de trigger de comando.
create or replace function ponto.arp_sem_truncate()
returns trigger language plpgsql as $$
begin
  raise exception 'ARP é imutável (Portaria 671/2021, Anexo IX). TRUNCATE bloqueado.';
end;
$$;

create trigger t_arp_sem_truncate before truncate on ponto.arp
  for each statement execute function ponto.arp_sem_truncate();

-- NÃO usar RULE ... DO INSTEAD NOTHING aqui: a rule é reescrita antes do
-- trigger e engole o DELETE em silêncio — o operador vê "DELETE 0" e
-- acredita que a linha não existia. Falha silenciosa em log fiscal é pior
-- que falha ruidosa. O trigger acima levanta exceção, que é o certo.

revoke update, delete, truncate on ponto.arp from public;

-- ---------------------------------------------------------------------
-- Verificador da cadeia — roda antes de gerar qualquer AFD
-- ---------------------------------------------------------------------
create or replace function ponto.arp_verificar_cadeia(p_rep_id uuid)
returns table (nsr bigint, problema text)
language plpgsql
as $$
declare
  r          record;
  cfg        ponto.rep%rowtype;
  esperado   char(64);
  h_anterior char(64) := null;
  nsr_prev   bigint   := null;
  base       text;
begin
  select * into cfg from ponto.rep where id = p_rep_id;

  for r in
    select * from ponto.arp
     where rep_id = p_rep_id and tipo = '7'
     order by arp.nsr
  loop
    if nsr_prev is not null and r.nsr <> nsr_prev + 1 then
      nsr := r.nsr; problema := 'buraco na sequência de NSR'; return next;
    end if;

    base := lpad(r.nsr::text, 9, '0') || '7'
         || ponto.afd_dh(r.dh_marcacao, cfg.timezone)
         || lpad(r.cpf, 12, '0')
         || ponto.afd_dh(r.dh_gravacao, cfg.timezone)
         || ponto.coletor_codigo(r.coletor)
         || case when r.offline then '1' else '0' end
         || coalesce(h_anterior, '');

    esperado := upper(encode(digest(convert_to(base, 'LATIN1'), 'sha256'), 'hex'));

    if esperado <> r.hash then
      nsr := r.nsr; problema := 'hash não confere — registro adulterado'; return next;
    end if;

    h_anterior := r.hash;
    nsr_prev   := r.nsr;
  end loop;
end;
$$;
