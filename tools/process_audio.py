"""Etapa de áudio: processa os candidatos de assets/_raw/audio/ (e os áudios soltos de downloads/)
para assets/audio/, e gera assets/audio/candidates.json, assets/audio/REVIEW.md e as linhas do manifesto.

Uso (na raiz):  python -I tools/process_audio.py
Depois de escolher na cena scenes/dev/audio_preview.tscn (que grava assets/audio/selection.json):
                python -I tools/process_audio.py --apply-selection   (apaga os descartados de assets/audio/)

ffmpeg (no PATH): OGG Vorbis; SFX mono 44,1 kHz a -16 LUFS (ganho medido + limitador), música estéreo 44,1 kHz
a -20 LUFS (loudnorm em duas passadas); silêncio cortado nas duas pontas. Os originais ficam em assets/_raw/audio/ (fora do projeto Godot).
Música: o .import ganha loop=true (rode o --import da Godot antes, para o .import existir).
"""
import csv
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "assets", "_raw", "audio")
OUT = os.path.join(ROOT, "assets", "audio")
DOWNLOADS = os.path.join(ROOT, "downloads")
MANIFEST = os.path.join(ROOT, "assets", "assets_manifest.csv")
CANDIDATES = os.path.join(OUT, "candidates.json")
SELECTION = os.path.join(OUT, "selection.json")
REJECTED = os.path.join(OUT, "rejected.json")  # originais descartados na escolha: não voltam
AUDIO_EXT = (".wav", ".ogg", ".mp3", ".flac", ".m4a", ".aiff", ".aif")

# Kenney: candidatos escolhidos pelo uso no jogo (o pacote inteiro fica em _raw)
K = "kenney/"
KENNEY_PICKS = {
    "combat": [
        (K + "impact-sounds/Audio/impactMetal_heavy_000.ogg", "golpe de metal pesado"),
        (K + "impact-sounds/Audio/impactMetal_medium_001.ogg", "golpe de metal médio"),
        (K + "impact-sounds/Audio/impactPlate_heavy_000.ogg", "golpe em armadura"),
        (K + "impact-sounds/Audio/impactPunch_heavy_000.ogg", "soco/pancada pesada"),
        (K + "rpg-audio/Audio/drawKnife1.ogg", "sacar lâmina"),
        (K + "rpg-audio/Audio/knifeSlice.ogg", "corte de lâmina"),
    ],
    "footsteps": [
        (K + "impact-sounds/Audio/footstep_concrete_000.ogg", "passo em pedra/concreto"),
        (K + "impact-sounds/Audio/footstep_concrete_002.ogg", "passo em pedra/concreto (variação)"),
        (K + "impact-sounds/Audio/footstep_grass_000.ogg", "passo na grama"),
        (K + "impact-sounds/Audio/footstep_snow_000.ogg", "passo na neve"),
        (K + "rpg-audio/Audio/footstep00.ogg", "passo (pacote RPG)"),
    ],
    "ui": [
        (K + "ui-audio/Audio/click1.ogg", "clique"),
        (K + "ui-audio/Audio/rollover1.ogg", "passar o mouse"),
        (K + "interface-sounds/Audio/confirmation_001.ogg", "confirmação"),
        (K + "interface-sounds/Audio/error_004.ogg", "erro"),
        (K + "interface-sounds/Audio/open_001.ogg", "abrir janela"),
        (K + "interface-sounds/Audio/close_001.ogg", "fechar janela"),
        (K + "rpg-audio/Audio/handleCoins.ogg", "moedas (loja)"),
        (K + "rpg-audio/Audio/bookFlip1.ogg", "virar página (diário)"),
        (K + "rpg-audio/Audio/bookOpen.ogg", "abrir livro (diário)"),
        (K + "rpg-audio/Audio/cloth1.ogg", "pano (equipar)"),
        # segunda rodada (interface I): variantes mais suaves, as primeiras foram descartadas
        (K + "interface-sounds/Audio/select_002.ogg", "clique (seleção)"),
        (K + "ui-audio/Audio/click3.ogg", "clique seco"),
        (K + "rpg-audio/Audio/handleSmallLeather.ogg", "couro (abrir janela)"),
        (K + "rpg-audio/Audio/handleSmallLeather2.ogg", "couro (fechar janela)"),
        (K + "interface-sounds/Audio/confirmation_002.ogg", "confirmação suave"),
        (K + "interface-sounds/Audio/error_006.ogg", "erro grave"),
        (K + "rpg-audio/Audio/dropLeather.ogg", "soltar item"),
        (K + "rpg-audio/Audio/beltHandle1.ogg", "pegar item"),
        (K + "rpg-audio/Audio/cloth2.ogg", "equipar"),
        (K + "rpg-audio/Audio/handleCoins2.ogg", "moedas"),
        (K + "rpg-audio/Audio/bookFlip2.ogg", "virar página"),
        (K + "rpg-audio/Audio/metalLatch.ogg", "trinco (baú)"),
    ],
    "ambient": [
        (K + "impact-sounds/Audio/impactBell_heavy_000.ogg", "sino pesado"),
    ],
}


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")


