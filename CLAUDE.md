# CLAUDE.md · cnataquara-ponto

Instruções permanentes para sessões do Claude neste repo.

## O que é

Ponto eletrônico do CNA Taquara. PWA de registro para a **equipe
administrativa**. Professores não entram.

- Produção: https://ponto.cnataquara.com.br
- Supabase: `snipevyvfxaotjhnabmx`
- Nome do repo segue o padrão da unidade: `cnataquara-{subdomínio}`

Este é o único repo da unidade com documentação própria. Leia antes de codar:

| Arquivo | Para quê |
|---|---|
| `README.md` | Desenho do sistema e a premissa que a pesquisa derrubou |
| `CONFIGURAR.md` | O que falta configurar (segredos das Edge Functions e afins) |
| `assets/PADRAO.md` | Padrão visual compartilhado entre CRM, adm e ponto |
| `assets/LOGOS.md` | Uso dos assets de marca |
| `docs/assinatura-icp.md` | Assinatura ICP-Brasil |

## Princípio inegociável

**O REP nunca pode bloquear o registro de ponto.**

A Portaria MTP 671/2021 é explícita: o REP não pode restringir horário nem
impedir a marcação. Geofence, liveness e biometria **classificam** o registro
para fila de revisão. Não barram.

Sistema que recusa registro porque a pessoa está a 200 m da escola não é
controle mais rígido, é apagamento de prova de jornada, e o efeito prático se
inverte contra a unidade (Súmula 338).

Nunca proponha nada que bloqueie a marcação.

## Arquitetura

Diferente do CRM e do adm: este repo **não** é monólito de arquivo único.

```
index.html                    PWA de registro (~670 linhas, 1 bloco <script>)
pessoal.html                  Área pessoal do funcionário
assets/cna.css                Design system
models/                       Pesos do face-api.js (o maior peso do repo, 6,4 MB)
supabase/migrations/          DDL versionado, prefixo 20260809_*
supabase/functions/           Edge Functions em TypeScript
```

Usa `supabase-js@2` de verdade, via `esm.sh`, ao contrário dos outros dois:

```js
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const CFG = { supabaseUrl: 'https://snipevyvfxaotjhnabmx.supabase.co', ... };
const sb = createClient(CFG.supabaseUrl, CFG.supabaseAnon);
```

Tabelas: `empregados`, `dispositivos`, view `v_espelho`. RPC `agora()`.

Edge Functions: `registrar-ponto`, `gerar-afd`, `webauthn-registro`,
`terminal-ponto`, `terminal-desafio`, `desafio-liveness`.

Registro fiscal em ARP append-only, encadeamento de hash SHA-256 com sequência
NSR. `marcacao_contexto` fica **separada** do registro fiscal.

## Isolamento

Este sistema é arquiteturalmente isolado do administrativo por razão fiscal e
legal. Não crie foreign key, view ou função que cruze com `thelqaxsnuynevizhcla`.

As telas `rep.html` e `rep-entrar.html` moram no repo `cnataquara-adm` mas
apontam para o banco deste projeto. Isso é intencional: a separação que importa
é a do banco, não a do repo.

## Migrations

`apply_migration` para DDL, porque registra histórico. `execute_sql` para DML e
verificação. Dollar-quoting em insert grande. Toda migration nova entra também
em `supabase/migrations/` neste repo, para o versionado não divergir do banco.

## Deploy

Nunca entregue arquivo para upload manual. Sempre via API do GitHub.

1. Valide o JS com `node --check` antes de commitar
2. `GET` do arquivo para pegar o `sha`
3. `PUT` em `contents` com `sha` + conteúdo em base64
4. Poll em `pages/builds/latest` até `built`
5. Confirme lendo via API com `Accept: application/vnd.github.raw`

## Pendências não técnicas

Registro de software no INPI, certificado e-CNPJ ICP-Brasil e o documento de
atestado técnico. São bloqueadores de conformidade, não de código.

## Regras

- Busque o arquivo atual antes de editar. Nunca escreva de memória.
- Confirme com o Pedro antes de qualquer operação destrutiva no banco.
- 18 funcionários administrativos, abaixo do limite de 20 do REP-P.
