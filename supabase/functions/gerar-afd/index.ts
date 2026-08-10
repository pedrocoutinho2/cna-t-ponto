// =====================================================================
// GET /gerar-afd?inicio=2026-08-01&fim=2026-08-31
//
// Monta o Arquivo-Fonte de Dados no leiaute da Portaria 671/2021
// (versão 004). Só a coordenação e o Auditor-Fiscal do Trabalho acessam.
//
// O arquivo sai em ISO-8859-1, linhas terminadas em CRLF, ordenado por
// NSR, sem linhas em branco. Nome do arquivo: AFD + INPI + CNPJ + REP_P.
//
// ATENÇÃO: a assinatura ICP-Brasil (.p7s destacado) NÃO é feita aqui.
// Ver docs/03-assinatura-icp.md — depende do e-CNPJ do empregador e deve
// rodar num serviço com acesso ao certificado, nunca numa Edge Function.
// =====================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("ORIGEM_PWA") ?? "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

const pad = (s: string, n: number) => s.slice(0, n).padEnd(n, " ");
const num = (s: string | number, n: number) => String(s).padStart(n, "0").slice(-n);

function crc16Kermit(txt: string): string {
  let crc = 0;
  for (const ch of txt) {
    crc ^= ch.charCodeAt(0) & 0xff;
    for (let i = 0; i < 8; i++) {
      crc = crc & 1 ? (crc >> 1) ^ 0x8408 : crc >> 1;
    }
  }
  return (crc & 0xffff).toString(16).toUpperCase().padStart(4, "0");
}

function dh(iso: string, tz: string): string {
  const d = new Date(iso);
  const f = new Intl.DateTimeFormat("sv-SE", {
    timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hour12: false,
  }).formatToParts(d);
  const g = (t: string) => f.find((p) => p.type === t)!.value;

  const local = new Date(`${g("year")}-${g("month")}-${g("day")}T${g("hour")}:${g("minute")}:00Z`);
  const mins = Math.round((local.getTime() - d.getTime()) / 60000);
  const sinal = mins < 0 ? "-" : "+";
  const off = num(Math.floor(Math.abs(mins) / 60), 2) + num(Math.abs(mins) % 60, 2);

  return `${g("year")}-${g("month")}-${g("day")}T${g("hour")}:${g("minute")}:00${sinal}${off}`;
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
  const papel = user?.user?.app_metadata?.papel;
  if (papel !== "coordenacao" && papel !== "auditor") {
    return Response.json({ erro: "Acesso restrito." }, { status: 403, headers: cors });
  }

  const url = new URL(req.url);
  const inicio = url.searchParams.get("inicio")!;   // YYYY-MM-DD
  const fim = url.searchParams.get("fim")!;

  const { data: cfg } = await admin.schema("ponto").from("rep")
    .select("*").eq("ativo", true).single();

  // ---- integridade antes de emitir ------------------------------------
  const { data: falhas } = await admin.schema("ponto")
    .rpc("arp_verificar_cadeia", { p_rep_id: cfg.id });

  if (falhas && falhas.length > 0) {
    return Response.json(
      { erro: "Cadeia de integridade quebrada. AFD não emitido.", falhas },
      { status: 409, headers: cors },
    );
  }

  const { data: registros } = await admin.schema("ponto").from("arp")
    .select("nsr, tipo, linha_afd, dh_marcacao, dh_gravacao")
    .eq("rep_id", cfg.id)
    .gte("dh_gravacao", `${inicio}T00:00:00-03:00`)
    .lte("dh_gravacao", `${fim}T23:59:59-03:00`)
    .order("nsr");

  const linhas: string[] = [];

  // ---- Registro tipo "1": cabeçalho (299-302 = CRC) -------------------
  let cab =
    num(0, 9) +                                   // 001-009
    "1" +                                         // 010
    cfg.tipo_id_empregador +                      // 011
    pad(cfg.cnpj_cpf_empregador, 14) +            // 012-025
    pad(cfg.cno_caepf || "", 14) +                // 026-039
    pad(cfg.razao_social, 150) +                  // 040-189
    pad(cfg.inpi, 17) +                           // 190-206  (INPI, no REP-P)
    //  ^ regra 7 do leiaute: preencher pela esquerda, completar com espaço.
    //    Não zero-pade este campo: o número do INPI não é puramente
    //    numérico e "000BR51..." reprova no validador.
    inicio +                                      // 207-216
    fim +                                         // 217-226
    dh(new Date().toISOString(), cfg.timezone) +  // 227-250
    cfg.versao_leiaute +                          // 251-253  "004"
    cfg.tipo_id_desenvolvedor +                   // 254
    pad(cfg.cnpj_cpf_desenvolvedor, 14) +         // 255-268
    pad("", 30);                                  // 269-298  (modelo: só REP-C)
  cab += crc16Kermit(cab);                        // 299-302
  linhas.push(cab);

  // ---- Registros gravados ---------------------------------------------
  const contagem: Record<string, number> = { "2": 0, "3": 0, "4": 0, "5": 0, "6": 0, "7": 0 };
  for (const r of registros ?? []) {
    linhas.push(r.linha_afd);
    contagem[r.tipo] = (contagem[r.tipo] ?? 0) + 1;
  }

  // ---- Registro tipo "9": trailer -------------------------------------
  linhas.push(
    "999999999" +
    num(contagem["2"], 9) + num(contagem["3"], 9) + num(contagem["4"], 9) +
    num(contagem["5"], 9) + num(contagem["6"], 9) + num(contagem["7"], 9) +
    "9",
  );

  // ---- Assinatura digital (100 posições) ------------------------------
  linhas.push(pad("ASSINATURA_DIGITAL_EM_ARQUIVO_P7S", 100));

  // ---- Serialização em ISO-8859-1 com CRLF ----------------------------
  const texto = linhas.join("\r\n") + "\r\n";
  const bytes = new Uint8Array(texto.length);
  for (let i = 0; i < texto.length; i++) {
    const c = texto.charCodeAt(i);
    bytes[i] = c <= 0xff ? c : 0x3f;   // fora do Latin-1 vira "?"
  }

  const nome = `AFD${cfg.inpi}${cfg.cnpj_cpf_empregador}REP_P.txt`;

  await admin.schema("ponto").from("auditoria").insert({
    ator: user!.user!.id,
    acao: "gerar_afd",
    alvo: nome,
    detalhe: { inicio, fim, registros: registros?.length ?? 0 },
  });

  return new Response(bytes, {
    headers: {
      ...cors,
      "Content-Type": "text/plain; charset=iso-8859-1",
      "Content-Disposition": `attachment; filename="${nome}"`,
    },
  });
});
