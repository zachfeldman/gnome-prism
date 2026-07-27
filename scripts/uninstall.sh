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
SIGNAL_DESKTOP_DEST="${PREFIX}/.local/share/applications/signal-desktop_signal-desktop.desktop"
FACTORY_RESET_DESKTOP_DEST="${PREFIX}/.local/share/applications/factory-reset-tools_factory-reset-tools.desktop"
FIRMWARE_UPDATER_DESKTOP_DEST="${PREFIX}/.local/share/applications/firmware-updater_firmware-updater.desktop"
FIRMWARE_UPDATER_APP_DESKTOP_DEST="${PREFIX}/.local/share/applications/firmware-updater_firmware-updater-app.desktop"
YUBICO_DESKTOP_DEST="${PREFIX}/.local/share/applications/com.yubico.yubioath.desktop"
VIVALDI_MODS_DEST="${PREFIX}/.local/share/gnome-prism/vivaldi"
DM_MONO_DIR="${PREFIX}/.local/share/fonts/DMMono"
GTK4_OVERRIDE_DEST="${PREFIX}/.config/gtk-4.0/gtk.css"
GHOSTTY_THEME_DEST="${PREFIX}/.config/ghostty/themes/${THEME_NAME}"
GHOSTTY_CONFIG_DEST="${PREFIX}/.config/ghostty/config"
SCREENSAVER_UUID="gnome-prism-screensaver@zachfeldman"
SCREENSAVER_DEST="${PREFIX}/.local/share/gnome-shell/extensions/${SCREENSAVER_UUID}"

# Only attempt to disable the extension for the active user install, not test
# prefixes, and only if it's actually installed.
if [[ "${PREFIX}" == "${HOME}" ]] && [[ -d "${SCREENSAVER_DEST}" ]] && command -v gnome-extensions >/dev/null 2>&1; then
  gnome-extensions disable "${SCREENSAVER_UUID}" 2>/dev/null || true
fi
# Never touch any other extension directory; only remove our own UUID.
rm -rf "${SCREENSAVER_DEST}"

rm -rf "${THEME_DEST_LEGACY}" "${THEME_DEST_XDG}"
rm -rf "${ICONS_DEST_LEGACY}" "${ICONS_DEST_XDG}"
rm -rf "${BACKGROUNDS_DEST}"
rm -rf "${VIVALDI_MODS_DEST}"
rm -f "${FIREFOX_DESKTOP_DEST}" "${THUNDERBIRD_DESKTOP_DEST}" "${SNAP_STORE_DESKTOP_DEST}"
rm -f "${SPOTIFY_DESKTOP_DEST}" "${SIGNAL_DESKTOP_DEST}" "${FACTORY_RESET_DESKTOP_DEST}"
rm -f "${FIRMWARE_UPDATER_DESKTOP_DEST}" "${FIRMWARE_UPDATER_APP_DESKTOP_DEST}"
rm -f "${YUBICO_DESKTOP_DEST}"
rm -rf "${DM_MONO_DIR}"
rm -f "${GTK4_OVERRIDE_DEST}"
rm -f "${GHOSTTY_THEME_DEST}"

# Drop our "theme =" line from the Ghostty config too - leaving it behind points
# Ghostty at a theme that no longer exists.
if [[ -f "${GHOSTTY_CONFIG_DEST}" ]] && command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY' "${GHOSTTY_CONFIG_DEST}" "${THEME_NAME}"
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
name = re.escape(sys.argv[2])
text = path.read_text(encoding="utf-8")
text = re.sub(rf"(?:\n# Installed by gnome-prism\.)?\n\s*theme\s*=\s*{name}\s*(?=\n|$)", "", text)
path.write_text(text, encoding="utf-8")
PY
fi
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
echo "  ${SIGNAL_DESKTOP_DEST}"
echo "  ${FACTORY_RESET_DESKTOP_DEST}"
echo "  ${FIRMWARE_UPDATER_DESKTOP_DEST}"
echo "  ${FIRMWARE_UPDATER_APP_DESKTOP_DEST}"
echo "  ${YUBICO_DESKTOP_DEST}"
echo "  ${DM_MONO_DIR}"
echo "  ${GTK4_OVERRIDE_DEST}"
echo "  ${GHOSTTY_THEME_DEST}"
echo "  ${SCREENSAVER_DEST}"
