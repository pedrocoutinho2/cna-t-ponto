-- =====================================================================
-- Migration 008: vínculo nos DOIS sentidos
--
-- A 007 só cobria uma ordem: conta criada DEPOIS do cadastro. Na ordem
-- inversa — conta primeiro, cadastro depois, que é justamente o caminho
-- de quem instala o sistema — o gatilho em auth.users já tinha disparado
-- e nada ligava as pontas. Este gatilho fecha o outro sentido.
-- =====================================================================

create or replace function ponto.vincular_empregado()
returns trigger
language plpgsql
security definer
set search_path = ponto, auth, public
as $fn$
begin
  if new.email is not null and new.auth_user_id is null then
    select u.id into new.auth_user_id
      from auth.users u
     where lower(u.email) = lower(new.email)
     limit 1;
  end if;
  return new;
end;
$fn$;

drop trigger if exists t_vincular_empregado on ponto.empregados;
create trigger t_vincular_empregado
  before insert or update of email on ponto.empregados
  for each row execute function ponto.vincular_empregado();
