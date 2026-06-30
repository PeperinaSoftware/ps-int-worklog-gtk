#!/usr/bin/env bash
#
# install.sh - build & install the Worklog Calendar GTK4 app on Ubuntu 24.04.
#
#   ./install.sh                # build + install into ~/.local (per-user)
#   ./install.sh --system       # build + install into /usr (needs sudo)
#   ./install.sh --deps         # apt-install the build/runtime dependencies
#   ./install.sh --run          # build + install + launch
#   ./install.sh --uninstall    # remove a per-user install
#
# Per-user installs land under ~/.local (no root needed). The desktop entry,
# GSettings schema and icons are registered so the app shows up in the
# launcher and the top-bar indicator can find its icon.

set -euo pipefail

APP_ID="io.github.peperina.WorklogCalendar"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

PREFIX="$HOME/.local"
USE_SUDO=""
DO_DEPS=0
DO_RUN=0
DO_UNINSTALL=0

for arg in "$@"; do
  case "$arg" in
    --system)    PREFIX="/usr"; USE_SUDO="sudo" ;;
    --deps)      DO_DEPS=1 ;;
    --run)       DO_RUN=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $arg"; exit 1 ;;
  esac
done

PKGS=(meson ninja-build valac
      libgtk-4-dev libadwaita-1-dev libsoup-3.0-dev libjson-glib-dev libgee-0.8-dev
      gnome-shell-extension-appindicator)

install_deps() {
  echo ">> Instalando dependencias con apt…"
  sudo apt-get update
  sudo apt-get install -y "${PKGS[@]}"
}

uninstall() {
  echo ">> Desinstalando de $PREFIX…"
  rm -f  "$PREFIX/bin/$APP_ID"
  rm -f  "$PREFIX/share/applications/$APP_ID.desktop"
  rm -f  "$PREFIX/share/glib-2.0/schemas/$APP_ID.gschema.xml"
  rm -f  "$PREFIX/share/icons/hicolor/scalable/apps/$APP_ID.svg"
  rm -f  "$PREFIX/share/icons/hicolor/symbolic/apps/$APP_ID-symbolic.svg"
  glib-compile-schemas "$PREFIX/share/glib-2.0/schemas" 2>/dev/null || true
  gtk4-update-icon-cache -q "$PREFIX/share/icons/hicolor" 2>/dev/null || true
  echo ">> Listo."
}

if [[ $DO_DEPS -eq 1 ]]; then install_deps; fi
if [[ $DO_UNINSTALL -eq 1 ]]; then uninstall; exit 0; fi

echo ">> Configurando (prefix: $PREFIX)…"
if [[ ! -d "$BUILD_DIR" ]]; then
  meson setup "$BUILD_DIR" --prefix "$PREFIX"
else
  meson setup --reconfigure "$BUILD_DIR" --prefix "$PREFIX"
fi

echo ">> Compilando…"
ninja -C "$BUILD_DIR"

echo ">> Instalando…"
$USE_SUDO meson install -C "$BUILD_DIR"

# Make sure the per-user schema/icon caches are refreshed (meson's post_install
# does this for the configured prefix, but a belt-and-suspenders run is cheap).
$USE_SUDO glib-compile-schemas "$PREFIX/share/glib-2.0/schemas" 2>/dev/null || true
$USE_SUDO gtk4-update-icon-cache -q -t "$PREFIX/share/icons/hicolor" 2>/dev/null || true

echo ">> Instalado: $PREFIX/bin/$APP_ID"
echo "   Ejecutá '$APP_ID' o buscá 'Worklog Calendar' en el menú de aplicaciones."
echo "   En GNOME/Ubuntu, asegurate de tener activada la extensión"
echo "   'Ubuntu AppIndicators' para ver el reloj en la barra superior."

if [[ $DO_RUN -eq 1 ]]; then
  echo ">> Lanzando…"
  exec "$PREFIX/bin/$APP_ID"
fi
