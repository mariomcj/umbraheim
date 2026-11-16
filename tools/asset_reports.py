"""Gera CREDITS.md (raiz) e assets/REPORT.md a partir de assets/assets_manifest.csv e das pastas.

Uso (na raiz do projeto):  python -I tools/asset_reports.py
Rode de novo sempre que baixar ou processar assets.
"""
import csv
import datetime
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
MANIFEST = os.path.join(ASSETS, "assets_manifest.csv")
IMG_LIMIT = 1024
TRI_LIMIT = 20000

# Pendências que não dá para descobrir olhando as pastas (atualize à mão).
PENDING = [
    "**Puglin sem animação:** o Imp e o Puglin (Bestiary gratuito) não trazem animações, mas o esqueleto deles tem os mesmos "
    "nomes de ossos da Universal Animation Library (só faltam os mindinhos). O jogo copia os clipes da UAL1 para eles "
    "(`ModelRig`); o Imp já está em uso (Bruto Acorrentado), o Puglin ainda não.",
    "**Sketchfab (11 modelos, sem arquivo de licença):** pela busca na API do Sketchfab, todos os nomes batem com modelos "
    "CC-BY (crédito obrigatório), mas 6 nomes têm mais de um modelo igual e um dos \"Modular Dungeon\" é NonCommercial. "
    "Preciso do link exato de cada um para confirmar a licença e o autor. Vários são pesados para a Web (70 mil a 1,4 milhão de triângulos).",
    "**`texturas e assets/fornitures` e `weaponsassetspackbyStyloo` (sem licença):** não importados; diga de onde vieram e a licença.",
    "**Shaders com licença MIT, para você revisar** (fora da regra CC0/CC-BY, não baixados): "
    "[Dissolve with Glowing Edge](https://godotshaders.com/shader/dissolve-with-glowing-edge/), "
    "[3D Burn Dissolve](https://godotshaders.com/shader/3d-burn-dissolve/), "
    "[3D Vertical Dissolve](https://godotshaders.com/shader/3d-vertical-dissolve/), "
    "[Frost Overlay for any Mesh](https://godotshaders.com/shader/frost-overlay-for-any-mesh/).",
    "**Texturas 2048 px para personagens principais:** só se você aprovar (hoje tudo está em até 1024 px).",
    "**Áudio:** nenhum som ou música ainda (fora desta etapa).",
]
NOTES = [
    "Kits da Quaternius (Fantasy Props, Medieval Village, Stylized Nature) entram como glTF (.gltf + .bin) com uma pasta "
    "de texturas por kit, porque todos os modelos de um kit usam os mesmos atlas: em .glb, cada arquivo levaria uma cópia. "
    "A Godot importa .gltf direto. Importados por `tools/import_kits.py`; FBX/OBJ avulsos vão por `tools/convert_models.py` (Blender).",
    "Animações: `assets/models/characters/animations/UAL1_Standard.glb` e `UAL2_Standard.glb` (86 clipes, esqueleto de 65 ossos, "
    "o mesmo dos personagens elfo e orc; os monstros usam outro, de 55 ossos). Clipes principais renomeados: idle, walk, run, sprint, attack, "
    "attack_2..4, cast, hit, death.",
    "Blender 5.3 extraído do instalador (sem instalar) em `%LOCALAPPDATA%\Programs\blender-5.3.0-portable`.",
    "Os 10 shaders compilam no renderer Compatibility (testado na vitrine `scenes/dev/asset_showcase.tscn`). "
    "O `aura_3d` vinha com espaços inquebráveis do HTML e foi corrigido; ele é uma camada de contorno (vai por cima de outro material).",
    "Nada de `assets/textures`, `hdri`, `vfx`, `models`, `audio` e `scenes/dev` entra na build: estão no `exclude_filter` dos perfis de exportação "
    "até serem usados pelo jogo. Ao integrar um asset, tire a pasta dele do filtro (ou mova o arquivo para fora delas).",
    "Build Web depois do filtro: 45,11 MB (antes 38,83 MB). A diferença não vem desta biblioteca: é a arte nova do UMBRAHEIM em "
    "`client/ui/art/` (tela de carregamento de 1 MB, que também vira o `index.png` da Web, e duas imagens de título), que entram "
    "no `.pck` (6,5 MB). Vale reduzir essas imagens ou exportá-las com compressão com perda.",
]


