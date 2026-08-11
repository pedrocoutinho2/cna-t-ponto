#!/usr/bin/env python3
"""
verificar-ds.py — confere se os sistemas do CNA Taquara estão sincronizados
com o bloco de tokens canônico do cna-ds.css.

Uso:  python3 verificar-ds.py [caminho/para/cna-ds.css]

Sai com código 1 se algum sistema divergir. Roda antes de todo deploy.

O que checa, por sistema:
  1. bloco entre os marcadores CNA-DS existe e é idêntico ao canônico
  2. nenhuma var(--x) usada sem definição (fora as injetadas em runtime)
  3. hex hardcoded fora do :root, que deveriam ser token
  4. regra de :focus-visible presente
"""
import re, sys, urllib.request

INICIO = "== CNA-DS v1.0 INICIO"
FIM = "== CNA-DS v1.0 FIM =="

# variáveis injetadas em runtime pelo JS, não são token do design system
RUNTIME = {"cc", "sc", "rc", "bc", "uc"}

SISTEMAS = [
    ("CRM",        "pedrocoutinho2/crmcnataquara", ["index.html"]),
    ("Financeiro", "pedrocoutinho2/cna-financeiro", ["index.html"]),
    ("Ponto",      "pedrocoutinho2/cna-t-ponto",
     ["assets/cna.css", "index.html", "admin.html", "cadastro.html", "entrar.html"]),
]


def baixar(repo, caminho):
    url = f"https://raw.githubusercontent.com/{repo}/main/{caminho}"
    return urllib.request.urlopen(url, timeout=30).read().decode("utf-8")


def bloco(texto):
    """Extrai o miolo entre os marcadores, normalizado para comparação."""
    i = texto.find(INICIO)
    j = texto.find(FIM)
    if i == -1 or j == -1:
        return None
    # o texto do próprio comentário do marcador não faz parte do bloco
    fim_comentario = texto.find("*/", i)
    if fim_comentario == -1 or fim_comentario > j:
        return None
    miolo = texto[fim_comentario + 2:j]
    miolo = re.sub(r"/\*.*?\*/", "", miolo, flags=re.S)  # ignora comentários internos
    return re.sub(r"\s+", " ", miolo).strip()


def css_de(texto, caminho):
    """CSS do arquivo: o bloco <style> no single-file, o arquivo todo no .css."""
    if caminho.endswith(".css"):
        return texto
    return "".join(re.findall(r"<style>(.*?)</style>", texto, re.S))


def main():
    canon_path = sys.argv[1] if len(sys.argv) > 1 else "cna-ds.css"
    canon = bloco(open(canon_path, encoding="utf-8").read())
    if canon is None:
        print(f"ERRO: marcadores não encontrados em {canon_path}")
        return 1

    falhou = False
    for nome, repo, arquivos in SISTEMAS:
        print(f"\n=== {nome}  ({repo})")
        principal = arquivos[0]
        tokens, usadas, hexes, foco = set(), set(), {}, False

        for caminho in arquivos:
            try:
                txt = baixar(repo, caminho)
            except Exception as e:
                print(f"  ! não baixou {caminho}: {e}")
                falhou = True
                continue

            if caminho == principal:
                b = bloco(txt)
                if b is None:
                    print("  ✗ bloco CNA-DS ausente")
                    falhou = True
                elif b != canon:
                    print("  ✗ bloco CNA-DS divergente do canônico")
                    falhou = True
                else:
                    print("  ✓ bloco CNA-DS idêntico")
                m = re.search(r":root\{(.*?)\n\}", css_de(txt, caminho), re.S)
                if m:
                    tokens |= set(re.findall(r"--([\w-]+)\s*:", m.group(1)))

            css = css_de(txt, caminho)
            usadas |= set(re.findall(r"var\(--([\w-]+)", css))
            if "focus-visible" in css:
                foco = True
            fora = re.sub(r":root\{.*?\n\}", "", css, flags=re.S)
            for h in re.findall(r"#[0-9a-fA-F]{3,8}\b", fora):
                hexes[h.upper()] = hexes.get(h.upper(), 0) + 1

        orfas = sorted(usadas - tokens - RUNTIME)
        if orfas:
            print(f"  ✗ var() sem definição: {', '.join(orfas)}")
            falhou = True
        else:
            print("  ✓ nenhuma var() órfã")

        if foco:
            print("  ✓ :focus-visible presente")
        else:
            print("  ✗ :focus-visible ausente")
            falhou = True

        if hexes:
            top = sorted(hexes.items(), key=lambda x: -x[1])[:6]
            print(f"  · {len(hexes)} hex fora do :root — maiores: "
                  + ", ".join(f"{h}×{n}" for h, n in top))

    print("\n" + ("FALHOU: há divergência" if falhou else "OK: os três sincronizados"))
    return 1 if falhou else 0


if __name__ == "__main__":
    sys.exit(main())
