---
chapeu: como-fazer
status: ativo
atualizado: 2026-08-10
---

# O que falta configurar

Migrations e seed já estão aplicados no projeto `snipevyvfxaotjhnabmx`.
Faltam cinco passos manuais.

## 1. Expor o schema `ponto` na API  (sem isto, nada funciona)

Painel → **Integrations → Data API → Settings → Exposed schemas** (em algumas
versões o caminho é **Project Settings → Data API → Exposed schemas**) → acrescentar
`ponto` ao lado de `public`. Salvar.

O PostgREST só serve schemas listados ali. Enquanto `ponto` não estiver
na lista, toda chamada do PWA e do admin volta 404, mesmo com as tabelas
existindo e o RLS correto.

## 2. Criar o bucket de evidências

Painel → **Storage → New bucket** → nome `liveness`, **privado**,
limite de 500 KB, tipo permitido `image/jpeg`.

O Storage ainda não tinha sido inicializado quando a migration rodou, então
o bucket ficou de fora. Ele só é usado quando algum sinal de identidade
falha; sem ele, a marcação grava normalmente e a evidência é descartada.

## 3. Preencher os dados do empregador

```sql
update ponto.rep set
  cnpj_cpf_empregador    = '<CNPJ do CNA Taquara, só dígitos>',
  razao_social           = '<razão social completa>',
  cnpj_cpf_desenvolvedor = '<CNPJ da daRocha, só dígitos>'
where apelido = 'CNA Taquara';
```

O campo `inpi` fica vazio de propósito: com 18 colaboradores não há
obrigação de REP-P. Se a equipe passar de 20, é ele que precisa ser
preenchido.

## 4. Ajustar a cerca

A coordenada que está no banco é aproximada e o raio está largo (120 m)
justamente para não gerar falso alarme antes da calibragem.

```sql
update ponto.cercas set
  latitude  = <lat do prédio>,
  longitude = <lng do prédio>,
  raio_m    = 90,
  ips       = array['<IP público da escola>/32']::cidr[]
where nome = 'Unidade Taquara';
```

Pegue a coordenada clicando no ponto central do prédio no Google Maps, e o
IP acessando `ifconfig.me` **de dentro do Wi-Fi da escola**. Se o link não
tiver IP fixo, peça à operadora antes de confiar nessa camada.

## 5. Conferir a jornada

O seed assume 09h–18h de segunda a sexta com 1h de almoço, e 09h–13h no
sábado. Se não for isso:

```sql
select dia_semana, entrada, saida_almoco, volta_almoco, saida, carga_min
  from ponto.jornada_dias jd
  join ponto.jornadas j on j.id = jd.jornada_id
 order by dia_semana;
```

Se a unidade não abre sábado, apague a linha do `dia_semana = 6`.

---

## 6. Criar a conta de login

Painel → **Authentication → Users → Add user** → e-mail `taquara@cna.com.br`,
uma senha, e marque **Auto Confirm User**.

O papel de coordenação já está armado: a migration 007 instalou um gatilho
que aplica `papel: coordenacao` no momento em que a conta nasce, e amarra
o login ao cadastro de pessoa pelo e-mail. Você não precisa rodar SQL.

Para o resto da equipe, o caminho é o mesmo em qualquer ordem: cadastre a
pessoa na aba Equipe com o e-mail de acesso, crie a conta no Authentication,
e o vínculo acontece sozinho. Se as duas pontas já existirem e não tiverem
se encontrado, rode `select ponto.sincronizar_acessos();`.

A coluna **Acesso** na aba Equipe mostra em que pé está cada pessoa:
vinculado, aguardando primeiro login, ou sem e-mail.

---

## Depois disso

Publicar o `pwa/` no GitHub Pages e fazer o deploy das quatro Edge
Functions. Nenhuma das duas telas funciona antes do passo 1.

O cadastro biométrico presencial ainda não foi construído — é a próxima
peça, e é o que popula `ponto.biometria_facial` e `ponto.dispositivos`.