def size_of(path):
    total = 0
    count = 0
    for base, _dirs, files in os.walk(path):
        for f in files:
            if f.endswith(".import"):
                continue
            total += os.path.getsize(os.path.join(base, f))
            count += 1
    return total, count


def mb(n):
    return "%.1f MB" % (n / 1048576)


def image_size(path):
    with open(path, "rb") as f:
        head = f.read(32)
        if head[:8] == b"\x89PNG\r\n\x1a\n":
            w, h = struct.unpack(">II", head[16:24])
            return w, h
        if head[:2] == b"\xff\xd8":
            f.seek(2)
            while True:
                marker = f.read(2)
                if len(marker) < 2 or marker[0] != 0xFF:
                    return None
                if marker[1] in (0xC0, 0xC1, 0xC2):
                    f.read(3)
                    h, w = struct.unpack(">HH", f.read(4))
                    return w, h
                length = struct.unpack(">H", f.read(2))[0]
                f.seek(length - 2, 1)
    return None


def glb_triangles(path):
    """Conta triângulos de um .glb ou .gltf pelos acessores de índice (aproximado: ignora instâncias)."""
    import json
    if path.endswith(".gltf"):
        gltf = json.load(open(path, encoding="utf-8"))
    else:
        with open(path, "rb") as f:
            data = f.read()
        if data[:4] != b"glTF":
            return None
        length = struct.unpack("<I", data[12:16])[0]
        gltf = json.loads(data[20:20 + length])
    tris = 0
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            if "indices" in prim:
                tris += gltf["accessors"][prim["indices"]]["count"] // 3
            else:
                tris += gltf["accessors"][prim["attributes"]["POSITION"]]["count"] // 3
    return tris


