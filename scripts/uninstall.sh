#!/usr/bin/env bash
set -euo pipefail

THEME_NAME="gnome-prism"
PREFIX="${HOME}"

usage() {
  cat <<EOF
Usage: $0 [--prefix <path>] [--help]

Remove ${THEME_NAME} files from:
  <prefix>/.themes/${THEME_NAME}
  <prefix>/.icons/${THEME_NAME}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || { echo "Missing value for --prefix" >&2; exit 1; }
      PREFIX="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

THEME_DEST_LEGACY="${PREFIX}/.themes/${THEME_NAME}"
THEME_DEST_XDG="${PREFIX}/.local/share/themes/${THEME_NAME}"
ICONS_DEST_LEGACY="${PREFIX}/.icons/${THEME_NAME}"
ICONS_DEST_XDG="${PREFIX}/.local/share/icons/${THEME_NAME}"
BACKGROUNDS_DEST="${PREFIX}/.local/share/backgrounds/${THEME_NAME}"
FIREFOX_DESKTOP_DEST="${PREFIX}/.local/share/applications/firefox_firefox.desktop"
THUNDERBIRD_DESKTOP_DEST="${PREFIX}/.local/share/applications/thunderbird_thunderbird.desktop"
SNAP_STORE_DESKTOP_DEST="${PREFIX}/.local/share/applications/snap-store_snap-store.desktop"
SPOTIFY_DESKTOP_DEST="${PREFIX}/.local/share/applications/spotify_spotify.desktop"
FACTORY_RESET_DESKTOP_DEST="${PREFIX}/.local/share/applications/factory-reset-tools_factory-reset-tools.desktop"
FIRMWARE_UPDATER_DESKTOP_DEST="${PREFIX}/.local/share/applications/firmware-updater_firmware-updater.desktop"
FIRMWARE_UPDATER_APP_DESKTOP_DEST="${PREFIX}/.local/share/applications/firmware-updater_firmware-updater-app.desktop"
YUBICO_DESKTOP_DEST="${PREFIX}/.local/share/applications/com.yubico.yubioath.desktop"
VIVALDI_MODS_DEST="${PREFIX}/.local/share/gnome-prism/vivaldi"
DM_MONO_DIR="${PREFIX}/.local/share/fonts/DMMono"
GTK4_OVERRIDE_DEST="${PREFIX}/.config/gtk-4.0/gtk.css"

rm -rf "${THEME_DEST_LEGACY}" "${THEME_DEST_XDG}"
rm -rf "${ICONS_DEST_LEGACY}" "${ICONS_DEST_XDG}"
rm -rf "${BACKGROUNDS_DEST}"
rm -rf "${VIVALDI_MODS_DEST}"
rm -f "${FIREFOX_DESKTOP_DEST}" "${THUNDERBIRD_DESKTOP_DEST}" "${SNAP_STORE_DESKTOP_DEST}"
rm -f "${SPOTIFY_DESKTOP_DEST}" "${FACTORY_RESET_DESKTOP_DEST}"
rm -f "${FIRMWARE_UPDATER_DESKTOP_DEST}" "${FIRMWARE_UPDATER_APP_DESKTOP_DEST}"
rm -f "${YUBICO_DESKTOP_DEST}"
rm -rf "${DM_MONO_DIR}"
rm -f "${GTK4_OVERRIDE_DEST}"
fc-cache -f "${PREFIX}/.local/share/fonts" 2>/dev/null || true

if [[ "${PREFIX}" == "${HOME}" ]] && command -v gsettings >/dev/null 2>&1; then
  background_uri="$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || true)"
  background_uri_dark="$(gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null || true)"
  screensaver_uri="$(gsettings get org.gnome.desktop.screensaver picture-uri 2>/dev/null || true)"

  if [[ "${background_uri}" == *"${BACKGROUNDS_DEST}"* ]]; then
    gsettings reset org.gnome.desktop.background picture-uri || true
  fi
  if [[ "${background_uri_dark}" == *"${BACKGROUNDS_DEST}"* ]]; then
    gsettings reset org.gnome.desktop.background picture-uri-dark || true
  fi
  if [[ "${screensaver_uri}" == *"${BACKGROUNDS_DEST}"* ]]; then
    gsettings reset org.gnome.desktop.screensaver picture-uri || true
  fi
fi

echo "Removed:"
echo "  ${THEME_DEST_LEGACY}"
echo "  ${THEME_DEST_XDG}"
echo "  ${ICONS_DEST_LEGACY}"
echo "  ${ICONS_DEST_XDG}"
echo "  ${BACKGROUNDS_DEST}"
echo "  ${VIVALDI_MODS_DEST}"
echo "  ${FIREFOX_DESKTOP_DEST}"
echo "  ${THUNDERBIRD_DESKTOP_DEST}"
echo "  ${SNAP_STORE_DESKTOP_DEST}"
echo "  ${SPOTIFY_DESKTOP_DEST}"
echo "  ${FACTORY_RESET_DESKTOP_DEST}"
echo "  ${FIRMWARE_UPDATER_DESKTOP_DEST}"
echo "  ${FIRMWARE_UPDATER_APP_DESKTOP_DEST}"
echo "  ${YUBICO_DESKTOP_DEST}"
echo "  ${DM_MONO_DIR}"
echo "  ${GTK4_OVERRIDE_DEST}"
