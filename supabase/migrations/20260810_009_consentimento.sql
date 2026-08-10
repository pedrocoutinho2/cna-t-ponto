-- =====================================================================
-- Migration 009: termo de consentimento e cadastro biométrico
--
-- Biometria é dado pessoal sensível (LGPD art. 5º, II). Exige consentimento
-- específico e destacado — não serve cláusula embutida no contrato de
-- trabalho. Guardamos a versão exata do texto aceito, não só um "sim".
-- =====================================================================

create table ponto.termos (
  versao     text primary key,
  titulo     text not null,
  texto      text not null,
  vigente    boolean not null default false,
  criado_em  timestamptz not null default now()
);

create unique index termos_um_vigente on ponto.termos ((true)) where vigente;

create table ponto.consentimentos (
  id           uuid primary key default gen_random_uuid(),
  empregado_id uuid not null references ponto.empregados(id) on delete cascade,
  versao       text not null references ponto.termos(versao),
  aceito       boolean not null,
  aceito_em    timestamptz not null default now(),
  aceito_por_nome text not null,
  testemunha_id uuid references ponto.empregados(id),
  ip           inet,
  user_agent   text,
  revogado_em  timestamptz,
  revogado_motivo text
);

create index on ponto.consentimentos (empregado_id, aceito_em desc);

alter table ponto.termos          enable row level security;
alter table ponto.consentimentos  enable row level security;

create policy p_termos_leitura on ponto.termos
  for select to authenticated using (true);
create policy p_consent_leitura on ponto.consentimentos
  for select to authenticated
  using (empregado_id = ponto.empregado_atual() or ponto.eh_coordenacao());
create policy p_consent_registra on ponto.consentimentos
  for insert to authenticated with check (ponto.eh_coordenacao());
create policy p_consent_revoga on ponto.consentimentos
  for update to authenticated
  using (empregado_id = ponto.empregado_atual() or ponto.eh_coordenacao())
  with check (empregado_id = ponto.empregado_atual() or ponto.eh_coordenacao());

grant select on ponto.termos to authenticated;
grant select, insert, update on ponto.consentimentos to authenticated;

-- Biometria só entra se houver consentimento aceito e não revogado.
create policy p_bio_cadastra on ponto.biometria_facial
  for insert to authenticated
  with check (
    ponto.eh_coordenacao()
    and exists (select 1 from ponto.consentimentos c
                 where c.empregado_id = biometria_facial.empregado_id
                   and c.aceito and c.revogado_em is null));

create policy p_bio_coordenacao_le on ponto.biometria_facial
  for select to authenticated using (ponto.eh_coordenacao());

grant insert on ponto.biometria_facial to authenticated;
grant insert, update on ponto.dispositivos to authenticated;

-- Revogar consentimento revoga a biometria junto. Não faz sentido manter
-- o descritor de quem retirou a autorização.
create or replace function ponto.revogar_biometria()
returns trigger language plpgsql as $fn$
begin
  if new.revogado_em is not null and old.revogado_em is null then
    update ponto.biometria_facial
       set revogado_em = new.revogado_em
     where empregado_id = new.empregado_id and revogado_em is null;
  end if;
  return new;
end;
$fn$;

create trigger t_revogar_biometria
  after update on ponto.consentimentos
  for each row execute function ponto.revogar_biometria();

create or replace function ponto.situacao_cadastro()
returns table (
  empregado_id uuid, nome text, email text,
  tem_login boolean, consentiu boolean,
  amostras_faciais integer, aparelhos integer, pronto boolean
)
language sql stable as $fn$
  select e.id, e.nome::text, e.email,
         e.auth_user_id is not null,
         exists (select 1 from ponto.consentimentos c
                  where c.empregado_id = e.id and c.aceito and c.revogado_em is null),
         (select count(*)::integer from ponto.biometria_facial b
           where b.empregado_id = e.id and b.revogado_em is null),
         (select count(*)::integer from ponto.dispositivos d
           where d.empregado_id = e.id and d.ativo),
         e.auth_user_id is not null
           and exists (select 1 from ponto.consentimentos c
                        where c.empregado_id = e.id and c.aceito and c.revogado_em is null)
           and (select count(*) from ponto.biometria_facial b
                 where b.empregado_id = e.id and b.revogado_em is null) >= 3
    from ponto.empregados e
   where e.ativo
   order by e.nome;
$fn$;

grant execute on all functions in schema ponto to authenticated;

-- O texto do termo vigente (versão 2026.1) está no seed.sql.
