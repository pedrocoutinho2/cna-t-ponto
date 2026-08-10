# Logos neste projeto

Regra: **sempre PNG com fundo transparente**, na versão que melhor
contrasta com o fundo. Nunca recolorir por CSS ou filtro — filtro sobre
PNG suja as bordas e o design system proíbe recolorir a marca.

| Arquivo | Quando usar | Onde já é usado |
|---|---|---|
| `logo-cna.png` | fundo branco ou claro | cabeçalho das quatro telas |
| `logo-cna-branca.png` | fundo vermelho, azul ou escuro | reservado; aplicar com a classe `.sobre-cor` no contêiner |
| `icon-192.png` · `icon-512.png` | ícone do app no celular | manifest (ainda faltam) |
| `icon-maskable.png` | ícone adaptável do Android | manifest (ainda falta) |

## Como trocar

Basta substituir o arquivo mantendo o nome. Nada no código muda.
Enquanto `logo-cna.png` não existir, as telas mostram um lockup
tipográfico de reserva ("CNA idiomas" em vermelho e azul), então nada
quebra — só fica menos bonito.

## Ícones do app

O `manifest.webmanifest` já referencia os três ícones, mas eles ainda não
existem: quem instalar o PWA hoje vê o ícone genérico do navegador.

Assim que a logo chegar, gerar com:

```bash
python3 - <<'PY'
from PIL import Image
logo = Image.open('assets/logo-cna.png').convert('RGBA')
for lado in (192, 512):
    fundo = Image.new('RGBA', (lado, lado), (255, 255, 255, 255))
    m = logo.copy(); m.thumbnail((int(lado*.78), int(lado*.78)), Image.LANCZOS)
    fundo.paste(m, ((lado-m.width)//2, (lado-m.height)//2), m)
    fundo.save(f'assets/icon-{lado}.png')

# Maskable precisa de área de segurança: o Android recorta as bordas.
# Fundo vermelho da marca + logo branca ocupando só 60% do quadro.
branca = Image.open('assets/logo-cna-branca.png').convert('RGBA')
fundo = Image.new('RGBA', (512, 512), (230, 20, 60, 255))   # #E6143C
m = branca.copy(); m.thumbnail((307, 307), Image.LANCZOS)
fundo.paste(m, ((512-m.width)//2, (512-m.height)//2), m)
fundo.save('assets/icon-maskable.png')
PY
```

O maskable é o único caso em que a marca aparece sobre vermelho — por isso
a versão branca é necessária, e não opcional.
