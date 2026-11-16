"""Fontes da interface (Google Fonts, licença OFL 1.1, aceita só para fontes) em assets/fonts/.

Uso (na raiz):  python -I tools/fetch_fonts.py
Baixa do repositório oficial github.com/google/fonts, com o OFL.txt de cada família, e registra no
assets/assets_manifest.csv. Idempotente.
"""
import csv
import datetime
import os
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(ROOT, "assets", "fonts")
MANIFEST = os.path.join(ROOT, "assets", "assets_manifest.csv")
UA = "asset-fetch-script/1.0"
BASE = "https://raw.githubusercontent.com/google/fonts/main/ofl/"

REMOTE_NAMES = {"Cinzel-Variable.ttf": "Cinzel[wght].ttf"}  # colchetes no nome atrapalham caminhos res://

FAMILIES = {
    # pasta no repositório: (nome, autor, [arquivos])
    "cinzel": ("Cinzel", "Natanael Gama", ["Cinzel-Variable.ttf"]),
    "alegreyasans": ("Alegreya Sans", "Juan Pablo del Peral (Huerta Tipográfica)",
                     ["AlegreyaSans-Regular.ttf", "AlegreyaSans-Medium.ttf", "AlegreyaSans-Bold.ttf",
                      "AlegreyaSans-Italic.ttf"]),
    "imfellenglish": ("IM Fell English", "Igino Marini", ["IMFeENrm28P.ttf", "IMFeENit28P.ttf"]),
}


def get(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    data = urllib.request.urlopen(req, timeout=120).read()
    with open(dest + ".part", "wb") as f:
        f.write(data)
    os.replace(dest + ".part", dest)


def main():
    rows = list(csv.DictReader(open(MANIFEST, encoding="utf-8", newline="")))
    known = {r["caminho_local"] for r in rows}
    today = datetime.date.today().isoformat()
    for folder, (name, author, files) in FAMILIES.items():
        out = os.path.join(DEST, folder)
        os.makedirs(out, exist_ok=True)
        get(BASE + folder + "/OFL.txt", os.path.join(out, "OFL.txt"))
        for fname in files:
            remote = REMOTE_NAMES.get(fname, fname)
            get(BASE + folder + "/" + urllib.parse.quote(remote), os.path.join(out, fname))
        rel = "assets/fonts/" + folder
        if rel not in known:
            rows.append({"nome": name, "tipo": "fonte (TTF, %d arquivo(s))" % len(files), "fonte": "Google Fonts",
                         "url": "https://fonts.google.com/specimen/" + name.replace(" ", "+"), "autor": author,
                         "licença": "OFL 1.1", "caminho_local": rel, "data_download": today})
        print("  %s: %s" % (name, ", ".join(files)))
    fields = ["nome", "tipo", "fonte", "url", "autor", "licença", "caminho_local", "data_download"]
    with open(MANIFEST, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fields})


if __name__ == "__main__":
    main()
