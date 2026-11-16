"""Etapa de áudio da biblioteca: baixa os candidatos (originais) para assets/_raw/audio/.

Uso (na raiz):  python -I tools/fetch_audio.py [--only kenney|music|freesound]

- Kenney (CC0): pacotes de áudio inteiros (zip) em assets/_raw/audio/kenney/.
- Música do menu: candidatas do incompetech (Kevin MacLeod, CC-BY 4.0) e do OpenGameArt (CC-BY),
  em assets/_raw/audio/music/.
- Freesound: busca pela API com a chave da variável de ambiente FREESOUND_API_KEY (sessão, usuário
  ou máquina), só CC0 e Attribution, até 5 por busca; baixa a prévia HQ (OGG) em
  assets/_raw/audio/freesound/<categoria>/. Sem chave, a etapa é pulada com um aviso.
Cada original ganha um .json ao lado com nome, autor, licença, URL, tags e descrição originais
(o tools/process_audio.py lê esses dados para o REVIEW.md, o manifesto e os créditos).
Idempotente: o que já existe não é baixado de novo.
"""
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import zipfile
from http.cookiejar import CookieJar

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "assets", "_raw", "audio")
UA = "asset-fetch-script/1.0"

KENNEY = ["ui-audio", "interface-sounds", "impact-sounds", "rpg-audio"]

INCOMPETECH = "https://incompetech.com/music/royalty-free/mp3-royaltyfree/"
INCOMPETECH_PIECES = ["Oppressive Gloom", "Halls of the Undead", "Devastation and Revenge", "Private Reflection"]

OGA_MUSIC = {
    # slug: (arquivo, licença) — conferidos na página (CC-BY; OGA-BY e CC-BY-SA ficaram de fora)
    "dark-quest": ("https://opengameart.org/sites/default/files/Dark%20Quest.ogg", "CC-BY 4.0"),
    "the-descecrated-temple": ("https://opengameart.org/sites/default/files/The%20Desecrated%20Temple_2.mp3", "CC-BY 3.0"),
    "stronghold-0": ("https://opengameart.org/sites/default/files/stronghold.mp3", "CC-BY 4.0"),
    "dark-descent": ("https://opengameart.org/sites/default/files/Dark%20Descent_0.mp3", "CC-BY 3.0"),
}

# categoria (pasta em assets/audio/sfx) -> buscas no Freesound
FREESOUND = {
    "magic": ["spell cast", "dark magic", "fireball", "curse spell", "portal"],
    "combat": ["sword hit"],
    "monsters": ["monster growl"],
    "footsteps": ["footsteps stone"],
    "ambient": ["dungeon ambience", "wind", "church bell"],
    "ui": ["ui click"],
}
FREESOUND_LICENSES = {
    "http://creativecommons.org/publicdomain/zero/1.0/": "CC0",
    "https://creativecommons.org/publicdomain/zero/1.0/": "CC0",
    "http://creativecommons.org/licenses/by/4.0/": "CC-BY 4.0",
    "https://creativecommons.org/licenses/by/4.0/": "CC-BY 4.0",
    "http://creativecommons.org/licenses/by/3.0/": "CC-BY 3.0",
    "https://creativecommons.org/licenses/by/3.0/": "CC-BY 3.0",
}


def http(url, headers=None, opener=None, timeout=120):
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    return (opener.open if opener else urllib.request.urlopen)(req, timeout=timeout).read()


def save(url, dest, meta, opener=None, headers=None):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if not (os.path.exists(dest) and os.path.getsize(dest) > 0):
        data = http(url, headers=headers, opener=opener)
        with open(dest + ".part", "wb") as f:
            f.write(data)
        os.replace(dest + ".part", dest)
    if meta is not None:
        with open(dest + ".json", "w", encoding="utf-8", newline="\n") as f:
            json.dump(meta, f, ensure_ascii=False, indent=1)


