-- =====================================================================
-- Seed: cadastro inicial do CNA Taquara
-- Trocar os valores marcados com <> antes de aplicar.
-- =====================================================================

insert into ponto.rep (
  apelido, tipo_id_empregador, cnpj_cpf_empregador, razao_social,
  inpi, tipo_id_desenvolvedor, cnpj_cpf_desenvolvedor, local_prestacao
) values (
  'CNA Taquara',
  '1',
  '<CNPJ_CNA_TAQUARA_SO_DIGITOS>',
  '<RAZAO_SOCIAL_COMPLETA>',
  '<NUMERO_REGISTRO_INPI>',
  '1',
  '<CNPJ_DAROCHA_SO_DIGITOS>',
  'Rua <endereço da unidade>, Taquara, Rio de Janeiro - RJ'
);

-- Cerca da unidade. Pegar a coordenada do ponto central do prédio no
-- Google Maps e o IP público em https://ifconfig.me a partir do Wi-Fi
-- da escola. Raio inicial generoso: aperta depois do piloto.
insert into ponto.cercas (rep_id, nome, latitude, longitude, raio_m, ips)
select id, 'Unidade Taquara', -22.9285, -43.3720, 90, array['<IP_PUBLICO>/32']::cidr[]
  from ponto.rep where apelido = 'CNA Taquara';

-- ---------------------------------------------------------------------
-- Jornada padrão. Ajuste os horários reais da unidade antes de aplicar.
-- ---------------------------------------------------------------------
insert into ponto.jornadas (rep_id, nome, tolerancia_min, intervalo_min)
select id, 'Administrativo 44h', 10, 60 from ponto.rep;

-- Segunda a sexta: 09:00 às 18:00 com 1h de almoço = 480 min
insert into ponto.jornada_dias (jornada_id, dia_semana, entrada, saida_almoco, volta_almoco, saida, carga_min)
select j.id, d, '09:00', '12:00', '13:00', '18:00', 480
  from ponto.jornadas j, generate_series(1,5) d
 where j.nome = 'Administrativo 44h';

-- Sábado: 09:00 às 13:00 = 240 min. Remova se a unidade não abre sábado.
insert into ponto.jornada_dias (jornada_id, dia_semana, entrada, saida, carga_min)
select j.id, 6, '09:00', '13:00', 240
  from ponto.jornadas j where j.nome = 'Administrativo 44h';

-- Banco de horas: 6 meses é o prazo do acordo individual escrito.
-- Se houver convenção coletiva autorizando 12, troque aqui.
insert into ponto.banco_config (rep_id, prazo_meses, teto_positivo_min, teto_negativo_min)
select id, 6, 2400, -1200 from ponto.rep;

-- Feriados nacionais de 2026. Acrescente os municipais do Rio
-- (São Jorge, 23/04, e Dia do Comércio) conforme a prática da unidade.
insert into ponto.feriados (rep_id, data, nome, tipo)
select r.id, f.data::date, f.nome, 'nacional' from ponto.rep r,
(values
  ('2026-01-01','Confraternização Universal'),
  ('2026-02-17','Carnaval'),
  ('2026-04-03','Sexta-feira Santa'),
  ('2026-04-21','Tiradentes'),
  ('2026-05-01','Dia do Trabalho'),
  ('2026-06-04','Corpus Christi'),
  ('2026-09-07','Independência'),
  ('2026-10-12','Nossa Senhora Aparecida'),
  ('2026-11-02','Finados'),
  ('2026-11-15','Proclamação da República'),
  ('2026-11-20','Consciência Negra'),
  ('2026-12-25','Natal')
) as f(data, nome);
