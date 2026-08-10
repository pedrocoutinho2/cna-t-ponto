-- Trocar o turno de alguém exige encerrar a vigência antiga.
grant delete on ponto.empregado_jornada to authenticated;

create policy p_ej_apaga on ponto.empregado_jornada
  for delete to authenticated using (ponto.eh_coordenacao());

grant select on ponto.jornadas to authenticated;
