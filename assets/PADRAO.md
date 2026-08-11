---
chapeu: referencia
status: ativo
atualizado: 2026-08-10
---

# Padrão visual compartilhado

Este arquivo existe para que CRM, Financeiro e Ponto não divirjam com o
tempo. A referência é o CRM (`pedrocoutinho2/crmcnataquara`), porque foi
onde o padrão nasceu.

## Tokens

Os dez tokens de cor batem exatamente com os do CRM. Só mudam de nome,
porque aqui a base é em português:

| CRM | Ponto | Valor |
|---|---|---|
| `--red` | `--vermelho` | `#E6143C` |
| `--redDark` | `--vermelho-escuro` | `#A30E2A` |
| `--blue` | `--azul` | `#19408B` |
| `--ink` | `--tinta` | `#1A1A1A` |
| `--gray` | `--cinza` | `#5A5A5A` |
| `--line` | `--linha` | `#E4E4E7` |
| `--surface` | `--superficie` | `#F7F7F9` |
| `--white` | `--branco` | `#FFFFFF` |
| `--ok` | `--verde` | `#1E7A46` |
| `--off` | `--apagado` | `#8A8A8E` |

## Componentes espelhados

| Componente | Regra |
|---|---|
| **Cabeçalho** | fundo branco, `border-bottom:3px solid` vermelho, `padding:12px 22px`, grudado no topo |
| **Abas (desktop)** | pílula: contêiner `--superficie` com borda, `border-radius:999px`, `padding:3px`; item `7px 20px`, Poppins 600 13px, cinza; ativo preenchido de vermelho |
| **Botão** | `.btn` — borda `--linha`, fundo branco, `border-radius:10px`, `padding:9px 14px`, 600 13px |
| **Botão primário** | `.btn.primary` — fundo vermelho, hover vermelho-escuro |
| **Botão destrutivo** | `.btn.danger` — texto vermelho-escuro, borda `#F1C2CC` |
| **Gaveta (mobile)** | item `border-radius:11px`, `padding:13px 12px`, 14.5px, ponto de 8px à esquerda; ativo preenchido de vermelho |

`.acao` e `.leve` continuam funcionando como apelido de `.btn.primary` e
`.btn`, para não quebrar o código já escrito. Em tela nova, prefira `.btn`.

## Como verificar que continua igual

Existe um comparador que lê o CSS dos dois sistemas e confere propriedade
por propriedade. Ele resolve os nomes de token dos dois lados antes de
comparar, então divergência que ele aponta é divergência de verdade.

Rode depois de mexer em botão, aba ou cabeçalho:

```bash
curl -s https://raw.githubusercontent.com/pedrocoutinho2/crmcnataquara/main/index.html -o /tmp/crm.html
npm install jsdom && node cmp.mjs
```

## O que ainda difere de propósito

- **Tipografia de dados.** O Ponto usa `font-variant-numeric: tabular-nums`
  em horas e saldos. O CRM não precisa: lá quase não há coluna numérica
  que precise alinhar.
- **Sem mascotes.** Vale para os dois: ferramenta interna não é peça de
  marca.
