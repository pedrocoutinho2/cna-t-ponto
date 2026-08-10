// =====================================================================
// POST /webauthn-registro
//
// Dois passos, distinguidos pelo campo "etapa":
//   { etapa: "opcoes" }              -> devolve as opções de criação
//   { etapa: "verificar", resposta } -> valida e grava a credencial
//
// A chave privada nunca sai do Secure Enclave do aparelho. O que guardamos
// é só a chave pública, que não serve para assinar nada. É isso que faz o
// passkey resolver o problema da senha emprestada: não existe segredo
// transferível por WhatsApp.
// =====================================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  generateRegistrationOptions,
  verifyRegistrationResponse,
} from "npm:@simplewebauthn/server@13";

const RP_ID = Deno.env.get("WEBAUTHN_RP_ID")!;
const RP_NOME = "Ponto CNA Taquara";
const ORIGEM = Deno.env.get("ORIGEM_PWA")!;

const cors = {
  "Access-Control-Allow-Origin": ORIGEM,
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function b64url(buf: Uint8Array): string {
  return btoa(String.fromCharCode(...buf))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
  const { data: user } = jwt ? await admin.auth.getUser(jwt) : { data: null };
  if (!user?.user) {
    return Response.json({ erro: "Sessão expirada." }, { status: 401, headers: cors });
  }

  const { data: emp } = await admin.schema("ponto").from("empregados")
    .select("id, nome, cpf, ativo")
    .eq("auth_user_id", user.user.id).maybeSingle();

  if (!emp?.ativo) {
    return Response.json(
      { erro: "Seu login ainda não está ligado a um cadastro. Procure a coordenação." },
      { status: 403, headers: cors },
    );
  }

  const corpo = await req.json();

  // ---- Etapa 1: opções -------------------------------------------------
  if (corpo.etapa === "opcoes") {
    const { data: jaTem } = await admin.schema("ponto").from("dispositivos")
      .select("credential_id, transports").eq("empregado_id", emp.id).eq("ativo", true);

    const opcoes = await generateRegistrationOptions({
      rpName: RP_NOME,
      rpID: RP_ID,
      userID: new TextEncoder().encode(emp.id),
      userName: emp.cpf,
      userDisplayName: emp.nome,
      attestationType: "none",
      excludeCredentials: (jaTem ?? []).map((d) => ({
        id: d.credential_id,
        transports: d.transports as never,
      })),
      authenticatorSelection: {
        residentKey: "preferred",
        userVerification: "required",   // exige biometria ou PIN do aparelho
        authenticatorAttachment: "platform",
      },
    });

    // O desafio é guardado no servidor: quem responde tem que ter recebido.
    await admin.schema("ponto").from("liveness_desafios").insert({
      empregado_id: emp.id,
      nonce: `webauthn:${opcoes.challenge}`,
      acoes: ["registro_passkey"],
      expira_em: new Date(Date.now() + 5 * 60_000).toISOString(),
    });

    return Response.json({ opcoes, nome: emp.nome }, { headers: cors });
  }

  // ---- Etapa 2: verificação -------------------------------------------
  if (corpo.etapa === "verificar") {
    const { data: desafio } = await admin.schema("ponto").from("liveness_desafios")
      .select("id, nonce, expira_em, consumido_em")
      .eq("empregado_id", emp.id)
      .like("nonce", "webauthn:%")
      .is("consumido_em", null)
      .order("emitido_em", { ascending: false })
      .limit(1).maybeSingle();

    if (!desafio || new Date(desafio.expira_em) < new Date()) {
      return Response.json(
        { erro: "O registro demorou demais. Comece de novo." },
        { status: 400, headers: cors },
      );
    }

    await admin.schema("ponto").from("liveness_desafios")
      .update({ consumido_em: new Date().toISOString() }).eq("id", desafio.id);

    let r;
    try {
      r = await verifyRegistrationResponse({
        response: corpo.resposta,
        expectedChallenge: desafio.nonce.replace("webauthn:", ""),
        expectedOrigin: ORIGEM,
        expectedRPID: RP_ID,
        requireUserVerification: true,
      });
    } catch (e) {
      return Response.json(
        { erro: `Não foi possível validar o aparelho: ${(e as Error).message}` },
        { status: 400, headers: cors },
      );
    }

    if (!r.verified || !r.registrationInfo) {
      return Response.json({ erro: "Aparelho não validado." }, { status: 400, headers: cors });
    }

    const cred = r.registrationInfo.credential;

    const { error } = await admin.schema("ponto").from("dispositivos").insert({
      empregado_id: emp.id,
      credential_id: cred.id,
      public_key: b64url(cred.publicKey),
      counter: cred.counter,
      transports: cred.transports ?? [],
      apelido: corpo.apelido ?? "Celular",
      // Aparelho novo entra ativo, mas fica registrado quando e por quem.
      // Trocar de celular é normal; trocar toda semana não é, e o relatório
      // da coordenação mostra isso.
      aprovado_em: new Date().toISOString(),
    });

    if (error) {
      return Response.json(
        {
          erro: error.message.includes("duplicate")
            ? "Este aparelho já está registrado."
            : "Não foi possível salvar o aparelho.",
        },
        { status: 400, headers: cors },
      );
    }

    await admin.schema("ponto").from("auditoria").insert({
      ator: user.user.id,
      acao: "registrar_passkey",
      alvo: emp.id,
      detalhe: { apelido: corpo.apelido ?? "Celular" },
    });

    return Response.json({ ok: true, nome: emp.nome }, { headers: cors });
  }

  return Response.json({ erro: "Etapa desconhecida." }, { status: 400, headers: cors });
});
