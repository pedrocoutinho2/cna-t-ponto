# Design System — Sistemas CNA Taquara
**v1.0 · 2026-08-10 · vale para CRM, Financeiro, Ponto (REP-A) e todo sistema novo**

> Este documento cuida de **interface de sistema**. O `CNA-Taquara-Design-System.md` cuida de **apresentação e material de treinamento**. Os dois compartilham paleta e tipografia; divergem no resto, porque deck é para projetar e sistema é para operar.
>
> Arquivo de implementação: `cna-ds.css`.

---

## 1. Princípios

- **Ferramenta, não vitrine.** Sistema interno é usado sob pressão, em pé, no celular, entre um atendimento e outro. Densidade e clareza vencem elegância.
- **Sem mascote.** Mascote é anfitrião de marca em conteúdo e treinamento. O Ben sorrindo enquanto alguém lança uma despesa ou registra um atraso não ajuda ninguém. A regra já valia para o Financeiro; agora vale para todos.
- **Marca por acento, não por área.** Vermelho e azul entram em barra, botão, item ativo e dado. Fundo é branco ou `surface`.
- **Mobile é o caso principal.** A equipe usa celular. Toda tela nasce funcionando em 390px.
- **Um jeito de fazer cada coisa.** Se dois sistemas resolvem o mesmo problema de dois jeitos, um dos dois está errado.

---

## 2. Tokens

Nomes em **inglês**. CRM e Financeiro já usavam; o bloco `cna.tokens.js` do design system de apresentações também. O Ponto migra do português.

### Marca

| Token | HEX | Uso |
|---|---|---|
| `--red` | `#E6143C` | Marca primária. Botão primário, barra do topo, item ativo. |
| `--redDark` | `#A30E2A` | Texto vermelho sobre branco, hover do primário, destrutivo. |
| `--blue` | `#19408B` | Marca secundária. Dado, link, cabeçalho de tabela, foco. |
| `--blueDark` | `#142F66` | Hover do botão azul. |
| `--white` | `#FFFFFF` | Fundo de card e conteúdo. |
| `--ink` | `#1A1A1A` | Texto corrido. Nunca `#000`. |
| `--gray` | `#5A5A5A` | Texto de apoio, label, caption. |
| `--line` | `#E4E4E7` | Borda, divisor, linha de tabela. |
| `--surface` | `#F7F7F9` | Fundo da aplicação, listra par de tabela. |

> `--line` é o nome oficial. O `CNA-Taquara-Design-System.md` chama de `grayLine`, e os dois sistemas atuais têm `var(--grayLine)` sem definição, caindo em fallback silencioso. Vale corrigir o documento de apresentações também.

### Pastéis e acento

| Token | HEX | Uso |
|---|---|---|
| `--pastelRed` | `#FDECEF` | Fundo de tag/aviso de erro, item ativo em sidebar. |
| `--pastelBlue` | `#EAF0FA` | Fundo de tag informativa, destaque neutro. |
| `--yellow` | `#FFC800` | Acento **só sobre fundo escuro**. 1,55:1 sobre branco: nunca como texto ou ícone em fundo claro. |

### Semânticas

| Token | HEX | Fundo | Contraste sobre o fundo |
|---|---|---|---|
| `--ok` | `#1B7A3D` | `--okBg` `#E7F5EC` | 4,79:1 |
| `--warn` | `#B45309` | `--warnBg` `#FEF3E2` | 4,58:1 |
| `--danger` | `#A30E2A` | `--dangerBg` `#FDECEF` | 6,94:1 |
| `--muted` | `#8A8A8E` | — | **3,44:1 sobre branco: reprova em texto.** Só bolinha, ícone inativo e borda. Texto apagado usa `--gray`. |

O CRM usava `#1E7A46` e o Financeiro `#1B7A3D` para a mesma ideia de "verde de sucesso". Ficou `#1B7A3D`.

### Contraste verificado (WCAG, sobre branco)

