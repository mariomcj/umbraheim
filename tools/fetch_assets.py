"""Baixa a biblioteca inicial de assets (só CC0) e registra tudo em assets/assets_manifest.csv.

Uso (na raiz do projeto):  python -I tools/fetch_assets.py [polyhaven] [ambientcg] [kenney] [shaders]
Sem argumentos, faz tudo. É idempotente: o que já existe não é baixado de novo.

- Originais em assets/_raw/<fonte>/ (ignorados pela Godot via .gdignore e pelo git).
- O que o jogo usa vai para assets/textures, assets/hdri, assets/vfx.
- Nada de dados pessoais nas requisições: User-Agent genérico.
"""
import csv
import datetime
import io
import json
import os
import re
import shutil
import sys
import time
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
RAW = os.path.join(ASSETS, "_raw")
MANIFEST = os.path.join(ASSETS, "assets_manifest.csv")
UA = "Mozilla/5.0 (asset-fetch-script/1.0)"
TODAY = datetime.date.today().isoformat()

POLYHAVEN_TEXTURES = {
    "stone": ["stone_brick_wall_001", "castle_wall_slates", "medieval_blocks_03", "rustic_stone_wall_02", "mossy_rock"],
    "ground": ["cobblestone_floor_04", "monastery_stone_floor", "forrest_ground_01", "brown_mud_leaves_01"],
    "metal": ["rust_coarse_01", "rusty_metal_02", "metal_plate"],
    "wood": ["weathered_brown_planks", "rough_wood", "bark_brown_02"],
}
POLYHAVEN_HDRIS = ["moonless_golf", "kloppenheim_02", "overcast_soil_puresky"]
POLYHAVEN_MAPS = {"Diffuse": "albedo", "nor_gl": "normal", "Rough": "roughness"}

AMBIENTCG = {
    "ground": ["PavingStones139", "PavingStones138", "Tiles138", "ScatteredLeaves009"],
    "stone": ["Rock035", "Rock063"],
    "metal": ["Metal063"],
    "wood": ["Planks039", "WoodSiding008", "Bark016"],
}
AMBIENTCG_MAPS = {"_Color.jpg": "albedo", "_NormalGL.jpg": "normal", "_Roughness.jpg": "roughness"}

# pacote -> (pasta de destino, subpasta do zip com as imagens que interessam)
KENNEY = {
    "particle-pack": ("vfx/particles/kenney_particle_pack", "PNG (Transparent)"),
    "fantasy-ui-borders": ("textures/misc/ui/kenney_fantasy_ui_borders", "PNG"),
    "ui-pack-rpg-expansion": ("textures/misc/ui/kenney_ui_rpg_expansion", "PNG"),
    "game-icons": ("textures/misc/ui/kenney_game_icons", "PNG"),
}

SHADERS = [
    "godot-4-vertical-dissolve-shader", "enhanced-dissolve-ragdoll-alternative-tutorial",
    "pulse-aura-for-3d-character", "aura-3d",
    "cartoon-3d-fire", "fire-and-electric-shader",
    "dither-portals", "pixelated-portal",
    "glowing-shield-beam-buble-dark-magic-fresnel", "colored-fresnel-shader",
]


# ---------------------------------------------------------------- utilidades