def kenney():
    for pack in KENNEY:
        zpath = os.path.join(RAW, "kenney", "kenney_%s.zip" % pack)
        out = os.path.join(RAW, "kenney", pack)
        if not os.path.exists(zpath):
            jar = CookieJar()
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
            page = http("https://kenney.nl/assets/%s" % pack, opener=opener).decode("utf-8", "ignore")
            did = re.search(r"data-download-id='([0-9a-f]+)'", page).group(1)
            link = json.loads(http("https://kenney.nl/download-link/" + did, opener=opener,
                                   headers={"Referer": "https://kenney.nl/assets/" + pack}))["url"]
            save(link, zpath, None, opener=opener)
        if not os.path.isdir(out):
            with zipfile.ZipFile(zpath) as z:
                for m in z.infolist():
                    target = os.path.normpath(os.path.join(out, m.filename))
                    if not target.startswith(os.path.normpath(out) + os.sep):
                        raise RuntimeError("caminho suspeito no zip: " + m.filename)
                z.extractall(out)
        meta = {"nome": "Kenney " + pack.replace("-", " ").title(), "autor": "Kenney (kenney.nl)", "licença": "CC0",
                "fonte": "Kenney", "url": "https://kenney.nl/assets/" + pack, "tags": [], "descricao": ""}
        with open(os.path.join(out, "_pack.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(meta, f, ensure_ascii=False, indent=1)
        n = sum(1 for _, _, fs in os.walk(out) for f in fs if f.lower().endswith((".ogg", ".wav", ".mp3")))
        print("  kenney %s: %d sons" % (pack, n))


def music():
    pieces = json.loads(http("https://incompetech.com/music/royalty-free/pieces.json"))
    by_title = {p["title"]: p for p in pieces}
    for title in INCOMPETECH_PIECES:
        p = by_title[title]
        meta = {"nome": title, "autor": "Kevin MacLeod (incompetech.com)", "licença": "CC-BY 4.0", "fonte": "incompetech",
                "url": "https://incompetech.com/music/royalty-free/index.html?isrc=%s" % p.get("isrc", ""),
                "tags": [t.strip() for t in (p.get("feel") or "").split(",") if t.strip()]
                        + [t.strip() for t in (p.get("instruments") or "").split(",") if t.strip()],
                "descricao": p.get("description") or "", "duracao_original": p.get("length", "")}
        save(INCOMPETECH + urllib.parse.quote(p["filename"]), os.path.join(RAW, "music", "incompetech_" + slug(title) + ".mp3"), meta)
        print("  música (incompetech):", title)
    for page_slug, (url, lic) in OGA_MUSIC.items():
        page = http("https://opengameart.org/content/" + page_slug).decode("utf-8", "ignore")
        title = re.search(r"<title>([^|<]+)", page)
        author = re.search(r'field-name-author-submitter.*?<a href="/users/[^"]+">([^<]+)</a>', page, re.S)
        tags = [urllib.parse.unquote(t) for t in re.findall(r'field_art_tags_tid=([^"&]+)"', page)]
        body = re.search(r'field-name-body.*?<div class="field-item even"[^>]*>(.*?)</div>', page, re.S)
        desc = re.sub(r"\s+", " ", re.sub("<[^>]+>", " ", body.group(1))).strip() if body else ""
        ext = os.path.splitext(urllib.parse.urlparse(url).path)[1].lower()
        meta = {"nome": title.group(1).strip() if title else page_slug, "autor": author.group(1) if author else "?",
                "licença": lic, "fonte": "OpenGameArt", "url": "https://opengameart.org/content/" + page_slug,
                "tags": tags, "descricao": desc[:600]}
        save(url, os.path.join(RAW, "music", "oga_" + page_slug + ext), meta)
        print("  música (OpenGameArt):", meta["nome"])


def freesound_key():
    key = os.environ.get("FREESOUND_API_KEY", "")
    if not key and sys.platform == "win32":
        import winreg
        for hive, path in [(winreg.HKEY_CURRENT_USER, r"Environment"),
                           (winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment")]:
            try:
                with winreg.OpenKey(hive, path) as k:
                    key = winreg.QueryValueEx(k, "FREESOUND_API_KEY")[0]
                    break
            except OSError:
                pass
    return key


def freesound():
    key = freesound_key()
    if not key:
        print("  Freesound: FREESOUND_API_KEY não encontrada; pulei.")
        return
    lic_filter = 'license:("Creative Commons 0" OR "Attribution")'
    fields = "id,name,username,license,tags,description,duration,previews,url"
    for cat, queries in FREESOUND.items():
        for q in queries:
            params = urllib.parse.urlencode({"query": q, "filter": lic_filter, "fields": fields,
                                             "sort": "rating_desc", "page_size": 15})
            res = json.loads(http("https://freesound.org/apiv2/search/text/?" + params,
                                  headers={"Authorization": "Token " + key}))
            got = 0
            for s in res.get("results", []):
                lic = FREESOUND_LICENSES.get(s.get("license", ""))
                if lic is None or float(s.get("duration", 0)) > (120 if cat == "ambient" else 12):
                    continue # Attribution NonCommercial e sampling+ ficam de fora; sons longos demais também
                meta = {"nome": s["name"], "autor": s["username"], "licença": lic, "fonte": "Freesound", "url": s["url"],
                        "tags": s.get("tags", []), "descricao": (s.get("description") or "")[:600],
                        "busca": q, "duracao_original": s.get("duration")}
                dest = os.path.join(RAW, "freesound", cat, "fs%d_%s.ogg" % (s["id"], slug(s["name"])[:40]))
                save(s["previews"]["preview-hq-ogg"], dest, meta)
                got += 1
                if got >= 5:
                    break
            print("  Freesound %s / %s: %d" % (cat, q, got))


def slug(text):
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def main():
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else ""
    for name, fn in [("kenney", kenney), ("music", music), ("freesound", freesound)]:
        if only in ("", name):
            print(name)
            fn()


if __name__ == "__main__":
    main()
