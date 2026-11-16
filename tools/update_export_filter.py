"""Mantém a build Web enxuta: só entra o que o jogo usa de assets/.

Uso (na raiz):  python -I tools/update_export_filter.py [--dry]

Descobre os arquivos de assets/ usados pelo jogo (cenas .tscn, materiais .tres, scripts .gd
e dados .json fora de scenes/dev, tests e tools, mais os modelos que RegionScenery escolhe
por nome) e as dependências deles (glTF -> .bin e texturas; glb/fbx -> texturas extraídas ao lado,
<modelo>_<imagem>.png; .tres/.tscn -> ext_resource).
Tudo o mais de assets/ vai para o exclude_filter dos perfis em export_presets.cfg.
Rode de novo sempre que o jogo passar a usar um asset novo.
"""
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = ["tests/*", "tools/*", "docs/*", "build/*", "scenes/dev/*", "downloads/*", "assets/_raw/*"]
LICENSE_FILES = {"OFL.txt"}  # licença que precisa ir junto da fonte (entra pelo include_filter)
KEEP = {"assets/shaders"}  # shaders do próprio jogo (com includes entre si): sempre entram
SKIP_DIRS = {".godot", "build", "tests", "tools", "docs", "downloads", "scenes/dev", "assets/_raw"}


def res_to_rel(p):
    return p[len("res://"):] if p.startswith("res://") else p


def scan_sources():
    refs = set()
    for dp, dn, fn in os.walk(ROOT):
        rel = os.path.relpath(dp, ROOT).replace("\\", "/")
        if rel == "assets" or any(rel == d or rel.startswith(d + "/") for d in SKIP_DIRS):
            dn[:] = []
            continue
        for f in fn:
            if not f.endswith((".tscn", ".tres", ".gd", ".json", ".gdshader")):
                continue
            text = io.open(os.path.join(dp, f), encoding="utf-8", errors="ignore").read()
            refs.update(re.findall(r'res://assets/[^"\'\s)]+', text))
            if f == "vfx.json":  # formas das partículas, por nome (VfxPlayer.SHAPES_DIR)
                cfg = json.loads(text)
                for shape in cfg.get("particle_shapes", {}).values():
                    if shape.get("texture"):
                        refs.add("res://assets/vfx/particles/kenney_particle_pack/%s.png" % shape["texture"])
            if f == "ambience.json":  # partículas por nome e modelos da decoração ("pasta/Nome", pastas em decor_dirs)
                cfg = json.loads(text)
                for t in cfg.get("particle_types", {}).values():
                    if t.get("texture"):
                        refs.add("res://assets/vfx/particles/kenney_particle_pack/%s.png" % t["texture"])
                dirs = cfg.get("decor_dirs", {})
                names = []
                for reg in cfg.get("regions", {}).values():
                    for layer in reg.get("decor", {}).get("layers", []):
                        names.extend(layer.get("models", []))
                    names.extend(fire["model"] for fire in reg.get("fires", []) if fire.get("model"))
                for n in names:
                    folder, _, base = n.partition("/")
                    if folder in dirs:
                        refs.add(dirs[folder] + base + ".gltf")
            if f == "audio.json":  # sons citados pelo caminho dentro de assets/audio (SoundDirector.AUDIO_DIR)
                for snd in json.loads(text).get("sounds", {}).values():
                    for file in snd.get("files", []):
                        refs.add("res://assets/audio/" + file)
            if f == "region_scenery.gd":  # modelos escolhidos por nome
                base = re.search(r'const NATURE := "([^"]+)"', text).group(1)
                block = text[text.index("const MODELS"):text.index("}", text.index("const MODELS"))]
                for name in re.findall(r'"([A-Za-z0-9_]+)"', block):
                    if name[0].isupper():
                        refs.add(base + name + ".gltf")
    return {res_to_rel(r) for r in refs}


def deps(rel, seen):
    if rel in seen or not os.path.exists(os.path.join(ROOT, rel)):
        return
    seen.add(rel)
    full = os.path.join(ROOT, rel)
    folder = os.path.dirname(rel)
    if rel.endswith(".gltf"):
        j = json.load(io.open(full, encoding="utf-8"))
        for b in j.get("buffers", []) + j.get("images", []):
            if "uri" in b and not b["uri"].startswith("data:"):
                deps(os.path.normpath(os.path.join(folder, b["uri"])).replace("\\", "/"), seen)
    elif rel.endswith((".glb", ".fbx")):
        # texturas embutidas que a Godot extrai ao lado do modelo: <nome do modelo>_<imagem>.png
        stem = os.path.splitext(os.path.basename(rel))[0] + "_"
        for f in os.listdir(os.path.join(ROOT, folder)):
            if f.startswith(stem) and f.lower().endswith((".png", ".jpg", ".jpeg")):
                deps(folder + "/" + f, seen)
    elif rel.endswith((".tscn", ".tres")):
        text = io.open(full, encoding="utf-8", errors="ignore").read()
        for p in re.findall(r'path="(res://assets/[^"]+)"', text):
            deps(res_to_rel(p), seen)


def exclusions(used):
    out = []

    def walk(rel):
        full = os.path.join(ROOT, rel)
        entries = sorted(os.listdir(full))
        has_used = any(u == rel or u.startswith(rel + "/") for u in used)
        if not has_used:
            out.append(rel + "/*")
            return
        for e in entries:
            r = rel + "/" + e
            if os.path.isdir(os.path.join(ROOT, r)):
                if r == "assets/_raw" or r in KEEP:
                    continue
                walk(r)
            elif not e.endswith((".import", ".uid", ".gdignore")) and r not in used and e not in LICENSE_FILES:
                out.append(r)
    walk("assets")
    return out


def main():
    used = set()
    for r in scan_sources():
        deps(r, used)
    excl = BASE + exclusions(used)
    print("assets usados pelo jogo: %d arquivos; padrões de exclusão: %d" % (len(used), len(excl)))
    if "--dry" in sys.argv:
        for u in sorted(used):
            print("  usa", u)
        return
    path = os.path.join(ROOT, "export_presets.cfg")
    cfg = io.open(path, encoding="utf-8").read()
    value = ", ".join(excl)
    extra = {"Web": ", addons/godot-sqlite/*", "Windows Desktop": "", "Servidor Linux": ""}
    parts = re.split(r'(?m)^(?=\[preset\.\d+\]$)', cfg)
    for i, part in enumerate(parts):
        m = re.search(r'(?m)^name="([^"]+)"', part)
        if not m or "exclude_filter=" not in part:
            continue
        name = m.group(1)
        parts[i] = re.sub(r'(?m)^exclude_filter="[^"]*"', lambda _: 'exclude_filter="%s%s"' % (value, extra.get(name, "")), part, count=1)
    io.open(path, "w", encoding="utf-8", newline="\n").write("".join(parts))
    print("export_presets.cfg atualizado")


if __name__ == "__main__":
    main()
