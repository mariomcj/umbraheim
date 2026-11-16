"""Etapa 2 da biblioteca de assets: converte modelos baixados à mão para glTF binário (.glb).

Dois modos:

1) Na raiz do projeto, com Python normal (prepara e chama o Blender para cada arquivo):
       python -I tools/convert_models.py --blender "C:/Program Files/Blender Foundation/Blender 4.x/blender.exe"
   - extrai os ZIPs de downloads/ para assets/_raw/<nome do zip>/;
   - acha FBX, OBJ, GLTF/GLB e BLEND;
   - converte cada um para .glb e põe em assets/models/<categoria>/ (a categoria vem do nome da pasta/arquivo:
     characters, monsters, props, environment, weapons; sem pista, vai para props);
   - para pacotes sem arquivo de licença, NÃO converte: lista para você informar a licença;
   - avisa os modelos acima de ~20k triângulos (sugestão: modificador Decimate no Blender).
   Opções: --only <texto> (só arquivos cujo caminho contém o texto), --dry-run (só lista),
           --src <pasta> (lê os pacotes dessa pasta no lugar de downloads/).
   No PowerShell 5.1, chamar o Blender à mão com "--" não funciona (o PowerShell engole o "--"); use este modo 1.

2) Dentro do Blender (o modo 1 chama assim; não precisa rodar à mão):
       blender -b --factory-startup -P tools/convert_models.py -- <entrada> <saída.glb>
   - importa, junta animações do Mixamo e renomeia as ações para idle, walk, run, attack, cast, hit, death
     (pelo nome do arquivo ou da ação: "Standing Idle" -> idle, "Sword Slash" -> attack, "Spell Cast" -> cast...);
   - exporta .glb com animações, normais e materiais; imprime "TRIS <n>" para o modo 1 ler.
"""
import os
import re
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOWNLOADS = os.path.join(ROOT, "downloads")
RAW = os.path.join(ROOT, "assets", "_raw")
MODELS = os.path.join(ROOT, "assets", "models")
TRI_LIMIT = 20000
MODEL_EXT = (".fbx", ".obj", ".gltf", ".glb", ".blend")
LICENSE_HINTS = ("license", "licence", "licenca", "licença", "readme", "credits", "cc0", "cc-by")
CATEGORIES = {
    "characters": ["character", "hero", "knight", "mage", "wizard", "player", "human", "personagem"],
    "monsters": ["monster", "zombie", "skeleton", "demon", "ghoul", "undead", "creature", "orc", "goblin", "monstro"],
    "weapons": ["weapon", "sword", "staff", "axe", "bow", "dagger", "shield", "arma"],
    "environment": ["environment", "tree", "rock", "ruin", "dungeon", "cemetery", "grave", "wall", "terrain", "nature"],
    "props": ["prop", "chest", "barrel", "torch", "candle", "crate", "table"],
}
# nome da ação no jogo <- palavras que aparecem no nome do clipe (Mixamo e afins)
ACTION_NAMES = [
    ("idle", ["idle", "breathing", "standing"]),
    ("walk", ["walk"]),
    ("run", ["run", "sprint", "jog"]),
    ("cast", ["cast", "spell", "magic", "conjur"]),
    ("attack", ["attack", "slash", "punch", "kick", "stab", "swing", "strike"]),
    ("hit", ["hit", "impact", "react", "damage"]),
    ("death", ["death", "dying", "die"]),
]
# bibliotecas com muitos clipes num arquivo (ex.: Universal Animation Library): nome exato -> nome do jogo
EXACT_CLIPS = {
    "Idle_Loop": "idle", "Walk_Loop": "walk", "Jog_Fwd_Loop": "run", "Sprint_Loop": "sprint",
    "Sword_Attack": "attack", "Spell_Simple_Shoot": "cast", "Hit_Chest": "hit", "Death01": "death",
    "Sword_Regular_A": "attack_2", "Sword_Regular_B": "attack_3", "Sword_Regular_C": "attack_4",
}


def action_name(raw, taken):
    low = raw.lower()
    for name, words in ACTION_NAMES:
        if any(w in low for w in words):
            out = name
            i = 2
            while out in taken:
                out = "%s_%d" % (name, i)
                i += 1
            return out
    return re.sub(r"[^a-z0-9_]+", "_", low).strip("_") or "action"


