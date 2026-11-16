#!/usr/bin/env bash
# Instala ou atualiza o Umbraheim num servidor Linux x86_64 (Debian/Ubuntu), como root.
# Faz: usuário de serviço, Godot 4.7.2 + export templates, clone/pull do repositório,
# import, build Web em /var/www/umbraheim e reinício do serviço systemd.
# O nginx e o certificado ficam fora (ver docs/DEPLOY.md).
#
# Uso:  sudo bash tools/deploy/deploy.sh            (primeira vez ou atualização)
# Variáveis opcionais: REPO, BRANCH, GODOT_VERSION
set -euo pipefail

REPO="${REPO:-https://github.com/mariomcj/umbraheim.git}"
BRANCH="${BRANCH:-main}"
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
BASE=/opt/umbraheim
APP="$BASE/app"
GODOT_DIR="$BASE/godot"
GODOT="$GODOT_DIR/godot"
WEB_ROOT=/var/www/umbraheim
DATA=/var/lib/umbraheim
SVC_USER=umbraheim
RELEASE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"

as_svc() { sudo -u "$SVC_USER" -H "$@"; }

echo "== dependências"
apt-get update -qq
apt-get install -y -qq git unzip curl rsync ca-certificates libfontconfig1 >/dev/null

echo "== usuário e pastas"
id "$SVC_USER" >/dev/null 2>&1 || useradd --system --create-home --home-dir "/home/$SVC_USER" --shell /usr/sbin/nologin "$SVC_USER"
mkdir -p "$BASE" "$GODOT_DIR" "$DATA" "$WEB_ROOT"
chown -R "$SVC_USER:$SVC_USER" "$BASE" "$DATA"

echo "== Godot ${GODOT_VERSION}"
if [ ! -x "$GODOT" ] || ! "$GODOT" --headless --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable"; then
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/godot.zip" "$RELEASE_URL/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
    unzip -q "$tmp/godot.zip" -d "$tmp"
    install -m 755 "$tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" "$GODOT"
    rm -rf "$tmp"
fi
TPL_DIR="/home/$SVC_USER/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
if [ ! -f "$TPL_DIR/web_nothreads_release.zip" ]; then
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/tpl.tpz" "$RELEASE_URL/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
    unzip -q "$tmp/tpl.tpz" -d "$tmp"
    mkdir -p "$TPL_DIR"
    cp -r "$tmp/templates/." "$TPL_DIR/"
    chown -R "$SVC_USER:$SVC_USER" "/home/$SVC_USER/.local"
    rm -rf "$tmp"
fi

echo "== código"
if [ -d "$APP/.git" ]; then
    as_svc git -C "$APP" fetch --quiet origin "$BRANCH"
    as_svc git -C "$APP" reset --quiet --hard "origin/$BRANCH"
else
    as_svc git clone --quiet --branch "$BRANCH" "$REPO" "$APP"
fi

echo "== import (a primeira vez demora)"
as_svc "$GODOT" --headless --path "$APP" --import >/dev/null 2>&1 || true

echo "== build Web"
mkdir -p "$APP/build/web"
chown -R "$SVC_USER:$SVC_USER" "$APP/build"
as_svc "$GODOT" --headless --path "$APP" --export-release "Web" "$APP/build/web/index.html"
test -f "$APP/build/web/index.pck"
rsync -a --delete "$APP/build/web/" "$WEB_ROOT/"
chown -R www-data:www-data "$WEB_ROOT" 2>/dev/null || true

echo "== serviço"
install -m 644 "$APP/tools/deploy/umbraheim.service" /etc/systemd/system/umbraheim.service
systemctl daemon-reload
systemctl enable umbraheim >/dev/null
systemctl restart umbraheim
sleep 5
systemctl --no-pager --lines=15 status umbraheim || true
echo "== pronto. Arquivos em $WEB_ROOT, banco em $DATA/umbraheim.db"
