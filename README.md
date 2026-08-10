---
chapeu: sistema
status: rascunho
atualizado: 2026-08-09
---

# Ponto CNA — REP-P

Sistema de registro de ponto por PWA, com prova de presença (geo + IP) e
prova de identidade (liveness + face + passkey), gravando num ARP imutável
no leiaute da Portaria MTP 671/2021.

**Escopo:** equipe administrativa do CNA Taquara. Não inclui professores.

---

## Leia isto antes de codar mais nada

A pesquisa no leiaute oficial derrubou uma premissa do desenho original.

### A cerca não pode bloquear a marcação

A Portaria 671 é explícita: o REP **não pode restringir horários nem impedir
a marcação do trabalhador**. Um sistema que recusa o registro porque a pessoa
está a 200 m da escola não é um controle mais rígido — é um sistema que
apaga prova de jornada.

O efeito prático é o inverso do pretendido. Se o funcionário alega que
trabalhou e o sistema não tem o registro porque bloqueou, a Súmula 338 do
TST joga a presunção contra a escola: sem registro, vale a jornada que o
empregado alegar. Você teria construído uma máquina de gerar passivo.

**Então o desenho aqui é outro:** a marcação **sempre** entra na ARP e
**sempre** vai para o AFD. Geolocalização, IP, face e passkey não decidem
*se* grava — decidem apenas se aquele registro entra na fila de conferência
da coordenação. A tabela `marcacao_contexto` guarda esses sinais separada da
`arp`, justamente para que o contexto possa ser anotado e revisado sem nunca
tocar no registro fiscal.

Na prática você ganha mais do que com bloqueio: um relatório de "quem bateu
de fora da escola, quando e quantas vezes" é conversa de gestão com dado na
mão, e não uma discussão sobre por que o app não deixou a pessoa registrar.

### Três coisas que dinheiro e tempo resolvem, mas código não

| Exigência | O que é | Sem isso |
|---|---|---|
| **Registro no INPI** | Certificado de registro de programa de computador. O número vai no cabeçalho do AFD (posições 190‑206) e no comprovante. | O AFD sai com campo inválido. O sistema não é REP‑P. |
| **Certificado ICP‑Brasil (e‑CNPJ)** | Assina o AFD (.p7s destacado) e o comprovante (PAdES). | Arquivos sem valor fiscal numa fiscalização. |
| **Atestado técnico + termo de responsabilidade** | Documento do desenvolvedor declarando aderência ao Anexo IX, assinado digitalmente, um por empregador. | Fiscal pede na hora; você não tem. |

O código deste repositório está pronto para receber os três. Nenhum deles é
opcional, e o INPI é o de prazo mais longo — comece por ele.

### O que este repositório não cobre

O REP‑P grava e entrega o AFD. Quem produz o **Espelho de Ponto** e o **AEJ**
(Arquivo Eletrônico de Jornada) é o *Programa de Tratamento de Registro de
Ponto* — outro componente, que consome o AFD e cruza com jornada contratual,
ausências e banco de horas. A view `ponto.v_espelho` é o insumo, não o
produto final.

---

## Arquitetura

```
  celular do funcionário
        │
        │  PWA (GitHub Pages) — face-api.js roda no aparelho
        │  o descritor de 128 dimensões sai extraído do cliente;
        │  a foto não sobe, exceto quando algum sinal falha
        ▼
  Edge Functions (Deno)
        ├── desafio-liveness   nonce + 2 ações sorteadas, TTL 40 s
        ├── registrar-ponto    valida, classifica, GRAVA SEMPRE
        ├── comprovante        PDF por marcação
        └── gerar-afd          leiaute 004, ISO-8859-1, CRLF
        ▼
  Postgres (Supabase)
        ├── ponto.arp                 append-only, NSR + cadeia SHA-256
        ├── ponto.marcacao_contexto   geo/IP/face/liveness — mutável
        ├── ponto.biometria_facial    pgvector, só descritores
        └── ponto.dispositivos        credenciais WebAuthn
```

### As quatro provas

| Prova | Como | O que derruba |
|---|---|---|
| **Onde — rede** | IP público da unidade conferido no servidor | Falsificar exige VPN para dentro da escola |
| **Onde — GPS** | Raio de 90 m, leituras acima de 60 m de erro descartadas | Fake GPS passa; por isso é sinal secundário |
| **Quem — rosto** | Cosseno ≥ 0,62 contra descritores cadastrados | Pessoa errada |
| **Quem — vivacidade** | 2 ações sorteadas pelo servidor, com traço de yaw/EAR conferido no servidor | Foto impressa, vídeo gravado, deepfake pré-renderizado |
| **Quem — aparelho** | Passkey no Secure Enclave | Senha emprestada, login em outro celular |

O liveness é o que resolve o seu problema original. Senha se passa por
WhatsApp; um desafio sorteado no instante da marcação, não.

**Limite honesto:** a detecção roda no cliente, então um atacante com
conhecimento técnico consegue forjar o traço de yaw/EAR chamando a API
direto. O servidor confere plausibilidade física (amplitude mínima, duração,
quadros não repetidos) e guarda a evidência quando algo falha, mas isso é
dissuasão e auditoria, não impossibilidade. Para a realidade de uma escola
com equipe administrativa, o custo do ataque já é muito maior que o
benefício. Se um dia precisar de garantia forte, o caminho é tablet fixo na
recepção, onde o dispositivo é a prova.