# ---------------------------------------------------------------- modo 2: dentro do Blender

def blender_main(src, dst):
    import bpy  # noqa: F401 (só existe dentro do Blender)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(src)[1].lower()
    folder = os.path.dirname(src)
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=True)
        # Mixamo: animações "sem pele" na mesma pasta (Idle.fbx, Walking.fbx...) entram como ações do mesmo esqueleto
        base_name = os.path.basename(src).lower()
        for f in sorted(os.listdir(folder)):
            path = os.path.join(folder, f)
            if f.lower().endswith(".fbx") and f.lower() != base_name and _is_animation_only(f):
                before = set(bpy.data.actions)
                bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=True)
                for act in set(bpy.data.actions) - before:
                    act["source_file"] = f
                # remove os esqueletos extras trazidos pelo arquivo de animação
                for obj in list(bpy.context.selected_objects):
                    bpy.data.objects.remove(obj, do_unlink=True)
    elif ext == ".obj":
        if hasattr(bpy.ops.wm, "obj_import"):
            bpy.ops.wm.obj_import(filepath=src)
        else:
            bpy.ops.import_scene.obj(filepath=src)
    elif ext in (".gltf", ".glb"):
        bpy.ops.import_scene.gltf(filepath=src)
    elif ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=src)
    # Renomear muda a ordem de bpy.data.actions: percorre uma cópia, senão a mesma ação é visitada duas vezes.
    # Um clipe por arquivo (Mixamo): nome pelo arquivo/palavra-chave. Biblioteca com vários clipes num arquivo:
    # só os nomes exatos de EXACT_CLIPS mudam; o resto fica com o nome original (em minúsculas).
    taken = set()
    for act in list(bpy.data.actions):
        src_file = act.get("source_file", "")
        raw = (src_file or act.name).split("|")[-1]
        raw = os.path.splitext(raw)[0]
        if src_file or len(bpy.data.actions) == 1:
            new = action_name(raw, taken)
        else:
            new = EXACT_CLIPS.get(raw) or re.sub(r"[^a-z0-9_]+", "_", raw.lower()).strip("_") or "action"
            base, i = new, 2
            while new in taken:
                new = "%s_%d" % (base, i)
                i += 1
        taken.add(new)
        act.name = new
        act.use_fake_user = True
    # o primeiro esqueleto fica com as ações em faixas NLA, para o exportador levar todas
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is not None and bpy.data.actions:
        arm.animation_data_create()
        for act in bpy.data.actions:
            track = arm.animation_data.nla_tracks.new()
            track.name = act.name
            track.strips.new(act.name, int(act.frame_range[0]), act)
        arm.animation_data.action = None
    tris = 0
    deps = bpy.context.evaluated_depsgraph_get()
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            mesh = obj.evaluated_get(deps).to_mesh()
            mesh.calc_loop_triangles()
            tris += len(mesh.loop_triangles)
            obj.evaluated_get(deps).to_mesh_clear()
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_animations=True,
                              export_animation_mode="NLA_TRACKS" if arm is not None and bpy.data.actions else "ACTIONS",
                              export_apply=True, export_yup=True)
    print("TRIS %d" % tris)
    print("ACTIONS %s" % ",".join(a.name for a in bpy.data.actions))


def _is_animation_only(name):
    low = name.lower()
    return any(w in low for _n, ws in ACTION_NAMES for w in ws) and "skin" not in low


# ---------------------------------------------------------------- modo 1: organizar e chamar o Blender

def category_for(path):
    low = path.lower().replace("\\", "/")
    for cat, words in CATEGORIES.items():
        if any(w in low for w in words):
            return cat
    return "props"


def has_license(folder):
    for base, _dirs, files in os.walk(folder):
        for f in files:
            if any(h in f.lower() for h in LICENSE_HINTS):
                return True
    return False


def extract_downloads():
    for f in sorted(os.listdir(DOWNLOADS)):
        if f.lower().endswith(".zip"):
            out = os.path.join(RAW, os.path.splitext(f)[0])
            if not os.path.isdir(out):
                print("extraindo", f)
                with zipfile.ZipFile(os.path.join(DOWNLOADS, f)) as z:
                    z.extractall(out)


