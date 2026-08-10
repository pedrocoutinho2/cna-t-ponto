// =====================================================================
// POST /registrar-ponto
//
// REGRA DE OURO desta função: ela NUNCA recusa uma marcação por causa de
// localização, rede ou biometria. A Portaria 671/2021 proíbe o REP de
// restringir ou bloquear a marcação do trabalhador. Estar fora da cerca
// não impede o registro — apenas marca o registro para tratamento pela
// coordenação. Quem bloqueia ponto cria passivo trabalhista, não o evita.
//
// A função só recusa quando não consegue identificar quem está marcando
// (sessão inválida ou empregado inativo), porque aí não existe marcação
// a registrar.
// =====================================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyAuthenticationResponse } from "npm:@simplewebauthn/server@13";

const LIMIAR_FACE = 0.62;      // similaridade de cosseno mínima
const LIMIAR_LIVENESS = 0.70;  // confiança mínima do traço de vivacidade

const RP_ID = Deno.env.get("WEBAUTHN_RP_ID")!;          // ex.: ponto.cnataquara.com.br
const ORIGEM = Deno.env.get("ORIGEM_PWA")!;             // ex.: https://ponto.cnataquara.com.br

const cors = {
  "Access-Control-Allow-Origin": ORIGEM,
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface Corpo {
  desafio_id: string;
  nonce: string;
  descritor_facial: number[];          // 128 floats (face-api.js)
  liveness: {
    acoes_cumpridas: string[];
    confianca: number;                 // 0..1, calculada no cliente
    trace: Array<{ t: number; yaw: number; ear: number; area: number }>;
  };
  evidencia_b64?: string;              // frame do desafio, JPEG
  geo?: { latitude: number; longitude: number; acuracia_m: number } | null;
  webauthn?: unknown;                  // AuthenticationResponseJSON
}

function ipDaRequisicao(req: Request): string | null {
  const xff = req.headers.get("x-forwarded-for");
  return xff ? xff.split(",")[0].trim() : req.headers.get("cf-connecting-ip");
}

// Confere se o traço é fisicamente plausível: precisa haver variação real
// nos ângulos e um intervalo de tempo compatível com movimento humano.
function traceCoerente(t: Corpo["liveness"]["trace"], acoes: string[]): boolean {
  if (t.length < 12) return false;
  const dur = t[t.length - 1].t - t[0].t;
  if (dur < 1200 || dur > 40000) return false;

  const yaw = t.map((p) => p.yaw);
  const ear = t.map((p) => p.ear);
  const amplitudeYaw = Math.max(...yaw) - Math.min(...yaw);
  const amplitudeEar = Math.max(...ear) - Math.min(...ear);

  const precisaVirar = acoes.some((a) => a.startsWith("virar"));
  const precisaPiscar = acoes.includes("piscar");

  if (precisaVirar && amplitudeYaw < 18) return false;   // graus
  if (precisaPiscar && amplitudeEar < 0.12) return false;

  // quadros idênticos = vídeo em loop ou frame congelado
  const distintos = new Set(t.map((p) => `${p.yaw.toFixed(1)}|${p.ear.toFixed(3)}`));
  return distintos.size >= t.length * 0.6;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // ---- 1. Quem está marcando -----------------------------------------
  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
  const { data: user } = jwt ? await admin.auth.getUser(jwt) : { data: null };
  if (!user?.user) {
    return Response.json({ erro: "Sessão expirada. Entre de novo." }, { status: 401, headers: cors });
  }

  const { data: emp } = await admin.schema("ponto").from("empregados")
    .select("id, rep_id, cpf, nome, ativo")
    .eq("auth_user_id", user.user.id).maybeSingle();

  if (!emp?.ativo) {
    return Response.json(
      { erro: "Cadastro inativo. Procure a coordenação." },
      { status: 403, headers: cors },
    );
  }

  const corpo: Corpo = await req.json();
  const agora = new Date();
  const ip = ipDaRequisicao(req);

  // ---- 2. Liveness ----------------------------------------------------
  let liveness_ok = false;
  let desafio_id: string | null = null;

  const { data: desafio } = await admin.schema("ponto").from("liveness_desafios")
    .select("id, acoes, expira_em, consumido_em, empregado_id")
    .eq("id", corpo.desafio_id).eq("nonce", corpo.nonce).maybeSingle();

  if (
    desafio &&
    desafio.empregado_id === emp.id &&
    !desafio.consumido_em &&
    new Date(desafio.expira_em) > agora
  ) {
    desafio_id = desafio.id;
    const acoesBatem =
      JSON.stringify(desafio.acoes) === JSON.stringify(corpo.liveness.acoes_cumpridas);
    liveness_ok = acoesBatem &&
      corpo.liveness.confianca >= LIMIAR_LIVENESS &&
      traceCoerente(corpo.liveness.trace, desafio.acoes);

    // nonce queima na primeira tentativa, passe ou não
    await admin.schema("ponto").from("liveness_desafios")
      .update({ consumido_em: agora.toISOString() }).eq("id", desafio.id);
  }

  // ---- 3. Conferência facial -----------------------------------------
  let face_similaridade = 0;
  if (Array.isArray(corpo.descritor_facial) && corpo.descritor_facial.length === 128) {
    const { data: sim } = await admin.schema("ponto").rpc("conferir_face", {
      p_empregado_id: emp.id,
      p_descritor: `[${corpo.descritor_facial.join(",")}]`,
    });
    face_similaridade = Number(sim ?? 0);
  }
  const face_ok = face_similaridade >= LIMIAR_FACE;

  // ---- 4. Passkey (WebAuthn) ------------------------------------------
  let webauthn_ok = false;
  let dispositivo_id: string | null = null;

  if (corpo.webauthn) {
    const credId = (corpo.webauthn as { id: string }).id;
    const { data: disp } = await admin.schema("ponto").from("dispositivos")
      .select("id, credential_id, public_key, counter, empregado_id, ativo")
      .eq("credential_id", credId).maybeSingle();

    if (disp?.ativo && disp.empregado_id === emp.id) {
      try {
        const r = await verifyAuthenticationResponse({
          response: corpo.webauthn as never,
          expectedChallenge: corpo.nonce,
          expectedOrigin: ORIGEM,
          expectedRPID: RP_ID,
          credential: {
            id: disp.credential_id,
            publicKey: Uint8Array.from(atob(disp.public_key.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0)),
            counter: Number(disp.counter),
          },
        });
        webauthn_ok = r.verified;
        if (r.verified) {
          dispositivo_id = disp.id;
          await admin.schema("ponto").from("dispositivos")
            .update({ counter: r.authenticationInfo.newCounter }).eq("id", disp.id);
        }
      } catch {
        webauthn_ok = false;
      }
    }
  }

  // ---- 5. Cerca e rede ------------------------------------------------
  const { data: cercas } = await admin.schema("ponto").from("cercas")
    .select("id, latitude, longitude, raio_m, acuracia_maxima_m, ips")
    .eq("rep_id", emp.rep_id).eq("ativa", true);

  let dentro_cerca = false;
  let distancia: number | null = null;
  let cerca_id: string | null = null;
  let ip_autorizado = false;

  for (const c of cercas ?? []) {
    if (ip) {
      const { data: bate } = await admin.rpc("ip_em_faixas", { p_ip: ip, p_faixas: c.ips });
      if (bate) { ip_autorizado = true; cerca_id = c.id; }
    }
    if (corpo.geo && corpo.geo.acuracia_m <= c.acuracia_maxima_m) {
      const { data: d } = await admin.schema("ponto").rpc("distancia_m", {
        lat1: corpo.geo.latitude, lon1: corpo.geo.longitude,
        lat2: c.latitude, lon2: c.longitude,
      });
      const dist = Number(d);
      if (distancia === null || dist < distancia) { distancia = dist; cerca_id ??= c.id; }
      if (dist <= c.raio_m) { dentro_cerca = true; cerca_id = c.id; }
    }
  }

  // ---- 6. GRAVA A MARCAÇÃO (sempre) -----------------------------------
  const { data: registro, error: erroArp } = await admin.schema("ponto").from("arp")
    .insert({
      rep_id: emp.rep_id,
      tipo: "7",
      empregado_id: emp.id,
      cpf: emp.cpf,
      dh_marcacao: agora.toISOString(),   // hora do servidor, nunca do celular
      coletor: "browser",
      offline: false,
    })
    .select("id, nsr, hash, dh_marcacao")
    .single();

  if (erroArp) {
    return Response.json(
      { erro: "A marcação não foi gravada. Tente de novo e avise a coordenação." },
      { status: 500, headers: cors },
    );
  }

  // ---- 7. Contexto e classificação ------------------------------------
  const sinais = [dentro_cerca || ip_autorizado, face_ok, liveness_ok, webauthn_ok]
    .filter(Boolean).length;

  let evidencia: string | null = null;
  if (corpo.evidencia_b64 && (!liveness_ok || !face_ok || sinais < 4)) {
    // só guarda imagem quando algum sinal falhou — minimização (LGPD art. 6º, III)
    const caminho = `${emp.rep_id}/${registro.nsr}.jpg`;
    const bytes = Uint8Array.from(atob(corpo.evidencia_b64), (c) => c.charCodeAt(0));
    await admin.storage.from("liveness").upload(caminho, bytes, {
      contentType: "image/jpeg", upsert: false,
    });
    evidencia = caminho;
  }

  await admin.schema("ponto").from("marcacao_contexto").insert({
    arp_id: registro.id,
    rep_id: emp.rep_id,
    empregado_id: emp.id,
    latitude: corpo.geo?.latitude ?? null,
    longitude: corpo.geo?.longitude ?? null,
    acuracia_m: corpo.geo?.acuracia_m ?? null,
    distancia_cerca_m: distancia,
    dentro_cerca,
    cerca_id,
    ip,
    ip_autorizado,
    dispositivo_id,
    webauthn_ok,
    face_similaridade,
    face_ok,
    liveness_desafio_id: desafio_id,
    liveness_ok,
    liveness_evidencia: evidencia,
    sinais_ok: sinais,
    revisao: sinais >= 4 ? "nao_requer" : "pendente",
    user_agent: req.headers.get("user-agent"),
  });

  // ---- 8. Comprovante -------------------------------------------------
  return Response.json(
    {
      nsr: registro.nsr,
      hash: registro.hash,
      marcado_em: registro.dh_marcacao,
      nome: emp.nome,
      cpf: emp.cpf,
      sinais_ok: sinais,
      em_revisao: sinais < 4,
      comprovante_url: `${Deno.env.get("SUPABASE_URL")}/functions/v1/comprovante?nsr=${registro.nsr}`,
    },
    { headers: cors },
  );
});
