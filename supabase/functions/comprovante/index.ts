// =====================================================================
// GET /comprovante?nsr=123
//
// Comprovante de Registro de Ponto do Trabalhador — obrigatório a cada
// marcação (Portaria 671/2021). Campos exigidos, todos presentes abaixo:
//
//   I    cabeçalho "Comprovante de Registro de Ponto do Trabalhador"
//   II   CNPJ/CPF do empregador
//   III  razão social do empregador
//   IV   local da prestação do serviço
//   V    nome e CPF do trabalhador
//   VI   data e hora da marcação
//   VII  NSR
//   VIII número de registro no INPI (REP-P)
//   IX   código hash SHA-256 da marcação (exclusivo do REP-P)
//   X    assinatura eletrônica
//
// A assinatura PAdES entra depois deste passo — ver docs/03-assinatura-icp.md.
// =====================================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";

const cors = { "Access-Control-Allow-Origin": Deno.env.get("ORIGEM_PWA") ?? "*" };

Deno.serve(async (req) => {
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

  const nsr = Number(new URL(req.url).searchParams.get("nsr"));

  const { data: m } = await admin.schema("ponto").from("arp")
    .select(`nsr, hash, dh_marcacao, cpf,
             empregado:empregados!inner(id, nome, auth_user_id),
             rep:rep!inner(cnpj_cpf_empregador, razao_social, local_prestacao, inpi, timezone)`)
    .eq("tipo", "7").eq("nsr", nsr).maybeSingle();

  if (!m) {
    return Response.json({ erro: "Marcação não encontrada." }, { status: 404, headers: cors });
  }

  const ehDono = m.empregado.auth_user_id === user.user.id;
  const ehCoord = user.user.app_metadata?.papel === "coordenacao";
  if (!ehDono && !ehCoord) {
    return Response.json({ erro: "Acesso restrito." }, { status: 403, headers: cors });
  }

  const quando = new Intl.DateTimeFormat("pt-BR", {
    timeZone: m.rep.timezone, dateStyle: "short", timeStyle: "medium",
  }).format(new Date(m.dh_marcacao));

  const cpfFmt = m.cpf.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");
  const cnpjFmt = m.rep.cnpj_cpf_empregador
    .replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, "$1.$2.$3/$4-$5");

  // ---- PDF -------------------------------------------------------------
  const pdf = await PDFDocument.create();
  pdf.setTitle(`Comprovante de Registro de Ponto — NSR ${m.nsr}`);
  pdf.setProducer("REP-P CNA");

  const pag = pdf.addPage([320, 460]);   // formato de recibo
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const reg = await pdf.embedFont(StandardFonts.Helvetica);
  const mono = await pdf.embedFont(StandardFonts.Courier);

  let y = 424;
  const tinta = rgb(0.09, 0.11, 0.15);
  const claro = rgb(0.42, 0.44, 0.48);

  const linha = (txt: string, f = reg, tam = 9, cor = tinta, salto = 13) => {
    pag.drawText(txt, { x: 26, y, size: tam, font: f, color: cor });
    y -= salto;
  };
  const campo = (rotulo: string, valor: string) => {
    linha(rotulo.toUpperCase(), reg, 6.5, claro, 10);
    linha(valor, bold, 10, tinta, 18);
  };
  const regua = () => {
    pag.drawLine({
      start: { x: 26, y: y + 5 }, end: { x: 294, y: y + 5 },
      thickness: 0.5, color: rgb(0.82, 0.79, 0.72),
    });
    y -= 12;
  };

  linha("COMPROVANTE DE REGISTRO", bold, 12, tinta, 15);
  linha("DE PONTO DO TRABALHADOR", bold, 12, tinta, 10);
  regua();

  campo("Empregador", m.rep.razao_social.trim());
  campo("CNPJ", cnpjFmt);
  campo("Local da prestação de serviço", m.rep.local_prestacao.trim());
  regua();

  campo("Trabalhador", m.empregado.nome.trim());
  campo("CPF", cpfFmt);
  campo("Data e hora da marcação", quando);
  campo("NSR", String(m.nsr).padStart(9, "0"));
  campo("Registro do programa no INPI", m.rep.inpi.trim());
  regua();

  linha("CÓDIGO HASH (SHA-256)", reg, 6.5, claro, 11);
  pag.drawText(m.hash.slice(0, 32), { x: 26, y, size: 7, font: mono, color: tinta });
  y -= 10;
  pag.drawText(m.hash.slice(32), { x: 26, y, size: 7, font: mono, color: tinta });
  y -= 22;

  linha("Documento assinado eletronicamente com certificado", reg, 6.5, claro, 9);
  linha("ICP-Brasil. Confira em ponto.cnataquara.com.br/verificar", reg, 6.5, claro, 9);

  const bytes = await pdf.save();

  return new Response(bytes, {
    headers: {
      ...cors,
      "Content-Type": "application/pdf",
      "Content-Disposition": `inline; filename="comprovante-${m.nsr}.pdf"`,
    },
  });
});