def candidates(only):
    found = []
    roots = [RAW, DOWNLOADS]
    for root in roots:
        for base, _dirs, files in os.walk(root):
            for f in files:
                path = os.path.join(base, f)
                if not f.lower().endswith(MODEL_EXT) or (only and only.lower() not in path.lower()):
                    continue
                if f.lower().endswith(".fbx") and _is_animation_only(f) and _has_mesh_sibling(base, f):
                    continue  # animação Mixamo: entra junto com o modelo da mesma pasta
                found.append(path)
    return found


def _has_mesh_sibling(folder, anim_file):
    return any(g.lower().endswith(".fbx") and g != anim_file and not _is_animation_only(g) for g in os.listdir(folder))


def package_of(path):
    rel = os.path.relpath(path, RAW if path.startswith(RAW) else DOWNLOADS)
    first = rel.split(os.sep)[0]
    return os.path.join(RAW if path.startswith(RAW) else DOWNLOADS, first) if os.sep in rel else os.path.dirname(path)


def main():
    args = sys.argv[1:]
    blender = None
    only = ""
    dry = "--dry-run" in args
    if "--blender" in args:
        blender = args[args.index("--blender") + 1]
    if "--only" in args:
        only = args[args.index("--only") + 1]
    if "--src" in args:  # pasta dos pacotes (ex.: a pasta Downloads do Windows) no lugar de downloads/
        global DOWNLOADS
        DOWNLOADS = args[args.index("--src") + 1]
    os.makedirs(RAW, exist_ok=True)
    extract_downloads()
    files = candidates(only)
    if not files:
        print("Nenhum modelo em downloads/ ou assets/_raw/.")
        return
    no_license, heavy, done, failed = [], [], [], []
    for src in files:
        pkg = package_of(src)
        if not has_license(pkg):
            no_license.append(pkg)
            continue
        name = re.sub(r"[^a-z0-9_]+", "_", os.path.splitext(os.path.basename(src))[0].lower()).strip("_")
        dst = os.path.join(MODELS, category_for(src), name + ".glb")
        if dry or blender is None:
            print("converteria %s -> %s" % (os.path.relpath(src, ROOT), os.path.relpath(dst, ROOT)))
            continue
        r = subprocess.run([blender, "-b", "--factory-startup", "-P", os.path.abspath(__file__), "--", src, dst],
                           capture_output=True, text=True, encoding="utf-8", errors="ignore")
        tris = re.search(r"TRIS (\d+)", r.stdout)
        acts = re.search(r"ACTIONS (.*)", r.stdout)
        if r.returncode != 0 or not os.path.exists(dst):
            failed.append((src, (r.stderr or r.stdout)[-400:]))
            continue
        done.append((dst, int(tris.group(1)) if tris else 0, acts.group(1) if acts else ""))
        if tris and int(tris.group(1)) > TRI_LIMIT:
            heavy.append((dst, int(tris.group(1))))
    for dst, t, a in done:
        print("OK  %s (%d triângulos%s)" % (os.path.relpath(dst, ROOT), t, ", ações: " + a if a else ""))
    for dst, t in heavy:
        print("PESADO  %s: %d triângulos (acima de ~%d) — sugiro Decimate no Blender" % (os.path.relpath(dst, ROOT), t, TRI_LIMIT))
    for pkg in sorted(set(no_license)):
        print("SEM LICENÇA (não convertido; me diga a licença): %s" % os.path.relpath(pkg, ROOT))
    for src, err in failed:
        print("FALHOU  %s\n%s" % (os.path.relpath(src, ROOT), err))
    if blender is None and not dry:
        print("\nBlender não informado: use --blender <caminho do blender.exe> para converter.")
    if done:
        print("\nLembre de registrar cada modelo em assets/assets_manifest.csv e rodar: python -I tools/asset_reports.py")


if __name__ == "__main__":
    try:
        import bpy  # noqa: F401
        inside_blender = True
    except ImportError:
        inside_blender = False
    if inside_blender:
        rest = sys.argv[sys.argv.index("--") + 1:]
        blender_main(rest[0], rest[1])
    else:
        main()