| Cor | Razão | Veredito |
|---|---|---|
| `ink` | 17,4:1 | Texto corrido padrão |
| `blue` | 9,78:1 | Livre em qualquer tamanho |
| `redDark` | 7,91:1 | Livre em qualquer tamanho |
| `gray` | 6,90:1 | Livre para apoio |
| `red` | 4,64:1 | **Só título, botão e bloco curto.** Nunca corpo longo. |
| `muted` | 3,44:1 | Reprova em texto |
| `yellow` | 1,55:1 | Reprova. Só sobre escuro. |

### Tipografia

- `--display` **Poppins** — título, nav, botão, número grande
- `--body` **Inter** — corpo, formulário, tabela

Duas famílias, nunca três. Hora e valor usam `font-variant-numeric: tabular-nums` em vez de trazer uma monoespaçada: os dígitos alinham em coluna e a contagem de famílias fica respeitada.

Escala: `--fs-h1` 19px · `--fs-h2` 15px · `--fs-base` 14px · `--fs-sm` 12,5px · `--fs-xs` 11px · `--fs-stat` 28px.

### Forma e espaço

| Token | Valor | Uso |
|---|---|---|
| `--r-sm` | 8px | tag, badge, chip pequeno |
| `--r-md` | 10px | **botão, input, select** |
| `--r-lg` | 14px | card, painel, modal |
| `--r-pill` | 999px | chip de filtro, aba |

Espaçamento em múltiplos de 4: `--s1` 4 · `--s2` 8 · `--s3` 12 · `--s4` 16 · `--s5` 22 · `--s6` 32.

---

## 3. Shell e navegação

**Padrão: topo branco com borda vermelha inferior + abas em pílula no desktop + gaveta lateral no mobile.** É o que CRM e Ponto já fazem e o que escala quando o número de seções cresce.

**Variante opcional: sidebar permanente** para sistema com muitas seções (caso do Financeiro). Mas **fundo branco, item ativo em vermelho** — não fundo vermelho cheio.

Por que trocar a sidebar vermelha do Financeiro: ela obriga um jogo paralelo de tokens (`--onRed`, `--onRedLine`, `--onRedHover`, `--onRedActive`) que só existe naquele sistema, e coloca a navegação inteira em 4,64:1, que é o limite para texto grande e negrito. Nav é texto pequeno. A marca continua presente na barra vermelha do topo e no item ativo.

Trade-off honesto: o Financeiro perde a assinatura visual mais forte que tem hoje. Se você preferir manter, dá para manter a faixa vermelha e subir o peso da fonte da nav para 600, mas aí o Financeiro segue sendo exceção documentada, não regra.

---

## 4. Componentes canônicos

| Classe | O que é |
|---|---|
| `.topbar` `.brand` `.tabs` | Cabeçalho e nav desktop |
| `.sidebar` `.burger` `.drawer` | Nav lateral e gaveta mobile |
| `.card` `.panel` | Superfície branca com borda e raio 14 |
| `.kpis` `.kpi` | Grade de indicadores. Número em `--blue`, rótulo em caps cinza |
| `.btn` + `.primary` `.secondary` `.danger` `.ghost` `.sm` | Botões |
| `.chip` | Filtro alternável |
| `.field` | Bloco de formulário com label, input e hint |
| `.tableWrap` `table` `table.cardify` | Tabela, com virada para card no mobile via `data-label` |
| `.tag` + `.info` `.ok` `.warn` `.alert` | Etiqueta de estado |
| `.alert` + `.info` `.ok` `.warn` `.err` | Faixa de aviso |
| `.modal` | Diálogo, vira bottom sheet no mobile |
| `.empty` `.skeleton` | Estado vazio e carregamento |

**Hierarquia de botão:** um `.primary` por tela. `.secondary` (azul) para ação paralela. `.danger` só confirma em dois toques: primeiro clique aplica `.confirm`, segundo executa. Esse padrão já existe no CRM e vira regra.

---

## 5. Acessibilidade (obrigatório)

