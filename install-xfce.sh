#!/usr/bin/env bash
#
# install-xfce.sh - build & install Worklog Calendar on Xfce / Xubuntu 24.04.
#
# Same as install.sh but tailored for Xfce: it does NOT pull the GNOME
# AppIndicators extension. Instead it installs the Xfce panel's StatusNotifier
# plugin, which is what renders the top-bar "clock" indicator on Xfce.
#
#   ./install-xfce.sh                # install into ~/.local (per-user, no root)
#   ./install-xfce.sh --system       # install into /usr (needs sudo)
#   ./install-xfce.sh --deps         # apt-install build deps + Xfce SNI plugin
#   ./install-xfce.sh --run          # install + launch
#   ./install-xfce.sh --uninstall    # remove a per-user install

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
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $arg"; exit 1 ;;
  esac
done

# Build/runtime deps (no GNOME extension here). libadwaita is not shipped by
# Xubuntu by default but apt pulls it as a dependency of libadwaita-1-dev.
BUILD_PKGS=(meson ninja-build valac
            libgtk-4-dev libadwaita-1-dev libsoup-3.0-dev libjson-glib-dev libgee-0.8-dev)

# The Xfce panel needs a StatusNotifierItem host to show the tray clock. On
# xfce4-panel 4.18 (Xubuntu 24.04) SNI support is often already built in; the
# separate plugin is a belt-and-suspenders fallback and is installed
# best-effort (it must not abort the script if the package name differs).
XFCE_TRAY_PKG="xfce4-statusnotifier-plugin"

install_deps() {
  echo ">> Instalando dependencias de compilación con apt…"
  sudo apt-get update
  sudo apt-get install -y "${BUILD_PKGS[@]}"

  echo ">> Instalando el plugin de bandeja del panel de Xfce (best-effort)…"
  if sudo apt-get install -y "$XFCE_TRAY_PKG"; then
    echo "   OK: $XFCE_TRAY_PKG instalado."
  else
    echo "   AVISO: no pude instalar '$XFCE_TRAY_PKG'."
    echo "   Verificá el nombre con:  apt search statusnotifier"
    echo "   (En Xubuntu 24.04 el xfce4-panel 4.18 ya suele traer soporte SNI.)"
  fi
  echo ">> Recordá agregar el plugin al panel: clic derecho en el panel →"
  echo "   Panel → Agregar nuevos elementos… → 'Status Notifier Plugin'."
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

$USE_SUDO glib-compile-schemas "$PREFIX/share/glib-2.0/schemas" 2>/dev/null || true
$USE_SUDO gtk4-update-icon-cache -q -t "$PREFIX/share/icons/hicolor" 2>/dev/null || true

echo ">> Instalado: $PREFIX/bin/$APP_ID"
echo "   Ejecutá '$APP_ID' o buscá 'Worklog Calendar' en el menú de aplicaciones."
echo "   En Xfce el reloj sale del plugin 'Status Notifier' del panel — sin"
echo "   extensiones de GNOME. Clic izquierdo abre la ventanita; clic derecho,"
echo "   el menú con Salir."

if [[ $DO_RUN -eq 1 ]]; then
  echo ">> Lanzando…"
  exec "$PREFIX/bin/$APP_ID"
fi
