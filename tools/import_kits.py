"""Etapa 2 da biblioteca de assets: importa os kits baixados à mão (só os com licença CC0 conferida).

Uso (na raiz do projeto):  python -I tools/import_kits.py [--src <pasta dos downloads>] [kit ...]
  --src  pasta onde estão os pacotes (padrão: a pasta Downloads do Windows; depois downloads/ do projeto).
  kit    só esses kits (nomes de KITS abaixo). Sem nomes, faz todos.

O que faz:
- confere que o arquivo de licença do pacote diz CC0 (se não disser, PARA e avisa); exceção: os kits com
  `accept=QAL` (personagens e monstros da Quaternius, licença aceita pelo usuário);
- GLB com texturas embutidas (personagens e monstros): reduz só as imagens para no máximo 1024 px;
- kits glTF (Quaternius): copia cada .gltf + .bin e UMA pasta de texturas por kit, reduzidas a no máximo
  1024 px (os modelos compartilham os mesmos atlas; transformar cada um em .glb copiaria o atlas centenas de vezes);
- GLB prontos (Polymancer): copia como estão;
- biblioteca de animações (Universal Animation Library): copia o .glb sem root motion e renomeia os clipes
  principais para idle, walk, run, attack, cast, hit, death (o resto mantém o nome original);
- texturas soltas (Screaming Brain Studios): copia as imagens;
- registra cada kit em assets/assets_manifest.csv e copia a licença para a pasta de destino.
FBX/OBJ sem versão glTF continuam com tools/convert_models.py (Blender).
"""
import csv
import datetime
import json
import os
import shutil
import struct
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
MANIFEST = os.path.join(ASSETS, "assets_manifest.csv")
TODAY = datetime.date.today().isoformat()
MAX_SIDE = 1024
FIELDS = ["nome", "tipo", "fonte", "url", "autor", "licença", "caminho_local", "data_download"]