- **Foco visível em tudo.** `outline:3px solid var(--focus); outline-offset:2px`. O CRM hoje tem **zero** regra de `:focus-visible`: quem navega por teclado fica perdido. É o item mais urgente da lista.
- Texto corrido só em combinação ≥ 4,5:1. Vermelho vivo fica em título e bloco curto.
- Nada comunicado só por cor. Estado sempre com rótulo ou ícone junto.
- Alvo de toque mínimo 40×40px.
- Toda tabela responsiva usa `data-label` em cada `<td>`.
- `prefers-reduced-motion` respeitado.

---

## 6. Distribuição: como cada sistema consome

CRM e Financeiro são `index.html` único; o Ponto é PWA com arquivos separados. Duas opções foram consideradas:

**A — CSS externo compartilhado.** Um `cna-ds.css` publicado num endereço só, linkado pelos três. Sincroniza sozinho, mas cria dependência de runtime entre repositórios: se aquele Pages cair ou o cache sujar, os três sistemas perdem estilo de uma vez. Para o Ponto, que é PWA e precisa funcionar offline, é pior ainda.

**B — Bloco de tokens embutido, versionado.** ✅ **Recomendada.** O `cna-ds.css` é a fonte de verdade; cada sistema single-file embute o bloco entre marcadores:

```html
<style>
/* == CNA-DS v1.0 INÍCIO — não edite à mão, sincronize do cna-ds.css == */
:root{ ... }
/* == CNA-DS v1.0 FIM == */
```

Preserva a arquitetura de arquivo único, não tem dependência de rede e não pisca sem estilo no carregamento. O Ponto continua com o arquivo externo local, gerado do mesmo fonte.

O risco da B é divergência com o tempo. Mitigação: script que baixa os três `index.html`, extrai o bloco entre marcadores e compara com o canônico, mais uma varredura de hex hardcoded fora dos tokens. Rodar antes de cada deploy.

`[CONFIRMAR]` onde fica o repositório canônico do `cna-ds.css`. Sugestão: `pedrocoutinho2/cna-design`, servindo também de casa para o script verificador.

---

## 7. Estado dos sistemas (aplicado em 10/08/2026)

| | CRM | Financeiro | Ponto |
|---|---|---|---|
| Repo | `crmcnataquara` | `cna-financeiro` | `cna-t-ponto` |
| Commit | `65f542a6` | `8ca750b3` | `c3e5ef32` |
| Bloco canônico | ✅ | ✅ | ✅ |
| `:focus-visible` | ✅ (não existia) | ✅ | ✅ |
| Corpo em Inter | ✅ | ✅ (era Poppins) | ✅ |
| Escala de raios | ✅ | ✅ | parcial |
| Vars órfãs | zero | zero | zero |
| Shell | abas + gaveta | sidebar branca | abas |

O que ficou pendente por escolha, não por esquecimento:

- **Nomes de classe.** Os três seguem convenções próprias (`.card`/`.panel`/`.cartao`, `.btn`/`.acao`). São ~287 ocorrências só no Ponto. Token é o que precisa ser idêntico entre sistemas, porque garante que vermelho é o mesmo vermelho; nome de classe é convenção interna de cada arquivo. Refactor separado, se um dia valer a pena.
- **Hex restantes.** 31 distintos no CRM, quase todos `rgba()` de sombra e cinzas de barra de rolagem.
- **Raios do Ponto.** `--raio` virou `--r-sm` em todos os usos para preservar a aparência. Afinar por componente depois.

## 8. Regra para sistema novo

Começa copiando o `cna-ds.css`. Só escreve CSS próprio para o que for específico do domínio, e sempre em cima dos tokens, nunca com hex solto. Se precisar de um valor que não existe no token set, o valor não entra no arquivo: entra primeiro aqui.

---

## 9. Pendências `[CONFIRMAR]`

1. Repositório canônico do `cna-ds.css` e casa do script verificador.
2. Alinhar `grayLine` → `line` também no `CNA-Taquara-Design-System.md`.
3. Revogar os três PATs usados nesta rodada.
