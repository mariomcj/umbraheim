"""Baixa os pacotes CC0 de personagens e monstros (parte 2 dos assets no jogo) para downloads/.

Uso (na raiz):  python -I tools/fetch_creatures.py

- KayKit Adventurers e Skeletons (Kay Lousberg, CC0): só os arquivos usados, direto do GitHub oficial.
- Quaternius Animal Pack Vol.2 e Animated Monster Pack (CC0): zips do OpenGameArt, extraídos em downloads/<pacote>/.
Idempotente: o que já existe não é baixado de novo. A cópia para assets/ e o manifesto ficam com
tools/import_creatures.py, depois da conversão.
"""
import os
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DL = os.path.join(ROOT, "downloads")
UA = {"User-Agent": "asset-fetch-script/1.0"}

ADV = "https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0/main/"
ADV_DIR = "addons/kaykit_character_pack_adventures/"
SKE = "https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0/main/"
SKE_DIR = "addons/kaykit_character_pack_skeletons/"

KAYKIT = {
    "kaykit_adventurers": (ADV, ["LICENSE.txt"]
        + [ADV_DIR + "Characters/gltf/" + f for f in ["Mage.glb", "Knight.glb", "Rogue_Hooded.glb",
           "mage_texture.png", "knight_texture.png", "rogue_texture.png"]]
        + [ADV_DIR + "Assets/gltf/" + f for f in ["staff.gltf", "staff.bin", "sword_1handed.gltf", "sword_1handed.bin",
           "shield_spikes.gltf", "shield_spikes.bin", "spellbook_open.gltf", "spellbook_open.bin",
           "dagger.gltf", "dagger.bin", "knight_texture.png", "mage_texture.png", "rogue_texture.png"]]),
    "kaykit_skeletons": (SKE, ["LICENSE.txt"]
        + [SKE_DIR + "Characters/gltf/" + f for f in ["Skeleton_Warrior.glb", "Skeleton_Minion.glb",
           "Skeleton_Mage.glb", "Skeleton_Rogue.glb", "skeleton_texture.png"]]
        + [SKE_DIR + "Assets/gltf/" + f for f in ["Skeleton_Blade.gltf", "Skeleton_Blade.bin", "Skeleton_Axe.gltf",
           "Skeleton_Axe.bin", "Skeleton_Staff.gltf", "Skeleton_Staff.bin", "Skeleton_Shield_Large_A.gltf",
           "Skeleton_Shield_Large_A.bin", "skeleton_texture.png"]]),
}
ZIPS = {
    "quaternius_animal_pack_2": "https://opengameart.org/sites/default/files/Animal%20Pack%20Vol.2%20by%20%40Quaternius.zip",
    "quaternius_animated_monsters": "https://opengameart.org/sites/default/files/Animated%20Monster%20Pack%20by%20%40Quaternius.zip",
}


def get(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return 0
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        data = r.read()
    with open(dest + ".part", "wb") as f:
        f.write(data)
    os.replace(dest + ".part", dest)
    return len(data)


def safe_extract(zpath, dest):
    with zipfile.ZipFile(zpath) as z:
        for m in z.infolist():
            target = os.path.normpath(os.path.join(dest, m.filename))
            if not target.startswith(os.path.normpath(dest) + os.sep):
                raise RuntimeError("caminho suspeito no zip: " + m.filename)
        z.extractall(dest)


def main():
    total = 0
    for pack, (base, files) in KAYKIT.items():
        for f in files:
            total += get(base + f, os.path.join(DL, pack, f.replace("/", os.sep)))
        print("ok", pack)
    for pack, url in ZIPS.items():
        z = os.path.join(DL, pack + ".zip")
        total += get(url, z)
        out = os.path.join(DL, pack)
        if not os.path.isdir(out):
            safe_extract(z, out)
        print("ok", pack)
    print("baixados agora: %.1f MB" % (total / 1e6))


if __name__ == "__main__":
    sys.exit(main())
