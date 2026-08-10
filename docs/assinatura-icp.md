---
chapeu: decisao
status: rascunho
atualizado: 2026-08-09
---

# Assinatura ICP-Brasil no REP-P

## Por que isso não mora numa Edge Function

Uma Edge Function é efêmera, roda em infra compartilhada e recebe segredos
por variável de ambiente. Chave privada de e‑CNPJ não deve passar por aí:
se vazar, alguém assina documento fiscal no CNPJ da escola.

O certificado fica num **serviço de assinatura separado**, com acesso
restrito por rede, chave nunca exposta ao runtime da aplicação, e log de
cada assinatura emitida.

Duas opções, em ordem de preferência:

1. **Certificado em nuvem** (Serpro, Certisign, Soluti, BirdID). A chave
   nunca sai do HSM do provedor; você chama uma API REST. É o caminho mais
   simples e o mais defensável numa auditoria.
2. **e‑CNPJ A1 (.pfx) num container próprio**, isolado, sem porta pública,
   acessível só pelo backend via rede interna.

Certificado A3 em token físico não serve: exige presença de hardware, o que
inviabiliza a geração automática de comprovante a cada marcação.

---

## O que assinar, e como

| Artefato | Formato | Quando |
|---|---|---|
| **AFD** | CAdES destacado (`.p7s` ao lado do `.txt`) | Sob demanda, ao gerar |
| **Comprovante** | PAdES (assinatura embutida no PDF) | A cada marcação |

O AFD carrega, na última linha, o texto literal
`ASSINATURA_DIGITAL_EM_ARQUIVO_P7S` completado com espaços até 100
caracteres — é o que a norma manda para REP‑A e REP‑P. A assinatura de
verdade vai no arquivo `.p7s` separado, entregue junto.

O `gerar-afd/index.ts` já emite essa linha. Falta só produzir o `.p7s`.

---

## AFD: CAdES destacado

```bash
# assina os bytes exatos do AFD (ISO-8859-1, CRLF) sem embutir o conteúdo
openssl cms -sign \
  -binary -outform DER -nodetach:no \
  -in  AFD<INPI><CNPJ>REP_P.txt \
  -out AFD<INPI><CNPJ>REP_P.txt.p7s \
  -signer ecnpj.pem -inkey ecnpj.key \
  -certfile cadeia-icp.pem \
  -md sha256
```

Conferência antes de entregar ao fiscal:

```bash
openssl cms -verify -binary -inform DER \
  -in AFD....p7s -content AFD....txt \
  -CAfile cadeia-icp-brasil.pem
```

Cuidado com o detalhe que quebra na hora errada: se qualquer processo
reescrever o `.txt` normalizando CRLF para LF, ou reconvertendo o encoding,
a assinatura deixa de conferir. Gere, assine e armazene os bytes originais.

---

## Comprovante: PAdES

O `pdf-lib` monta o PDF mas não assina. O fluxo em duas etapas:

1. `comprovante/index.ts` devolve o PDF sem assinatura.
2. O serviço de assinatura recebe esses bytes, aplica PAdES e devolve.

Em Node, `@signpdf/signpdf` com `@signpdf/signer-p12` resolve:

```js
import { SignPdf } from '@signpdf/signpdf';
import { P12Signer } from '@signpdf/signer-p12';
import { pdflibAddPlaceholder } from '@signpdf/placeholder-pdf-lib';

pdflibAddPlaceholder({
  pdfDoc,
  reason: 'Comprovante de Registro de Ponto do Trabalhador',
  contactInfo: 'ponto@cnataquara.com.br',
  name: razaoSocial,
  location: localPrestacao,
  signatureLength: 8192,
});

const assinado = await new SignPdf().sign(
  await pdfDoc.save(),
  new P12Signer(pfx, { passphrase: process.env.PFX_SENHA }),
);
```

Se for certificado em nuvem, o `P12Signer` vira um signer que delega o
digest para a API do provedor — a estrutura do fluxo é a mesma.

---

## Carimbo do tempo

A Portaria não exige carimbo do tempo (RFC 3161), mas ele resolve um
problema real: quando o certificado expirar, uma assinatura sem carimbo
perde verificabilidade. Documentos de jornada são guardados por anos.
Certificados valem 1 a 3.

Custa pouco por carimbo e evita a discussão de "esse AFD de 2026 foi
assinado mesmo em 2026?". Vale contratar junto com o certificado.

---

## O que ainda falta produzir

- **Atestado técnico**, declarando aderência ao Anexo IX, assinado
  digitalmente pelo desenvolvedor.
- **Termo de responsabilidade**, um por empregador atendido.

Se a DaRocha desenvolve e o CNA Taquara usa, a DaRocha é a desenvolvedora e
assina os dois. Isso é responsabilidade técnica formal sobre o sistema —
vale conversar com o contador ou com um advogado trabalhista antes de
assinar, porque a assinatura tem consequência.