QUATERNIUS = {"fonte": "Quaternius", "url": "https://quaternius.com", "autor": "Quaternius"}
KITS = {
    "fantasy_props": dict(QUATERNIUS, kind="gltf", nome="Fantasy Props MegaKit (Standard)",
                          src="Fantasy Props MegaKit[Standard]", gltf="Exports/glTF", license="License_Standard.txt",
                          dest="models/props/quaternius_fantasy_props"),
    "medieval_village": dict(QUATERNIUS, kind="gltf", nome="Medieval Village MegaKit (Standard)",
                             src="Medieval Village MegaKit[Standard]/Medieval Village MegaKit[Standard]", gltf="glTF",
                             license="License_Standard.txt", dest="models/environment/quaternius_medieval_village"),
    "stylized_nature": dict(QUATERNIUS, kind="gltf", nome="Stylized Nature MegaKit (Standard)",
                            src="Stylized Nature MegaKit[Standard]", gltf="glTF", license="License_Standard.txt",
                            dest="models/environment/quaternius_stylized_nature"),
    "animations_1": dict(QUATERNIUS, kind="anim", nome="Universal Animation Library (Standard)",
                         src="Universal Animation Library[Standard]/Universal Animation Library[Standard]",
                         glb="Unreal-Godot/UAL1_Standard.glb", license="License.txt",
                         dest="models/characters/animations"),
    "animations_2": dict(QUATERNIUS, kind="anim", nome="Universal Animation Library 2 (Standard)",
                         src="Universal Animation Library 2[Standard]/Universal Animation Library 2[Standard]",
                         glb="Unreal-Godot/UAL2_Standard.glb", license="License.txt",
                         dest="models/characters/animations"),
    "polymancer": dict(kind="glb_tree", nome="Polymancer — Tavern & Street", fonte="Polymancer",
                       url="https://polymancer.app", autor="A. Chernomurov (Polymancer)",
                       src="texturas e assets/polymancer-tavern-and-street/polymancer-tavern-and-street", glb="GLB",
                       license="LICENSE.txt", dest="models/props/polymancer_tavern_street"),
    "sbs_1": dict(kind="images", nome="SBS Tiny Texture Pack (512x512)", fonte="Screaming Brain Studios",
                  url="", autor="Screaming Brain Studios", src="texturas e assets/SBS - Tiny Texture Pack - 512x512",
                  license="License.txt", dest="textures/misc/sbs_tiny_texture_pack_1"),
    "sbs_2": dict(kind="images", nome="SBS Tiny Texture Pack 2 (512x512)", fonte="Screaming Brain Studios",
                  url="", autor="Screaming Brain Studios", src="texturas e assets/SBS - Tiny Texture Pack 2 - 512x512",
                  license="License.txt", dest="textures/misc/sbs_tiny_texture_pack_2"),
    "sbs_3": dict(kind="images", nome="SBS Tiny Texture Pack 3 (Large)", fonte="Screaming Brain Studios",
                  url="", autor="Screaming Brain Studios", src="texturas e assets/SBS - Tiny Texture Pack 3 - Large",
                  license="License.txt", dest="textures/misc/sbs_tiny_texture_pack_3"),
}
# Licença própria da Quaternius, aceita pelo usuário em 2026-11-13 (uso comercial livre, sem crédito obrigatório;
# proibido revender/redistribuir os modelos como assets). Só estes kits podem ter licença diferente de CC0.
QAL = "QAL v1.0 (Quaternius Asset License)"
KITS.update({
    "characters": dict(QUATERNIUS, kind="glb_files", nome="Characters - Fantasy Races Kit (Standard)", accept=QAL,
                       src="Characters - Fantasy Races Kit[Standard]/Characters - Fantasy Races Kit[Standard]",
                       glb="Exports/GLB (Godot-Unreal)", variations="Textures/Variations", license="License_Standard.txt",
                       dest="models/characters/quaternius_fantasy_races"),
    "monsters": dict(QUATERNIUS, kind="glb_files", nome="Bestiary - Dungeon Monsters Kit (Standard)", accept=QAL,
                     src="Bestiary - Dungeon Monsters Kit[Standard]/Bestiary - Dungeon Monsters Kit[Standard]",
                     glb="Exports/GLB (Godot-Unreal)", variations="Textures", variation_filter="_BaseColor_",
                     license="License_Standard.txt", dest="models/monsters/quaternius_dungeon_monsters"),
})
# clipes da Universal Animation Library -> nome usado pelo jogo (os outros ficam com o nome original)
CLIP_NAMES = {
    "Idle_Loop": "idle", "Walk_Loop": "walk", "Jog_Fwd_Loop": "run", "Sprint_Loop": "sprint",
    "Sword_Attack": "attack", "Spell_Simple_Shoot": "cast", "Hit_Chest": "hit", "Death01": "death",
    "Sword_Regular_A": "attack_2", "Sword_Regular_B": "attack_3", "Sword_Regular_C": "attack_4",
}


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def check_license(src, name, accept=None):
    path = os.path.join(src, name)
    if not os.path.isfile(path):
        raise SystemExit("SEM LICENÇA: %s não tem %s. Nada foi copiado." % (src, name))
    text = open(path, encoding="utf-8", errors="ignore").read()
    if accept == QAL and "Quaternius Asset License" in text:
        return path
    if "CC0" not in text and "publicdomain/zero" not in text:
        raise SystemExit("LICENÇA NÃO É CC0 em %s. Nada foi copiado; revise à mão." % path)
    return path


def save_image(src, dst):
    """Copia a imagem; se passar de MAX_SIDE, reduz mantendo a proporção. Devolve (largura, altura) original."""
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with Image.open(src) as im:
        size = im.size
        if max(size) <= MAX_SIDE:
            shutil.copyfile(src, dst)
            return size
        scale = MAX_SIDE / max(size)
        out = im.resize((max(1, round(size[0] * scale)), max(1, round(size[1] * scale))), Image.LANCZOS)
        out.save(dst, optimize=True) if dst.lower().endswith(".png") else out.save(dst, quality=90)
    return size


def find_image(kit_root, gltf_dir, uri):
    direct = os.path.join(gltf_dir, uri)
    if os.path.isfile(direct):
        return direct
    base = os.path.basename(uri)
    for b, _dirs, files in os.walk(kit_root):
        if "unreal" in b.lower():  # normais no padrão DirectX: a Godot usa OpenGL
            continue
        if base in files:
            return os.path.join(b, base)
    return None


