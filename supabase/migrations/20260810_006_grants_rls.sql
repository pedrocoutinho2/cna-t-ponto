-- =====================================================================
-- Migration 006: GRANTs de tabela + RLS nas tabelas que faltavam
--
-- RLS roda EM CIMA do GRANT, não no lugar dele. Sem GRANT, o PostgREST
-- devolve "permission denied" antes mesmo de avaliar a política. As
-- migrations 002 e 005 concediam acesso a funções e views, mas não às
-- tabelas — o painel admin quebraria em toda operação de escrita.
-- =====================================================================

alter table ponto.rep                enable row level security;
alter table ponto.jornadas           enable row level security;
alter table ponto.jornada_dias       enable row level security;
alter table ponto.empregado_jornada  enable row level security;
alter table ponto.feriados           enable row level security;
alter table ponto.ajustes            enable row level security;
alter table ponto.banco_config       enable row level security;
alter table ponto.banco_lancamentos  enable row level security;
alter table ponto.cercas             enable row level security;
alter table ponto.auditoria          enable row level security;
alter table ponto.nsr_contador       enable row level security;

-- ---- leitura geral do time -------------------------------------------
create policy p_rep_leitura on ponto.rep
  for select to authenticated using (true);
create policy p_jornadas_leitura on ponto.jornadas
  for select to authenticated using (true);
create policy p_jornada_dias_leitura on ponto.jornada_dias
  for select to authenticated using (true);
create policy p_feriados_leitura on ponto.feriados
  for select to authenticated using (true);
create policy p_banco_config_leitura on ponto.banco_config
  for select to authenticated using (true);

-- ---- cada um vê o seu; coordenação vê tudo ---------------------------
create policy p_ej_leitura on ponto.empregado_jornada
  for select to authenticated
  using (empregado_id = ponto.empregado_atual() or ponto.eh_coordenacao());

create policy p_ajustes_leitura on ponto.ajustes
  for select to authenticated
  using (empregado_id = ponto.empregado_atual() or ponto.eh_coordenacao());

create policy p_banco_leitura on ponto.banco_lancamentos
  for select to authenticated
  using (empregado_id = ponto.empregado_atual() or ponto.eh_coordenacao());

-- ---- escrita: só coordenação -----------------------------------------
create policy p_empregados_insere on ponto.empregados
  for insert to authenticated with check (ponto.eh_coordenacao());
create policy p_empregados_altera on ponto.empregados
  for update to authenticated
  using (ponto.eh_coordenacao()) with check (ponto.eh_coordenacao());

create policy p_ej_escreve on ponto.empregado_jornada
  for insert to authenticated with check (ponto.eh_coordenacao());

-- Ajuste é carimbado com o autor real: ninguém assina no lugar de outro.
create policy p_ajustes_insere on ponto.ajustes
  for insert to authenticated
  with check (ponto.eh_coordenacao() and criado_por = ponto.empregado_atual());

-- Cancelar ajuste é permitido; reescrever o conteúdo, não.
create policy p_ajustes_cancela on ponto.ajustes
  for update to authenticated
  using (ponto.eh_coordenacao() and cancelado_em is null)
  with check (ponto.eh_coordenacao() and cancelado_por = ponto.empregado_atual());

create policy p_jornadas_escreve on ponto.jornadas
  for all to authenticated
  using (ponto.eh_coordenacao()) with check (ponto.eh_coordenacao());
create policy p_jornada_dias_escreve on ponto.jornada_dias
  for all to authenticated
  using (ponto.eh_coordenacao()) with check (ponto.eh_coordenacao());
create policy p_feriados_escreve on ponto.feriados
  for all to authenticated
  using (ponto.eh_coordenacao()) with check (ponto.eh_coordenacao());
create policy p_banco_config_escreve on ponto.banco_config
  for update to authenticated
  using (ponto.eh_coordenacao()) with check (ponto.eh_coordenacao());

-- ---- GRANTs ----------------------------------------------------------
grant select on
  ponto.rep, ponto.empregados, ponto.jornadas, ponto.jornada_dias,
  ponto.empregado_jornada, ponto.feriados, ponto.ajustes,
  ponto.banco_config, ponto.banco_lancamentos, ponto.arp,
  ponto.marcacao_contexto, ponto.biometria_facial, ponto.dispositivos,
  ponto.liveness_desafios
to authenticated;

grant insert on ponto.empregados, ponto.empregado_jornada, ponto.ajustes to authenticated;
grant update on ponto.empregados, ponto.ajustes, ponto.marcacao_contexto,
                ponto.biometria_facial, ponto.banco_config to authenticated;
grant insert, update, delete on ponto.jornadas, ponto.jornada_dias, ponto.feriados to authenticated;
grant update on ponto.dispositivos to authenticated;

-- cercas, auditoria e nsr_contador: nenhum acesso pelo cliente.
grant all on all tables in schema ponto to service_role;
grant all on all sequences in schema ponto to service_role;

-- ARP nunca é escrita pelo cliente: só pela Edge Function.
revoke insert, update, delete on ponto.arp from authenticated;
