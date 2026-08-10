---
chapeu: como-fazer
status: ativo
atualizado: 2026-08-10
---

# O que falta configurar

Migrations, seed, Edge Functions e GitHub Pages já estão no ar.
Restam quatro itens.

## 1. Segredos das Edge Functions  (sem isto, nada funciona)

Painel → **Edge Functions → Secrets** → adicionar:

| Nome | Valor |
|---|---|
| `ORIGEM_PWA` | `https://pedrocoutinho2.github.io` |
| `WEBAUTHN_RP_ID` | `pedrocoutinho2.github.io` |

O `SUPABASE_URL` e o `SUPABASE_SERVICE_ROLE_KEY` já vêm preenchidos.

**Atenção ao endereço.** O passkey fica amarrado ao domínio: se um dia o
sistema mudar para `ponto.cnataquara.com.br`, todo mundo terá que registrar
o celular de novo. Se você já pretende usar domínio próprio, configure
antes de cadastrar a equipe — economiza 18 reregistros.

## 2. Criar o bucket de evidências

Painel → **Storage → New bucket** → nome `liveness`, **privado**,
limite 500 KB, tipo `image/jpeg`.

Só é usado quando algum sinal de identidade falha. Sem ele a marcação
grava normalmente e a evidência é descartada — a função foi escrita para
nunca deixar de registrar o ponto por causa disso.

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

A coordenada é aproximada e o raio está largo (120 m) de propósito, para
não gerar falso alarme antes da calibragem.

```sql
update ponto.cercas set
  latitude  = <lat do prédio>,
  longitude = <lng do prédio>,
  raio_m    = 90,
  ips       = array['<IP público da escola>/32']::cidr[]
where nome = 'Unidade Taquara';
```

Coordenada: ponto central do prédio no Google Maps. IP: acesse
`ifconfig.me` **de dentro do Wi-Fi da escola**. Sem IP fixo, essa camada
não é confiável — fale com a operadora.

---

# Como colocar a equipe no ar

Para cada pessoa, três etapas em qualquer ordem nas duas primeiras:

1. **Cadastro** — aba Equipe da administração, com o e-mail de acesso.
2. **Conta** — Authentication → Users → Add user, mesmo e-mail,
   com Auto Confirm marcado.
3. **Biometria** — tela `cadastro.html`, presencialmente: termo de
   consentimento assinado e três amostras do rosto.

Depois disso, a própria pessoa abre a tela de bater ponto no celular dela
e registra o aparelho. Isso não pode ser feito por outro: a chave nasce
dentro do aparelho e nunca sai de lá.

A tabela na tela de cadastro mostra em que pé está cada um.

---

# Telas

| Endereço | Para quê |
|---|---|
| `/` | Bater ponto |
| `/entrar.html` | Login |
| `/admin.html` | Equipe, espelho, banco de horas, relatórios |
| `/cadastro.html` | Cadastro biométrico presencial |

---

# Já resolvido

**Schema `ponto` exposto na API** — feito por SQL:

```sql
alter role authenticator set pgrst.db_schemas = 'public, graphql_public, ponto';
notify pgrst, 'reload config';
```

É um override em nível de banco e **vence** a configuração do painel. Se
alguém abrir *Integrations → Data API → Exposed schemas* e salvar sem
incluir `ponto`, a tela mostra uma coisa e o servidor faz outra. Para
devolver o controle à interface: `alter role authenticator reset pgrst.db_schemas;`

**Edge Functions publicadas:** `desafio-liveness`, `webauthn-registro`,
`registrar-ponto`.

**Ainda não publicadas:** `comprovante` e `gerar-afd`. Elas servem à
obrigação de REP-P, que não se aplica a 18 pessoas. O código está no
repositório e sobe em minutos se a equipe crescer.
