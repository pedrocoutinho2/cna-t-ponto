// =====================================================================
// POST /desafio-liveness
// Emite um desafio de vivacidade: nonce de uso único + 1 ação sorteada
// pelo servidor, com validade de 40 s. Foto impressa ou vídeo gravado não
// passa, porque o cliente não sabe de antemão qual ação vai cair.
//
// "piscar" saiu da lista: o olho fechado dura de 100 a 150 ms e o detector
// no celular gasta mais que isso por quadro, então o quadro decisivo caía
// entre duas leituras e a pessoa ficava presa no desafio. Uma ação bem
// detectada prova mais vivacidade que duas que travam.
// =====================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const ACOES = [
  "virar_direita",
  "virar_esquerda",
  "aproximar",
  "sorrir",
] as const;

const TTL_SEGUNDOS = 40;
const QUANTIDADE_ACOES = 1;

const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("ORIGEM_PWA") ?? "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function sortear<T>(lista: readonly T[], n: number): T[] {
  const copia = [...lista];
  const buf = new Uint32Array(n);
  crypto.getRandomValues(buf);
  const saida: T[] = [];
  for (let i = 0; i < n; i++) {
    saida.push(copia.splice(buf[i] % copia.length, 1)[0]);
  }
  return saida;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!jwt) {
    return Response.json({ erro: "Sessão ausente." }, { status: 401, headers: cors });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: user } = await admin.auth.getUser(jwt);
  if (!user?.user) {
    return Response.json({ erro: "Sessão inválida." }, { status: 401, headers: cors });
  }

  const { data: empregado } = await admin
    .schema("ponto")
    .from("empregados")
    .select("id, nome, ativo")
    .eq("auth_user_id", user.user.id)
    .maybeSingle();

  if (!empregado?.ativo) {
    return Response.json(
      { erro: "Cadastro não encontrado ou inativo. Procure a coordenação." },
      { status: 403, headers: cors },
    );
  }

  const nonce = crypto.randomUUID() + "." + crypto.randomUUID();
  const acoes = sortear(ACOES, QUANTIDADE_ACOES);
  const expira = new Date(Date.now() + TTL_SEGUNDOS * 1000);

  const { data: desafio, error } = await admin
    .schema("ponto")
    .from("liveness_desafios")
    .insert({
      empregado_id: empregado.id,
      nonce,
      acoes,
      expira_em: expira.toISOString(),
    })
    .select("id")
    .single();

  if (error) {
    return Response.json(
      { erro: "Não foi possível abrir o desafio. Tente de novo." },
      { status: 500, headers: cors },
    );
  }

  return Response.json(
    {
      desafio_id: desafio.id,
      nonce,
      acoes,
      expira_em: expira.toISOString(),
      nome: empregado.nome,
    },
    { headers: cors },
  );
});