---

## Integridade da ARP

Cada marcação recebe NSR sequencial sem buracos (contador com lock de
transação, não `SEQUENCE` — rollback deixaria furo no AFD) e um SHA-256
calculado sobre os campos 1 a 7 do registro tipo 7 **mais o hash do registro
anterior**. Alterar qualquer marcação passada quebra a cadeia de todas as
seguintes.

`UPDATE` e `DELETE` na `ponto.arp` disparam exceção por trigger — inclusive
para o `service_role`. `ponto.arp_verificar_cadeia()` roda antes de qualquer
emissão de AFD e recusa a geração se encontrar divergência.

### O que já foi testado

As migrations rodaram num Postgres 16 real com pgvector, e os testes
passaram:

| Verificação | Resultado |
|---|---|
| `crc16_kermit('123456789')` | `2189` — igual ao exemplo da norma |
| Linha do registro tipo 7 | 137 caracteres |
| Cabeçalho tipo 1 / trailer tipo 9 / assinatura | 302 / 64 / 100 |
| Campo DH | 24 caracteres, `2026-08-09T15:42:00-0300` |
| NSR | sequencial, sem buracos |
| Cadeia de hash | encadeada; adulteração forçada foi detectada |
| `UPDATE` / `DELETE` / `TRUNCATE` na ARP | os três levantam exceção |

Um bug foi encontrado e corrigido no caminho: a versão inicial usava
`CREATE RULE ... DO INSTEAD NOTHING` contra `DELETE`. A rule é reescrita
antes do trigger e engolia o comando em silêncio — o operador via
`DELETE 0` e concluía que a linha não existia, sem nunca saber que a ARP é
imutável. Falha silenciosa em log fiscal é pior que falha ruidosa. Agora
são triggers, e os três comandos levantam exceção.

### Uma ambiguidade do leiaute que você precisa resolver no piloto

A regra 7 do anexo manda preencher os campos pela esquerda, completando com
espaço. Mas vários campos são declarados como tipo N (numérico), onde a
prática de mercado é zerar à esquerda. Os dois não podem estar certos ao
mesmo tempo.

Aqui a regra 7 foi seguida ao pé da letra — o campo do INPI, por exemplo,
sai alinhado à esquerda com espaços à direita, porque zerá-lo produziria
`000BR512026000123`, que é lixo. Antes de virar a chave, passe um AFD de
teste pelo validador do Ministério do Trabalho e ajuste se ele reclamar.
É meia hora de trabalho que evita descobrir o problema numa fiscalização.

---

## LGPD

Biometria é dado pessoal sensível (art. 5º, II). O desenho já minimiza:

- **Descritor, não foto.** O vetor de 128 dimensões não reconstrói o rosto.
- **Imagem só quando falha.** `registrar-ponto` só sobe o frame quando algum
  sinal não bateu, com expurgo automático em 90 dias.
- **Bucket fechado.** Sem política de leitura para `authenticated`; a
  coordenação só acessa por URL assinada, com registro em `ponto.auditoria`.
- **Revogação pelo titular.** RLS permite ao próprio funcionário revogar o
  descritor.

Falta você produzir, e não dá para pular: consentimento específico e
destacado (separado do contrato de trabalho), RIPD, política de retenção
escrita, e **alternativa real para quem recusar a biometria** — recusa não
pode virar punição nem impedir a pessoa de registrar ponto. Na prática:
livro de ponto ou marcação pela coordenação, com o mesmo NSR e o mesmo AFD.

---

## Ordem de implantação

1. Aplicar as migrations, cadastrar o REP e a cerca da unidade.
2. Descobrir o IP público da escola e travar com a operadora (IP fixo).
3. Cadastro biométrico presencial, com termo de consentimento assinado.
4. Piloto de duas semanas em paralelo ao controle atual, com a fila de
   revisão aberta — é onde você calibra raio e limiar de face.
5. Iniciar o registro no INPI e comprar o e‑CNPJ A1.
6. Plugar a assinatura (ver `docs/assinatura-icp.md`) e desligar o paralelo.

---

## Vale a pena construir?

Vale ter a conta na mesa antes de investir mais horas. Um REP‑P de mercado
custa na faixa de R$ 8 a R$ 15 por funcionário/mês e já vem com INPI,
certificado, atestado técnico, AEJ e espelho prontos. Para 18 pessoas, algo
como R$ 2 a 3 mil por ano.

Construir faz sentido se você quer o controle de presença sob medida (que é
exatamente o que os prontos não fazem bem), se o CNA Taquara é o primeiro de
vários, ou se isso vira produto da DaRocha. Não faz sentido se o objetivo é
só cumprir a obrigação legal com o menor atrito.

Um meio-termo que costuma ser o melhor negócio: contratar um REP‑P pronto
para o lado fiscal e manter só a camada de presença (liveness + cerca) como
sistema próprio, alimentando o REP contratado por API.