def duration(path):
    r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path])
    try:
        return float(r.stdout.strip())
    except ValueError:
        return 0.0


TRIM = ("silenceremove=start_periods=1:start_threshold=-55dB:start_silence=0.02,areverse,"
        "silenceremove=start_periods=1:start_threshold=-55dB:start_silence=0.08,areverse")


def _measure(src, chain):
    r = run(["ffmpeg", "-hide_banner", "-nostats", "-i", src, "-af", chain + ",loudnorm=print_format=json", "-f", "null", "-"])
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", r.stderr, re.S)
    return json.loads(m.group(0)) if m else None


def convert(src, dst, music):
    """Música: loudnorm em duas passadas (-20 LUFS). SFX: o som curto demais para o loudnorm (menos de 3 s)
    é medido com silêncio no fim (o silêncio não conta na medição) e recebe um ganho fixo até -16 LUFS,
    com limitador de pico em -4,4 dB (a codificação Vorbis passa do limite em transientes)."""
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if music:
        j = _measure(src, TRIM)
        norm = "loudnorm=I=-20:TP=-1.5:LRA=11"
        if j and j["input_i"] not in ("-inf", "inf"):
            norm += (":measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true"
                     % (j["input_i"], j["input_tp"], j["input_lra"], j["input_thresh"], j["target_offset"]))
        chain = TRIM + "," + norm
    else:
        j = _measure(src, TRIM + ",apad=whole_dur=4")
        gain = 0.0
        if j and j["input_i"] not in ("-inf", "inf"):
            gain = max(-30.0, min(30.0, -16.0 - float(j["input_i"])))
        chain = TRIM + ",volume=%.2fdB,alimiter=limit=0.6:attack=0.5:release=20:level=false" % gain
    args = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src, "-af", chain,
            "-ar", "44100", "-ac", "2" if music else "1", "-c:a", "libvorbis", "-q:a", "5" if music else "4", dst]
    r = run(args)
    if r.returncode != 0:
        raise RuntimeError("ffmpeg falhou em %s: %s" % (src, r.stderr[-400:]))


def meta_for(src):
    """Dados originais: <arquivo>.json (Freesound, música) ou _pack.json do pacote (Kenney)."""
    if os.path.exists(src + ".json"):
        return json.load(open(src + ".json", encoding="utf-8"))
    d = os.path.dirname(src)
    while d.startswith(RAW):
        p = os.path.join(d, "_pack.json")
        if os.path.exists(p):
            return json.load(open(p, encoding="utf-8"))
        d = os.path.dirname(d)
    return {}


def slug(text):
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def gather():
    """(categoria, original, rótulo) de todos os candidatos."""
    items = []
    for cat, picks in KENNEY_PICKS.items():
        for path, label in picks:
            items.append((cat, os.path.join(RAW, path), label))
    for src in sorted(glob.glob(os.path.join(RAW, "music", "*"))):
        if src.lower().endswith(AUDIO_EXT):
            items.append(("music", src, ""))
    for src in sorted(glob.glob(os.path.join(RAW, "freesound", "*", "*"))):
        if src.lower().endswith(AUDIO_EXT):
            items.append((os.path.basename(os.path.dirname(src)), src, ""))
    # áudios que o usuário pôs em downloads/: copiados para _raw/audio/downloads (originais) e processados;
    # a categoria vem da pasta (downloads/<categoria>/...) ou fica "unsorted"
    for dp, _dn, fn in os.walk(DOWNLOADS):
        for f in fn:
            if not f.lower().endswith(AUDIO_EXT):
                continue
            src = os.path.join(dp, f)
            sub = os.path.relpath(dp, DOWNLOADS).replace("\\", "/")
            cat = sub.split("/")[0] if sub != "." else "unsorted"
            keep = os.path.join(RAW, "downloads", sub if sub != "." else "", f)
            if not os.path.exists(keep):
                os.makedirs(os.path.dirname(keep), exist_ok=True)
                shutil.copy2(src, keep)
            items.append((cat if cat in ("magic", "combat", "ui", "footsteps", "ambient", "monsters", "music") else "unsorted", keep, ""))
    return items


