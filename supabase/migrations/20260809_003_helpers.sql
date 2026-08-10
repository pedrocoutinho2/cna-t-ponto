-- =====================================================================
-- Migration 003: helpers chamados pelas Edge Functions
-- =====================================================================

-- Checagem de IP público contra as faixas autorizadas da unidade.
-- Fica no schema public porque o supabase-js só chama RPC de schema
-- exposto sem precisar de .schema() em todos os pontos.
create or replace function public.ip_em_faixas(p_ip inet, p_faixas cidr[])
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from unnest(coalesce(p_faixas, '{}'::cidr[])) f
     where p_ip << f or p_ip <<= f
  );
$$;

grant execute on function public.ip_em_faixas(inet, cidr[]) to service_role;

-- Bucket privado das evidências de liveness.
-- Só é alimentado quando algum sinal falha; retenção curta.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('liveness', 'liveness', false, 512000, array['image/jpeg'])
on conflict (id) do nothing;

-- Nenhuma política de leitura para authenticated: as evidências só saem
-- por URL assinada gerada pela coordenação, com registro em ponto.auditoria.

-- ---------------------------------------------------------------------
-- Expurgo das evidências após 90 dias (pg_cron)
-- Os descritores e a ARP permanecem; só a imagem sai.
-- ---------------------------------------------------------------------
create or replace function ponto.expurgar_evidencias(dias int default 90)
returns int
language plpgsql
security definer
set search_path = ponto, storage, public
as $$
declare
  removidos int := 0;
  r record;
begin
  for r in
    select arp_id, liveness_evidencia
      from ponto.marcacao_contexto
     where liveness_evidencia is not null
       and criado_em < now() - make_interval(days => dias)
       and revisao <> 'pendente'
  loop
    delete from storage.objects
     where bucket_id = 'liveness' and name = r.liveness_evidencia;
    update ponto.marcacao_contexto
       set liveness_evidencia = null
     where arp_id = r.arp_id;
    removidos := removidos + 1;
  end loop;
  return removidos;
end;
$$;

-- select cron.schedule('expurgo-liveness', '0 3 * * *',
--   $$select ponto.expurgar_evidencias(90)$$);