def main():
    with open(MANIFEST, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))

    # ---------------------------------------------------------------- CREDITS.md
    by_license = {}
    for r in rows:
        by_license.setdefault(r["licença"], []).append(r)
    out = ["# Créditos", "",
           "Assets de terceiros usados no projeto, agrupados por licença. A lista completa, com caminhos e datas, está em "
           "[assets/assets_manifest.csv](assets/assets_manifest.csv).", ""]
    out += ["## CC-BY (crédito obrigatório)", ""]
    ccby = [r for lic, rs in by_license.items() if lic.upper().startswith("CC-BY") or lic.upper().startswith("CC BY") for r in rs]
    if ccby:
        for r in ccby:
            out.append("- **%s** — %s (%s), %s, licença %s." % (r["nome"], r["autor"], r["fonte"], r["url"], r["licença"]))
    else:
        out.append("Nenhum item CC-BY por enquanto.")
    out += ["", "## CC0 (domínio público)", "",
            "A CC0 não exige crédito. Mesmo assim, agradecemos aos autores:", ""]
    by_source = {}
    for r in by_license.get("CC0", []):
        by_source.setdefault(r["fonte"], []).append(r)
    for src in sorted(by_source):
        out += ["### " + src, ""]
        for r in sorted(by_source[src], key=lambda x: x["nome"].lower()):
            out.append("- [%s](%s) — %s" % (r["nome"], r["url"], r["autor"]))
        out.append("")
    qal = [r for lic, rs in by_license.items() if lic.startswith("QAL") for r in rs]
    if qal:
        out += ["## Quaternius Asset License (QAL v1.0)", "",
                "Licença própria da Quaternius (https://quaternius.com/license.html), aceita para o projeto: uso comercial "
                "livre e sem crédito obrigatório; proibido revender ou redistribuir os modelos como assets. Agradecemos:", ""]
        for r in sorted(qal, key=lambda x: x["nome"].lower()):
            out.append("- [%s](%s) — %s" % (r["nome"], r["url"], r["autor"]))
        out.append("")
    ofl = [r for lic, rs in by_license.items() if lic.startswith("OFL") for r in rs]
    if ofl:
        out += ["## SIL Open Font License (OFL 1.1), só fontes", "",
                "Fontes do Google Fonts. A OFL permite uso e distribuição junto do jogo; o texto da licença acompanha cada "
                "fonte (OFL.txt na pasta dela, também incluído na build). Não vendemos as fontes separadamente.", ""]
        for r in sorted(ofl, key=lambda x: x["nome"].lower()):
            out.append("- [%s](%s) — %s" % (r["nome"], r["url"], r["autor"]))
        out.append("")
    others = [lic for lic in by_license if lic != "CC0" and not lic.upper().startswith("CC") and not lic.startswith("QAL") and not lic.startswith("OFL")]
    if others:
        out += ["## Outras licenças (revisar!)", ""] + ["- %s: %d item(ns)" % (lic, len(by_license[lic])) for lic in others] + [""]
    with open(os.path.join(ROOT, "CREDITS.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out).rstrip() + "\n")

    # ---------------------------------------------------------------- REPORT.md
    raw_size, raw_count = size_of(os.path.join(ASSETS, "_raw"))
    lines = ["# Relatório da biblioteca de assets", "",
             "Gerado por `tools/asset_reports.py` em %s." % datetime.date.today().isoformat(), "",
             "## Totais", "",
             "- **Baixado (originais em `assets/_raw/`):** %s em %d arquivos." % (mb(raw_size), raw_count),
             "- **Itens no manifesto:** %d (%s)." % (len(rows), ", ".join("%s: %d" % (k, len(v)) for k, v in sorted(by_license.items()))), "",
             "## Tamanho por pasta (o que o jogo usa)", "", "| Pasta | Tamanho | Arquivos |", "|---|---|---|"]
    folders = ["textures/ground", "textures/stone", "textures/metal", "textures/wood", "textures/misc", "hdri",
               "vfx/shaders", "vfx/particles", "models/characters", "models/monsters", "models/props",
               "models/environment", "models/weapons", "audio/sfx", "audio/music"]
    total = 0
    for fo in folders:
        s, c = size_of(os.path.join(ASSETS, fo))
        total += s
        lines.append("| `assets/%s` | %s | %d |" % (fo, mb(s), c))
    lines += ["| **total** | **%s** | |" % mb(total), ""]

    big_imgs = []
    max_side = 0
    n_imgs = 0
    for base, _dirs, files in os.walk(ASSETS):
        if os.sep + "_raw" in base:
            continue
        for f in files:
            if f.lower().endswith((".png", ".jpg", ".jpeg")):
                dims = image_size(os.path.join(base, f))
                if dims:
                    n_imgs += 1
                    max_side = max(max_side, *dims)
                    if max(dims) > IMG_LIMIT:
                        big_imgs.append((os.path.relpath(os.path.join(base, f), ROOT).replace("\\", "/"), dims))
    heavy_models = []
    n_models = 0
    for base, _dirs, files in os.walk(os.path.join(ASSETS, "models")):
        for f in files:
            if f.endswith((".glb", ".gltf")):
                n_models += 1
                t = glb_triangles(os.path.join(base, f))
                if t and t > TRI_LIMIT:
                    heavy_models.append((os.path.relpath(os.path.join(base, f), ROOT).replace("\\", "/"), t))
    lines += ["## Itens pesados", ""]
    lines.append("- **Imagens:** %d conferidas, maior lado %d px. %s" % (n_imgs, max_side,
                 "Nenhuma acima de %d px." % IMG_LIMIT if not big_imgs else "%d acima de %d px:" % (len(big_imgs), IMG_LIMIT)))
    for p, d in big_imgs[:30]:
        lines.append("  - `%s` (%d×%d)" % (p, d[0], d[1]))
    ic, icn = size_of(os.path.join(ASSETS, "textures/misc/ui/kenney_game_icons"))
    lines.append("- **Kenney Game Icons:** %d PNG (%s) porque o pacote traz cada ícone em várias resoluções e cores; "
                 "ao usar na interface, fique só com uma resolução e apague o resto." % (icn, mb(ic)))
    lines.append("- **Modelos acima de ~%d triângulos:** %d modelos conferidos; %s" % (
        TRI_LIMIT, n_models, "nenhum acima do limite." if not heavy_models else "%d acima:" % len(heavy_models)))
    for p, t in heavy_models:
        lines.append("  - `%s`: %d triângulos — sugiro decimar no Blender (modificador Decimate)." % (p, t))
    lines += ["", "## Observações", ""] + ["- " + n for n in NOTES]
    lines += ["", "## Pendências", ""] + ["- " + p for p in PENDING]
    with open(os.path.join(ASSETS, "REPORT.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines).rstrip() + "\n")
    print("CREDITS.md e assets/REPORT.md gerados (%d itens, baixado %s, em uso %s)" % (len(rows), mb(raw_size), mb(total)))


if __name__ == "__main__":
    main()