def load_rejected():
    if not os.path.exists(REJECTED):
        return set()
    return set(json.load(open(REJECTED, encoding="utf-8")))


def process():
    items = gather()
    rejected = load_rejected()
    out = []
    for cat, src, label in items:
        if rel(src) in rejected:
            continue
        if not os.path.exists(src):
            print("  falta:", rel(src))
            continue
        meta = meta_for(src)
        base = os.path.splitext(os.path.basename(src))[0]
        if "kenney" in src.replace("\\", "/"):
            base = "kenney_" + base
        dst = os.path.join(OUT, "music" if cat == "music" else os.path.join("sfx", cat), slug(base) + ".ogg")
        if not os.path.exists(dst):
            convert(src, dst, cat == "music")
        out.append({
            "categoria": cat, "arquivo": rel(dst), "original": rel(src),
            "nome": meta.get("nome", base) if meta.get("fonte") != "Kenney" else os.path.basename(src),
            "rotulo": label, "pacote": meta.get("nome", "") if meta.get("fonte") == "Kenney" else "",
            "autor": meta.get("autor", "?"), "licença": meta.get("licença", "?"), "fonte": meta.get("fonte", "downloads/"),
            "url": meta.get("url", ""), "tags": meta.get("tags", []), "descricao": meta.get("descricao", ""),
            "busca": meta.get("busca", ""),
            "duracao_original_s": round(duration(src), 2), "duracao_s": round(duration(dst), 2),
        })
        print("  %-9s %s" % (cat, rel(dst)))
    with open(CANDIDATES, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    write_review(out)
    write_manifest(out)
    set_music_loop(out)
    print("candidatos: %d (assets/audio/candidates.json, assets/audio/REVIEW.md)" % len(out))


CAT_NAMES = {"music": "Música do menu", "magic": "Magia", "combat": "Combate", "monsters": "Monstros",
             "footsteps": "Passos", "ambient": "Ambiente", "ui": "Interface", "unsorted": "Sem categoria (downloads/)"}


def write_review(items):
    lines = ["# Revisão de áudio", "",
             "Candidatos já convertidos (OGG Vorbis, loudness normalizado, silêncio cortado). Ouça e escolha na cena",
             "`scenes/dev/audio_preview.tscn` (botão ▶ toca; marque os que ficam e clique em **Salvar escolha**).",
             "Depois, `python -I tools/process_audio.py --apply-selection` apaga os descartados de `assets/audio/`",
             "(os originais continuam em `assets/_raw/audio/`).", "",
             "Duração: original → processado (segundos).", "",
             "Loudness: música a -20 LUFS. SFX miram -16 LUFS, mas os sons muito curtos e secos (cliques, passos,",
             "golpes de metal) ficam entre -17 e -27 LUFS: o limitador segura o pico em cerca de -1 dBFS para não",
             "distorcer, e nesses sons quase todo o volume está no pico. O volume final de cada um se ajusta no jogo.", ""]
    for cat in CAT_NAMES:
        group = [i for i in items if i["categoria"] == cat]
        if not group:
            continue
        lines += ["## %s (%d)" % (CAT_NAMES[cat], len(group)), "",
                  "| Arquivo | Nome original | Duração | Autor · licença | Tags | Descrição |", "|---|---|---|---|---|---|"]
        for i in group:
            name = "[%s](%s)" % (i["nome"], i["url"]) if i["url"] else i["nome"]
            if i["rotulo"]:
                name += " — " + i["rotulo"]
            if i["pacote"]:
                name += " (%s)" % i["pacote"]
            desc = re.sub(r"\s+", " ", i["descricao"]).replace("|", "/")[:220]
            if i["busca"]:
                desc = "busca: \"%s\". " % i["busca"] + desc
            lines.append("| `%s` | %s | %.1f → %.1f | %s · %s | %s | %s |" % (
                os.path.basename(i["arquivo"]), name, i["duracao_original_s"], i["duracao_s"], i["autor"], i["licença"],
                ", ".join(i["tags"][:10]).replace("|", "/"), desc))
        lines.append("")
    lines += ["## Pendências", ""]
    if not any(i["fonte"] == "Freesound" for i in items):
        lines.append("- **Freesound:** a variável de ambiente `FREESOUND_API_KEY` não existe nesta máquina, então as buscas "
                     "(spell cast, dark magic, fireball, curse, portal, sword hit, monster growl, footsteps stone, dungeon ambience, "
                     "wind, church bell, ui click) ainda não foram feitas. Com a chave: `python -I tools/fetch_audio.py --only freesound` "
                     "e depois `python -I tools/process_audio.py`.")
    lines.append("- **Fora da regra de licença (não baixadas):** do OpenGameArt, \"Dark Gothic Haunted Masquerade\" e \"Dark Solemn "
                 "Choral with Organ\" (ISAo, OGA-BY 3.0), \"Orchestral Epic Fantasy Music\" (Zefz, CC-BY-SA 3.0 / GPL 3.0) e "
                 "\"The Dance of Death\" (Michael Klier, CC-BY-SA 3.0).")
    with open(os.path.join(OUT, "REVIEW.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_manifest(items):
    with open(MANIFEST, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    # linhas de áudio cujo arquivo sumiu (descartado ou removido) saem do manifesto
    rows = [r for r in rows if not r["caminho_local"].startswith("assets/audio/")
            or os.path.exists(os.path.join(ROOT, r["caminho_local"]))]
    known = {r["caminho_local"] for r in rows}
    today = datetime.date.today().isoformat()
    fields = ["nome", "tipo", "fonte", "url", "autor", "licença", "caminho_local", "data_download"]
    for i in items:
        if i["arquivo"] in known:
            continue
        kind = "música (OGG)" if i["categoria"] == "music" else "efeito sonoro (OGG, %s)" % i["categoria"]
        nome = i["nome"] + (" (%s)" % i["pacote"] if i["pacote"] else "")
        rows.append({"nome": nome, "tipo": kind, "fonte": i["fonte"], "url": i["url"], "autor": i["autor"],
                     "licença": i["licença"], "caminho_local": i["arquivo"], "data_download": today})
    with open(MANIFEST, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fields})


def set_music_loop(items):
    for i in items:
        if i["categoria"] != "music":
            continue
        imp = os.path.join(ROOT, i["arquivo"] + ".import")
        if os.path.exists(imp):
            s = open(imp, encoding="utf-8").read()
            s2 = re.sub(r"(?m)^loop=false$", "loop=true", s)
            if s2 != s:
                open(imp, "w", encoding="utf-8", newline="\n").write(s2)


def apply_selection():
    sel = json.load(open(SELECTION, encoding="utf-8"))
    keep = set(sel.get("keep", []))
    items = json.load(open(CANDIDATES, encoding="utf-8"))
    removed = 0
    for i in items:
        if i["arquivo"] in keep:
            continue
        for p in [i["arquivo"], i["arquivo"] + ".import"]:
            full = os.path.join(ROOT, p)
            if os.path.exists(full):
                os.remove(full)
        removed += 1
    kept = [i for i in items if i["arquivo"] in keep]
    rejected = load_rejected() | {i["original"] for i in items if i["arquivo"] not in keep}
    with open(REJECTED, "w", encoding="utf-8", newline="\n") as f:
        json.dump(sorted(rejected), f, ensure_ascii=False, indent=1)
    with open(CANDIDATES, "w", encoding="utf-8", newline="\n") as f:
        json.dump(kept, f, ensure_ascii=False, indent=1)
    with open(MANIFEST, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    gone = {i["arquivo"] for i in items} - keep
    rows = [r for r in rows if r["caminho_local"] not in gone]
    fields = ["nome", "tipo", "fonte", "url", "autor", "licença", "caminho_local", "data_download"]
    with open(MANIFEST, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fields})
    write_review(kept)
    print("mantidos %d, apagados %d (originais continuam em assets/_raw/audio/)" % (len(kept), removed))


if __name__ == "__main__":
    if "--apply-selection" in sys.argv:
        apply_selection()
    else:
        process()