def import_gltf(kit, src, dest):
    gdir = os.path.join(src, kit["gltf"])
    images, models, missing, resized = {}, 0, [], 0
    for f in sorted(os.listdir(gdir)):
        if not f.endswith(".gltf"):
            continue
        g = json.load(open(os.path.join(gdir, f), encoding="utf-8"))
        for buf in g.get("buffers", []):
            shutil.copyfile(os.path.join(gdir, buf["uri"]), os.path.join(dest, buf["uri"]))
        for im in g.get("images", []):
            uri = im.get("uri")
            if uri and uri not in images:
                images[uri] = find_image(src, gdir, uri)
        shutil.copyfile(os.path.join(gdir, f), os.path.join(dest, f))
        models += 1
    for uri, path in images.items():
        if path is None:
            missing.append(uri)
            continue
        if max(save_image(path, os.path.join(dest, uri))) > MAX_SIDE:
            resized += 1
    for uri in missing:
        print("  AVISO: textura não encontrada:", uri)
    return "%d modelos glTF, %d texturas (%d reduzidas para %d px)" % (models, len(images) - len(missing), resized, MAX_SIDE)


def rename_glb_clips(src, dst):
    data = open(src, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    g = json.loads(data[20:20 + jlen])
    renamed = []
    for a in g.get("animations", []):
        if a.get("name") in CLIP_NAMES:
            renamed.append("%s->%s" % (a["name"], CLIP_NAMES[a["name"]]))
            a["name"] = CLIP_NAMES[a["name"]]
    js = json.dumps(g, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)
    rest = data[20 + jlen:]
    body = struct.pack("<I", len(js)) + b"JSON" + js + rest
    with open(dst, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body)
    return len(g.get("animations", [])), renamed


def shrink_glb_images(src, dst):
    """Copia o .glb reduzindo as imagens embutidas para no máximo MAX_SIDE (o resto do arquivo fica igual)."""
    import io
    data = open(src, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    g = json.loads(data[20:20 + jlen])
    bin_start = 20 + jlen + 8
    blen = struct.unpack("<I", data[20 + jlen:24 + jlen])[0]
    blob = data[bin_start:bin_start + blen]
    new_views = {}
    shrunk = 0
    for im in g.get("images", []):
        if "bufferView" not in im:
            continue
        bv = g["bufferViews"][im["bufferView"]]
        raw = blob[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        with Image.open(io.BytesIO(raw)) as pic:
            if max(pic.size) <= MAX_SIDE:
                continue
            k = MAX_SIDE / max(pic.size)
            out = pic.resize((max(1, round(pic.size[0] * k)), max(1, round(pic.size[1] * k))), Image.LANCZOS)
            buf = io.BytesIO()
            if im.get("mimeType") == "image/jpeg":
                out.convert("RGB").save(buf, "JPEG", quality=90)
            else:
                out.save(buf, "PNG", optimize=True)
            new_views[im["bufferView"]] = buf.getvalue()
            shrunk += 1
    out_blob = bytearray()
    for i, bv in enumerate(g["bufferViews"]):
        chunk = new_views.get(i)
        if chunk is None:
            chunk = blob[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        out_blob += b"\0" * (-len(out_blob) % 4)
        bv["byteOffset"] = len(out_blob)
        bv["byteLength"] = len(chunk)
        out_blob += chunk
    out_blob += b"\0" * (-len(out_blob) % 4)
    g["buffers"][0]["byteLength"] = len(out_blob)
    js = json.dumps(g, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)
    body = struct.pack("<I", len(js)) + b"JSON" + js + struct.pack("<I", len(out_blob)) + b"BIN\0" + bytes(out_blob)
    with open(dst, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body)
    return shrunk


def import_kit(key, src_root):
    kit = KITS[key]
    src = os.path.join(src_root, kit["src"])
    if not os.path.isdir(src):
        print("== %s: pasta não encontrada (%s), pulado" % (key, src))
        return None
    lic = check_license(src, kit["license"], kit.get("accept"))
    dest = os.path.join(ASSETS, kit["dest"])
    os.makedirs(dest, exist_ok=True)
    kind = kit["kind"]
    if kind == "gltf":
        info = import_gltf(kit, src, dest)
        tipo = "modelos 3D (glTF, texturas até %d px)" % MAX_SIDE
        path = dest
        shutil.copyfile(lic, os.path.join(dest, "License.txt"))
    elif kind == "anim":
        name = os.path.basename(kit["glb"])
        path = os.path.join(dest, name)
        n, renamed = rename_glb_clips(os.path.join(src, kit["glb"]), path)
        shutil.copyfile(lic, os.path.join(dest, "License_%s.txt" % os.path.splitext(name)[0]))
        info = "%d clipes; renomeados: %s" % (n, ", ".join(renamed))
        tipo = "animações (glTF, esqueleto de 65 ossos da Quaternius)"
    elif kind == "glb_files":
        gsrc = os.path.join(src, kit["glb"])
        n = shrunk = 0
        for f in sorted(os.listdir(gsrc)):
            if f.lower().endswith(".glb"):
                shrunk += shrink_glb_images(os.path.join(gsrc, f), os.path.join(dest, f))
                n += 1
        vsrc = os.path.join(src, kit["variations"])
        nv = 0
        for f in sorted(os.listdir(vsrc)):
            if f.lower().endswith(".png") and kit.get("variation_filter", "") in f:
                save_image(os.path.join(vsrc, f), os.path.join(dest, "variations", f))
                nv += 1
        shutil.copyfile(lic, os.path.join(dest, "License.txt"))
        info = "%d modelos GLB (%d texturas embutidas reduzidas para %d px), %d texturas de variação de cor" % (n, shrunk, MAX_SIDE, nv)
        tipo, path = "modelos 3D com esqueleto (GLB, texturas até %d px; animações em characters/animations)" % MAX_SIDE, dest
    elif kind == "glb_tree":
        gsrc = os.path.join(src, kit["glb"])
        n = 0
        for b, _dirs, files in os.walk(gsrc):
            for f in files:
                if f.lower().endswith(".glb"):
                    out = os.path.join(dest, os.path.relpath(b, gsrc).lower(), f)
                    os.makedirs(os.path.dirname(out), exist_ok=True)
                    shutil.copyfile(os.path.join(b, f), out)
                    n += 1
        shutil.copyfile(lic, os.path.join(dest, "License.txt"))
        info, tipo, path = "%d modelos GLB" % n, "modelos 3D (GLB, cores nos materiais)", dest
    else:  # images: PNG opaco vira JPG (qualidade 90); só fica PNG o que tem transparência de verdade
        n = 0
        for b, _dirs, files in os.walk(src):
            for f in files:
                if f.lower().endswith((".png", ".jpg", ".jpeg")) and "preview" not in f.lower():
                    out = os.path.join(dest, os.path.relpath(os.path.join(b, f), src))
                    with Image.open(os.path.join(b, f)) as im:
                        alpha = im.mode in ("RGBA", "LA") and im.getchannel("A").getextrema()[0] < 255
                        if not alpha and f.lower().endswith(".png") and max(im.size) <= MAX_SIDE:
                            os.makedirs(os.path.dirname(out), exist_ok=True)
                            im.convert("RGB").save(os.path.splitext(out)[0] + ".jpg", quality=90)
                            n += 1
                            continue
                    save_image(os.path.join(b, f), out)
                    n += 1
        shutil.copyfile(lic, os.path.join(dest, "License.txt"))
        info, tipo, path = "%d imagens" % n, "texturas 2D (%d imagens)" % n, dest
    print("== %s: %s" % (key, info))
    return {"nome": kit["nome"], "tipo": tipo, "fonte": kit["fonte"], "url": kit["url"], "autor": kit["autor"],
            "licença": kit.get("accept") or "CC0", "caminho_local": rel(path), "data_download": TODAY}


def add_manifest(rows):
    with open(MANIFEST, encoding="utf-8", newline="") as f:
        old = list(csv.DictReader(f))
    known = {r["caminho_local"] for r in old}
    new = [r for r in rows if r["caminho_local"] not in known]
    with open(MANIFEST, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, lineterminator="\n")
        w.writeheader()
        for r in old + new:
            w.writerow({k: r.get(k, "") for k in FIELDS})
    return len(new)


def main():
    args = sys.argv[1:]
    src_root = None
    if "--src" in args:
        i = args.index("--src")
        src_root = args[i + 1]
        del args[i:i + 2]
    if src_root is None:
        win = os.path.join(os.path.expanduser("~"), "Downloads")
        src_root = win if os.path.isdir(os.path.join(win, KITS["fantasy_props"]["src"])) else os.path.join(ROOT, "downloads")
    rows = [r for r in (import_kit(k, src_root) for k in (args or list(KITS))) if r]
    print("%d kit(s) importado(s), %d novo(s) no manifesto" % (len(rows), add_manifest(rows)))


if __name__ == "__main__":
    main()