def http(url, headers=None, opener=None, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    return (opener.open if opener else urllib.request.urlopen)(req, timeout=timeout).read()


def get_json(url):
    return json.loads(http(url))


def download(url, dest, opener=None, headers=None):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return False
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    data = http(url, headers=headers, opener=opener, timeout=180)
    with open(dest + ".part", "wb") as f:
        f.write(data)
    os.replace(dest + ".part", dest)
    return True


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def manifest_rows():
    if not os.path.exists(MANIFEST):
        return []
    with open(MANIFEST, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def add_manifest(rows):
    old = manifest_rows()
    known = {r["caminho_local"] for r in old}
    new = [r for r in rows if r["caminho_local"] not in known]
    fields = ["nome", "tipo", "fonte", "url", "autor", "licença", "caminho_local", "data_download"]
    with open(MANIFEST, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader()
        for r in old + new:
            w.writerow({k: r.get(k, "") for k in fields})
    return len(new)


def row(nome, tipo, fonte, url, autor, licenca, caminho):
    return {"nome": nome, "tipo": tipo, "fonte": fonte, "url": url, "autor": autor, "licença": licenca,
            "caminho_local": rel(caminho), "data_download": TODAY}


# ---------------------------------------------------------------- fontes

def polyhaven():
    rows = []
    for folder, ids in POLYHAVEN_TEXTURES.items():
        for aid in ids:
            info = get_json("https://api.polyhaven.com/info/" + aid)
            files = get_json("https://api.polyhaven.com/files/" + aid)
            out = os.path.join(ASSETS, "textures", folder, aid)
            for key, suffix in POLYHAVEN_MAPS.items():
                url = files[key]["1k"]["jpg"]["url"]
                raw = os.path.join(RAW, "polyhaven", aid, os.path.basename(url))
                download(url, raw)
                os.makedirs(out, exist_ok=True)
                shutil.copyfile(raw, os.path.join(out, "%s_%s.jpg" % (aid, suffix)))
            rows.append(row(info["name"], "textura (1K: albedo, normal GL, rugosidade)", "Poly Haven",
                            "https://polyhaven.com/a/" + aid, ", ".join(info["authors"].keys()), "CC0", out))
            print("  polyhaven", aid)
    for aid in POLYHAVEN_HDRIS:
        info = get_json("https://api.polyhaven.com/info/" + aid)
        files = get_json("https://api.polyhaven.com/files/" + aid)
        url = files["hdri"]["1k"]["hdr"]["url"]
        raw = os.path.join(RAW, "polyhaven", aid, os.path.basename(url))
        download(url, raw)
        dest = os.path.join(ASSETS, "hdri", "%s_1k.hdr" % aid)
        shutil.copyfile(raw, dest)
        rows.append(row(info["name"], "HDRI (1K)", "Poly Haven", "https://polyhaven.com/a/" + aid,
                        ", ".join(info["authors"].keys()), "CC0", dest))
        print("  polyhaven", aid)
    return rows


def ambientcg():
    rows = []
    for folder, ids in AMBIENTCG.items():
        for aid in ids:
            meta = get_json("https://ambientcg.com/api/v2/full_json?id=%s&include=downloadData" % aid)["foundAssets"][0]
            url = "https://ambientcg.com/get?file=%s_1K-JPG.zip" % aid
            raw = os.path.join(RAW, "ambientcg", "%s_1K-JPG.zip" % aid)
            download(url, raw)
            out = os.path.join(ASSETS, "textures", folder, aid)
            os.makedirs(out, exist_ok=True)
            with zipfile.ZipFile(raw) as z:
                for name in z.namelist():
                    for end, suffix in AMBIENTCG_MAPS.items():
                        if name.endswith(end):
                            with z.open(name) as src, open(os.path.join(out, "%s_%s.jpg" % (aid, suffix)), "wb") as dst:
                                shutil.copyfileobj(src, dst)
            rows.append(row(meta.get("displayName", aid), "material (1K JPG: albedo, normal GL, rugosidade)", "ambientCG",
                            "https://ambientcg.com/view?id=" + aid, "ambientCG (Lennart Demes)", "CC0", out))
            print("  ambientcg", aid)
            time.sleep(0.5)
    return rows


def kenney():
    rows = []
    from http.cookiejar import CookieJar
    for pack, (dest_rel, inner) in KENNEY.items():
        raw = os.path.join(RAW, "kenney", "kenney_%s.zip" % pack)
        if not os.path.exists(raw):
            jar = CookieJar()
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
            page = http(("https://kenney.nl/assets/%s" % pack), opener=opener).decode("utf-8", "ignore")
            did = re.search(r"data-download-id='([0-9a-f]+)'", page).group(1)
            link = json.loads(http("https://kenney.nl/download-link/" + did, opener=opener,
                                   headers={"Referer": "https://kenney.nl/assets/" + pack}))["url"]
            download(link, raw, opener=opener)
        dest = os.path.join(ASSETS, dest_rel)
        os.makedirs(dest, exist_ok=True)
        n = 0
        with zipfile.ZipFile(raw) as z:
            for name in z.namelist():
                low = name.lower()
                if low.endswith((".txt",)) and "license" in low:
                    with z.open(name) as src, open(os.path.join(dest, "License.txt"), "wb") as dst:
                        shutil.copyfileobj(src, dst)
                parts = name.split("/")
                if name.endswith(".png") and inner in parts:
                    sub = "/".join(parts[parts.index(inner) + 1:])
                    target = os.path.join(dest, sub)
                    os.makedirs(os.path.dirname(target), exist_ok=True)
                    with z.open(name) as src, open(target, "wb") as dst:
                        shutil.copyfileobj(src, dst)
                    n += 1
        rows.append(row("Kenney " + pack.replace("-", " ").title(), "imagens 2D (%d PNG)" % n, "Kenney",
                        "https://kenney.nl/assets/" + pack, "Kenney (kenney.nl)", "CC0", dest))
        print("  kenney", pack, n, "PNG")
    return rows


def shaders():
    rows = []
    dest_dir = os.path.join(ASSETS, "vfx", "shaders")
    os.makedirs(dest_dir, exist_ok=True)
    import html as htmlmod
    for slug in SHADERS:
        url = "https://godotshaders.com/shader/%s/" % slug
        raw = os.path.join(RAW, "godotshaders", slug + ".html")
        download(url, raw)
        page = open(raw, encoding="utf-8", errors="ignore").read()
        cls = re.search(r'class="[^"]*type-shader[^"]*"', page)
        lic = re.search(r"shader_license-([a-z0-9-]+)", cls.group(0) if cls else "")
        if not lic or lic.group(1) != "cc0":
            print("  PULADO (licença %s): %s" % (lic.group(1) if lic else "?", slug))
            continue
        author = re.search(r"/author/([A-Za-z0-9_-]+)/", page)
        title = re.search(r"<title>([^<|]+)", page)
        blocks = re.findall(r"<pre[^>]*>(.*?)</pre>", page, re.S) + re.findall(r"<code[^>]*>(.*?)</code>", page, re.S)
        code = ""
        for b in blocks:
            t = htmlmod.unescape(re.sub(r"<[^>]+>", "", b)).replace(" ", " ") # &nbsp; quebra o tokenizador
            if "shader_type" in t and len(t) > len(code):
                code = t
        if not code:
            print("  SEM CÓDIGO:", slug)
            continue
        name = slug.replace("-", "_")[:48] + ".gdshader"
        dest = os.path.join(dest_dir, name)
        header = "// %s\n// Fonte: %s\n// Autor: %s · Licença: CC0 (godotshaders.com)\n\n" % (
            htmlmod.unescape(title.group(1).strip()) if title else slug, url, author.group(1) if author else "?")
        with open(dest, "w", encoding="utf-8", newline="\n") as f:
            f.write(header + code.strip() + "\n")
        rows.append(row(htmlmod.unescape(title.group(1).strip()) if title else slug, "shader (Godot)", "godotshaders.com",
                        url, author.group(1) if author else "?", "CC0", dest))
        print("  shader", slug)
        time.sleep(0.5)
    return rows


if __name__ == "__main__":
    wanted = sys.argv[1:] or ["polyhaven", "ambientcg", "kenney", "shaders"]
    for src in wanted:
        print("==", src)
        rows = globals()[src]()
        print("   %d item(ns), %d novo(s) no manifesto" % (len(rows), add_manifest(rows)))
