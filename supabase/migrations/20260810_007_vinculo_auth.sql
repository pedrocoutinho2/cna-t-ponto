-- =====================================================================
-- Migration 007: vínculo automático entre conta de login e cadastro
--
-- Sem isto, criar o usuário no Auth não basta: ele entra sem papel e sem
-- vínculo com ponto.empregados, e o painel abre vazio sem explicar por quê.
-- =====================================================================

alter table ponto.empregados add column if not exists email text;
create unique index if not exists empregados_email_uk
  on ponto.empregados (lower(email)) where email is not null;

-- Quem tem acesso administrativo. Separado de empregados de propósito:
-- o papel precisa existir ANTES de a pessoa ter cadastro, senão ninguém
-- consegue cadastrar o primeiro.
create table if not exists ponto.acessos (
  email      text primary key,
  papel      text not null check (papel in ('coordenacao','auditor')),
  criado_em  timestamptz not null default now(),
  observacao text
);

alter table ponto.acessos enable row level security;
grant select on ponto.acessos to authenticated;
create policy p_acessos_leitura on ponto.acessos
  for select to authenticated using (ponto.eh_coordenacao());

insert into ponto.acessos (email, papel, observacao)
values ('taquara@cna.com.br', 'coordenacao', 'Conta administrativa da unidade')
on conflict (email) do update set papel = excluded.papel;

-- ---------------------------------------------------------------------
-- Ao criar a conta: aplica o papel e amarra ao cadastro pelo e-mail.
-- ---------------------------------------------------------------------
create or replace function ponto.vincular_conta()
returns trigger language plpgsql security definer
set search_path = ponto, auth, public as $fn$
declare v_papel text;
begin
  update ponto.empregados
     set auth_user_id = new.id
   where lower(email) = lower(new.email) and auth_user_id is null;

  select a.papel into v_papel from ponto.acessos a
   where lower(a.email) = lower(new.email);

  if v_papel is not null then
    update auth.users
       set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
                             || jsonb_build_object('papel', v_papel)
     where id = new.id;
  end if;

  return new;
end;
$fn$;

drop trigger if exists t_vincular_conta on auth.users;
create trigger t_vincular_conta
  after insert on auth.users
  for each row execute function ponto.vincular_conta();

-- ---------------------------------------------------------------------
-- Para contas que já existirem quando o e-mail for cadastrado depois.
-- ---------------------------------------------------------------------
create or replace function ponto.sincronizar_acessos()
returns integer language plpgsql security definer
set search_path = ponto, auth, public as $fn$
declare n integer := 0;
begin
  update ponto.empregados e
     set auth_user_id = u.id
    from auth.users u
   where lower(e.email) = lower(u.email) and e.auth_user_id is null;

  with alvo as (
    select u.id, a.papel from auth.users u
      join ponto.acessos a on lower(a.email) = lower(u.email)
     where coalesce(u.raw_app_meta_data->>'papel','') is distinct from a.papel
  )
  update auth.users u
     set raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb)
                           || jsonb_build_object('papel', alvo.papel)
    from alvo where alvo.id = u.id;

  get diagnostics n = row_count;
  return n;
end;
$fn$;
