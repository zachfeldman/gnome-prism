#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

THEME_NAME="gnome-prism"
PREFIX="${HOME}"

# Portable download helper: tries curl, then wget.
download_file() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${dest}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${dest}" "${url}"
  else
    echo "Error: neither curl nor wget found; cannot download ${url}" >&2
    return 1
  fi
}

ensure_user_themes_extension() {
  # Only attempt to manage the extension for the active user install.
  [[ "${PREFIX}" == "${HOME}" ]] || return 0

  if ! command -v gnome-extensions >/dev/null 2>&1; then
    echo "Note: 'gnome-extensions' CLI not found; skipping automatic User Themes enablement." >&2
    echo "You can install/enable it manually to allow Shell theming." >&2
    return 0
  fi

  user_theme_ext_id="user-theme@gnome-shell-extensions.gcampax.github.com"
  ext_on_disk=false
  for d in /usr/share/gnome-shell/extensions "${HOME}/.local/share/gnome-shell/extensions"; do
    [[ -d "${d}/${user_theme_ext_id}" ]] && { ext_on_disk=true; break; }
  done

  if ! ${ext_on_disk}; then
    echo "User Themes extension not found; attempting to install (requires sudo)." >&2
    echo "You can skip this by cancelling the password prompt and installing the extension manually later." >&2
    if command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
      # Debian/Ubuntu
      pkg_cmd="apt-get"
      if command -v apt >/dev/null 2>&1; then
        pkg_cmd="apt"
      fi
      if sudo "${pkg_cmd}" -y install gnome-shell-extensions; then
        ext_on_disk=true
      else
        echo "Warning: failed to install 'gnome-shell-extensions'. Please install it manually to enable Shell theming." >&2
        return 0
      fi
    elif command -v dnf >/dev/null 2>&1; then
      # Fedora/RHEL
      if sudo dnf install -y gnome-shell-extension-user-theme; then
        ext_on_disk=true
      else
        echo "Warning: failed to install 'gnome-shell-extension-user-theme'. Please install it manually to enable Shell theming." >&2
        return 0
      fi
    else
      echo "Warning: User Themes extension not found and no supported package manager detected." >&2
      echo "Please install the GNOME 'User Themes' extension manually to enable Shell theming." >&2
      return 0
    fi
  fi

  # Try to enable the extension. On Wayland, GNOME Shell only discovers new
  # extensions after a login cycle, so `gnome-extensions enable` may fail if the
  # package was just installed in this session. Fall back to writing the enabled
  # list in dconf directly so it takes effect on next login.
  if gnome-extensions enable "${user_theme_ext_id}" 2>/dev/null; then
    echo "Enabled GNOME 'User Themes' shell extension for Shell theming."
  elif ${ext_on_disk}; then
    # Append to the enabled-extensions list via gsettings so the extension
    # activates on the next GNOME Shell start (i.e. next login on Wayland).
    current="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")"
    if ! echo "${current}" | grep -q "${user_theme_ext_id}"; then
      if [[ "${current}" == "@as []" ]]; then
        new_val="['${user_theme_ext_id}']"
      else
        new_val="$(echo "${current}" | sed "s/]$/, '${user_theme_ext_id}']/")"
      fi
      gsettings set org.gnome.shell enabled-extensions "${new_val}" 2>/dev/null || true
    fi
    echo "User Themes extension is installed but GNOME Shell has not loaded it yet."
    echo "It will activate on next login. Log out and back in to apply the Shell theme."
  fi
}

usage() {
  cat <<EOF
Usage: $0 [--prefix <path>] [--help]

Install ${THEME_NAME} theme files into:
  <prefix>/.themes/${THEME_NAME}
  <prefix>/.icons/${THEME_NAME} (if icon files exist)
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

if [[ "${PREFIX}" == "${HOME}" ]] && [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Error: Do not run this script with sudo or as root when installing a per-user theme." >&2
  echo "Re-run it as your regular user without sudo, for example:" >&2
  echo "  ./scripts/install.sh" >&2
  exit 1
fi

# Ensure curl is available (needed for font downloads and extension fallback).
if ! command -v curl >/dev/null 2>&1; then
  # Check internet connectivity with a neutral target
  if ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 && ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    echo "Error: no internet connection detected. Please connect to the internet and rerun." >&2
    exit 1
  fi
  if command -v apt-get >/dev/null 2>&1; then
    echo "curl not found; installing via apt (requires sudo)..."
    sudo apt-get update
    sudo apt-get install -y curl
  elif command -v dnf >/dev/null 2>&1; then
    echo "curl not found; installing via dnf (requires sudo)..."
    sudo dnf install -y curl
  else
    echo "Error: curl is not installed and no supported package manager detected." >&2
    echo "Please install curl manually and rerun." >&2
    exit 1
  fi
fi

THEME_SRC="${REPO_ROOT}/themes/${THEME_NAME}"
ICONS_SRC="${REPO_ROOT}/icons/${THEME_NAME}"
BACKGROUNDS_SRC="${REPO_ROOT}/assets/backgrounds"
FIREFOX_SNAP_DESKTOP_SRC="${FIREFOX_SNAP_DESKTOP_SRC:-/var/lib/snapd/desktop/applications/firefox_firefox.desktop}"
THUNDERBIRD_SNAP_DESKTOP_SRC="${THUNDERBIRD_SNAP_DESKTOP_SRC:-/var/lib/snapd/desktop/applications/thunderbird_thunderbird.desktop}"
SNAP_STORE_DESKTOP_SRC="${SNAP_STORE_DESKTOP_SRC:-/var/lib/snapd/desktop/applications/snap-store_snap-store.desktop}"
SPOTIFY_SNAP_DESKTOP_SRC="${SPOTIFY_SNAP_DESKTOP_SRC:-/var/lib/snapd/desktop/applications/spotify_spotify.desktop}"
FACTORY_RESET_SNAP_DESKTOP_SRC="${FACTORY_RESET_SNAP_DESKTOP_SRC:-/var/lib/snapd/desktop/applications/factory-reset-tools_factory-reset-tools.desktop}"
FIRMWARE_UPDATER_SNAP_DESKTOP_SRC="${FIRMWARE_UPDATER_SNAP_DESKTOP_SRC:-/var/lib/snapd/desktop/applications/firmware-updater_firmware-updater.desktop}"
FIRMWARE_UPDATER_APP_SNAP_DESKTOP_SRC="${FIRMWARE_UPDATER_APP_SNAP_DESKTOP_SRC:-/var/lib/snapd/desktop/applications/firmware-updater_firmware-updater-app.desktop}"
YUBICO_DESKTOP_SRC="${YUBICO_DESKTOP_SRC:-${HOME}/.local/share/applications/com.yubico.yubioath.desktop}"
CURSOR_SETTINGS_TEMPLATE="${REPO_ROOT}/apps/cursor/gnome-prism-settings.json"
TILIX_THEME_SCRIPT="${REPO_ROOT}/apps/tilix/install.sh"

THEME_DEST_LEGACY="${PREFIX}/.themes/${THEME_NAME}"
THEME_DEST_XDG="${PREFIX}/.local/share/themes/${THEME_NAME}"
ICONS_DEST_LEGACY="${PREFIX}/.icons/${THEME_NAME}"
ICONS_DEST_XDG="${PREFIX}/.local/share/icons/${THEME_NAME}"
BACKGROUNDS_DEST="${PREFIX}/.local/share/backgrounds/${THEME_NAME}"
APPS_DEST="${PREFIX}/.local/share/applications"
FIREFOX_DESKTOP_DEST="${APPS_DEST}/firefox_firefox.desktop"
THUNDERBIRD_DESKTOP_DEST="${APPS_DEST}/thunderbird_thunderbird.desktop"
SNAP_STORE_DESKTOP_DEST="${APPS_DEST}/snap-store_snap-store.desktop"
SPOTIFY_DESKTOP_DEST="${APPS_DEST}/spotify_spotify.desktop"
FACTORY_RESET_DESKTOP_DEST="${APPS_DEST}/factory-reset-tools_factory-reset-tools.desktop"
FIRMWARE_UPDATER_DESKTOP_DEST="${APPS_DEST}/firmware-updater_firmware-updater.desktop"
FIRMWARE_UPDATER_APP_DESKTOP_DEST="${APPS_DEST}/firmware-updater_firmware-updater-app.desktop"
YUBICO_DESKTOP_DEST="${APPS_DEST}/com.yubico.yubioath.desktop"
FIREFOX_USERCHROME_SCRIPT="${SCRIPT_DIR}/apply_firefox_userchrome.sh"
VIVALDI_THEME_SCRIPT="${SCRIPT_DIR}/apply_vivaldi_theme.sh"
BOTTOM_PANEL_SCRIPT="${SCRIPT_DIR}/setup_bottom_panel.sh"
CURSOR_SETTINGS_DIR="${PREFIX}/.config/Cursor/User"
CURSOR_SETTINGS_DEST="${CURSOR_SETTINGS_DIR}/settings.json"

if [[ ! -d "${THEME_SRC}" ]]; then
  echo "Theme source directory not found: ${THEME_SRC}" >&2
  exit 1
fi

# Install DM Mono font if not already present (required by gnome-shell.css).
if ! fc-list | grep -qi "DM Mono"; then
  echo
  echo "=== FONT: DM Mono ==="
  DM_MONO_DIR="${PREFIX}/.local/share/fonts/DMMono"
  mkdir -p "${DM_MONO_DIR}"
  DM_MONO_BASE_URL="https://raw.githubusercontent.com/google/fonts/main/ofl/dmmono"
  DM_MONO_FILES=(DMMono-Light DMMono-LightItalic DMMono-Regular DMMono-Italic DMMono-Medium DMMono-MediumItalic)
  dm_mono_ok=true
  for style in "${DM_MONO_FILES[@]}"; do
    if ! download_file "${DM_MONO_BASE_URL}/${style}.ttf" "${DM_MONO_DIR}/${style}.ttf"; then
      dm_mono_ok=false
      break
    fi
  done
  if ${dm_mono_ok}; then
    fc-cache -f "${DM_MONO_DIR}" 2>/dev/null || true
    echo "Installed DM Mono font to ${DM_MONO_DIR}"
  else
    echo "Warning: failed to download DM Mono font. The theme will fall back to Noto Sans Mono." >&2
  fi
else
  echo
  echo "=== FONT: DM Mono ==="
  echo "DM Mono already installed; skipping."
fi

mkdir -p "${PREFIX}/.themes"
mkdir -p "${PREFIX}/.local/share/themes"
rm -rf "${THEME_DEST_LEGACY}" "${THEME_DEST_XDG}"
cp -a "${THEME_SRC}" "${THEME_DEST_LEGACY}"
cp -a "${THEME_SRC}" "${THEME_DEST_XDG}"
echo
echo "=== GNOME THEME FILES ==="
echo "Installed theme to ${THEME_DEST_LEGACY}"
echo "Installed theme to ${THEME_DEST_XDG}"
if [[ "${PREFIX}" == "${HOME}" ]] && command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface gtk-theme "${THEME_NAME}" || true
  echo "Set GNOME GTK theme to ${THEME_NAME} via gsettings"
fi

# libadwaita apps (Nautilus, Settings, etc.) ignore theme-installed CSS and only
# read ~/.config/gtk-4.0/gtk.css.  Copy the GTK4 override there so it takes effect.
GTK4_OVERRIDE_SRC="${THEME_SRC}/gtk-4.0/gtk.css"
GTK4_OVERRIDE_DEST="${PREFIX}/.config/gtk-4.0/gtk.css"
if [[ -f "${GTK4_OVERRIDE_SRC}" ]]; then
  echo
  echo "=== GTK4 / LIBADWAITA OVERRIDE ==="
  mkdir -p "$(dirname "${GTK4_OVERRIDE_DEST}")"
  cp -f "${GTK4_OVERRIDE_SRC}" "${GTK4_OVERRIDE_DEST}"
  echo "Installed GTK4 override to ${GTK4_OVERRIDE_DEST}"
fi

if [[ -d "${ICONS_SRC}" ]]; then
  mkdir -p "${PREFIX}/.icons"
  mkdir -p "${PREFIX}/.local/share/icons"
  rm -rf "${ICONS_DEST_LEGACY}" "${ICONS_DEST_XDG}"
  cp -a "${ICONS_SRC}" "${ICONS_DEST_LEGACY}"
  cp -a "${ICONS_SRC}" "${ICONS_DEST_XDG}"
  echo
  echo "=== ICON THEME FILES ==="
  echo "Installed icons to ${ICONS_DEST_LEGACY}"
  echo "Installed icons to ${ICONS_DEST_XDG}"
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f "${ICONS_DEST_LEGACY}" || true
    gtk-update-icon-cache -q -t -f "${ICONS_DEST_XDG}" || true
  fi
  # On some Ubuntu/GNOME builds, the standard Settings UI does not list
  # user-installed icon themes even though they are valid and present.
  # When installing for the active user, proactively select the icon theme
  # via gsettings so icons apply everywhere, regardless of UI quirks.
  if [[ "${PREFIX}" == "${HOME}" ]] && command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface icon-theme "${THEME_NAME}" || true
    echo "Set GNOME icon theme to ${THEME_NAME} via gsettings"
  fi
fi

ensure_user_themes_extension

# Set Shell theme AFTER the User Themes extension is installed/enabled so the
# gsettings schema is available.
if [[ "${PREFIX}" == "${HOME}" ]] && command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.shell.extensions.user-theme name "${THEME_NAME}" || true
  echo "Set GNOME Shell theme to ${THEME_NAME} via gsettings"
fi

if [[ -d "${BACKGROUNDS_SRC}" ]]; then
  echo
  echo "=== WALLPAPER / BACKGROUNDS ==="
  mkdir -p "${PREFIX}/.local/share/backgrounds"
  rm -rf "${BACKGROUNDS_DEST}"
  cp -a "${BACKGROUNDS_SRC}" "${BACKGROUNDS_DEST}"
  echo "Installed backgrounds to ${BACKGROUNDS_DEST}"

  # Only apply desktop settings for the active user install, not test prefixes.
  if [[ "${PREFIX}" == "${HOME}" ]]; then
    shopt -s nullglob
    background_files=("${BACKGROUNDS_DEST}"/*)
    shopt -u nullglob
    if ((${#background_files[@]} > 0)); then
      default_background="${BACKGROUNDS_DEST}/gnome-prism-default-background.jpg"
      if [[ ! -f "${default_background}" ]]; then
        default_background="${background_files[0]}"
      fi
      wallpaper_uri="file://${default_background}"
      if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.background picture-uri "${wallpaper_uri}" || true
        gsettings set org.gnome.desktop.background picture-uri-dark "${wallpaper_uri}" || true
        gsettings set org.gnome.desktop.screensaver picture-uri "${wallpaper_uri}" || true
        echo "Set GNOME wallpaper and lock-screen background to ${wallpaper_uri}"
      else
        echo "Warning: gsettings not found, skipped wallpaper configuration." >&2
      fi
    fi
  fi
fi

# Snap Firefox desktop file commonly uses an absolute icon path, which bypasses icon themes.
# Install a local desktop-entry override so the themed icon name is used.
if [[ -f "${FIREFOX_SNAP_DESKTOP_SRC}" ]]; then
  echo
  echo "=== APP ICON OVERRIDES (Firefox) ==="
  mkdir -p "${APPS_DEST}"
  python3 - <<'PY' "${FIREFOX_SNAP_DESKTOP_SRC}" "${FIREFOX_DESKTOP_DEST}"
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
text = src.read_text(encoding="utf-8")

if re.search(r"^Icon=.*$", text, flags=re.M):
    text = re.sub(r"^Icon=.*$", "Icon=firefox_firefox", text, flags=re.M)
else:
    text += "\nIcon=firefox_firefox\n"

dest.write_text(text, encoding="utf-8")
PY
  echo "Installed Firefox desktop override to ${FIREFOX_DESKTOP_DEST}"
fi

# Snap Thunderbird desktop file uses an absolute icon path.
if [[ -f "${THUNDERBIRD_SNAP_DESKTOP_SRC}" ]]; then
  mkdir -p "${APPS_DEST}"
  python3 - <<'PY' "${THUNDERBIRD_SNAP_DESKTOP_SRC}" "${THUNDERBIRD_DESKTOP_DEST}"
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
text = src.read_text(encoding="utf-8")

if re.search(r"^Icon=.*$", text, flags=re.M):
    text = re.sub(r"^Icon=.*$", "Icon=thunderbird_thunderbird", text, flags=re.M)
else:
    text += "\nIcon=thunderbird_thunderbird\n"

dest.write_text(text, encoding="utf-8")
PY
  echo "Installed Thunderbird desktop override to ${THUNDERBIRD_DESKTOP_DEST}"
fi

# Snap Store desktop file uses an absolute icon path.
if [[ -f "${SNAP_STORE_DESKTOP_SRC}" ]]; then
  mkdir -p "${APPS_DEST}"
  python3 - <<'PY' "${SNAP_STORE_DESKTOP_SRC}" "${SNAP_STORE_DESKTOP_DEST}"
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
text = src.read_text(encoding="utf-8")

if re.search(r"^Icon=.*$", text, flags=re.M):
    text = re.sub(r"^Icon=.*$", "Icon=snap-store_snap-store", text, flags=re.M)
else:
    text += "\nIcon=snap-store_snap-store\n"

dest.write_text(text, encoding="utf-8")
PY
  echo "Installed Snap Store desktop override to ${SNAP_STORE_DESKTOP_DEST}"
fi

# Snap Factory Reset Tools desktop file uses an absolute icon path.
if [[ -f "${FACTORY_RESET_SNAP_DESKTOP_SRC}" ]]; then
  mkdir -p "${APPS_DEST}"
  python3 - <<'PY' "${FACTORY_RESET_SNAP_DESKTOP_SRC}" "${FACTORY_RESET_DESKTOP_DEST}"
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
text = src.read_text(encoding="utf-8")

if re.search(r"^Icon=.*$", text, flags=re.M):
    text = re.sub(r"^Icon=.*$", "Icon=factory-reset-tools_factory-reset-tools", text, flags=re.M)
else:
    text += "\nIcon=factory-reset-tools_factory-reset-tools\n"

dest.write_text(text, encoding="utf-8")
PY
  echo "Installed Factory Reset Tools desktop override to ${FACTORY_RESET_DESKTOP_DEST}"
fi

# Snap Firmware Updater desktop files use an absolute icon path.
for fw_src_var in FIRMWARE_UPDATER_SNAP_DESKTOP_SRC FIRMWARE_UPDATER_APP_SNAP_DESKTOP_SRC; do
  fw_src="${!fw_src_var}"
  if [[ "${fw_src_var}" == "FIRMWARE_UPDATER_APP_SNAP_DESKTOP_SRC" ]]; then
    fw_dest="${FIRMWARE_UPDATER_APP_DESKTOP_DEST}"
  else
    fw_dest="${FIRMWARE_UPDATER_DESKTOP_DEST}"
  fi
  if [[ -f "${fw_src}" ]]; then
    mkdir -p "${APPS_DEST}"
    python3 - <<'PY' "${fw_src}" "${fw_dest}"
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
text = src.read_text(encoding="utf-8")

if re.search(r"^Icon=.*$", text, flags=re.M):
    text = re.sub(r"^Icon=.*$", "Icon=firmware-updater_firmware-updater", text, flags=re.M)
else:
    text += "\nIcon=firmware-updater_firmware-updater\n"

dest.write_text(text, encoding="utf-8")
PY
    echo "Installed Firmware Updater desktop override to ${fw_dest}"
  fi
done

# Snap Spotify desktop file uses an absolute icon path, which bypasses icon themes.
if [[ -f "${SPOTIFY_SNAP_DESKTOP_SRC}" ]]; then
  echo
  echo "=== APP ICON OVERRIDES (Spotify/Yubico) ==="
  mkdir -p "${APPS_DEST}"
  python3 - <<'PY' "${SPOTIFY_SNAP_DESKTOP_SRC}" "${SPOTIFY_DESKTOP_DEST}"
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
text = src.read_text(encoding="utf-8")

if re.search(r"^Icon=.*$", text, flags=re.M):
    text = re.sub(r"^Icon=.*$", "Icon=spotify_spotify", text, flags=re.M)
else:
    text += "\nIcon=spotify_spotify\n"

dest.write_text(text, encoding="utf-8")
PY
  echo "Installed Spotify desktop override to ${SPOTIFY_DESKTOP_DEST}"
fi

# Some Yubico desktop entries use absolute icon paths; normalize to icon-theme name.
if [[ -f "${YUBICO_DESKTOP_SRC}" ]]; then
  mkdir -p "${APPS_DEST}"
  python3 - <<'PY' "${YUBICO_DESKTOP_SRC}" "${YUBICO_DESKTOP_DEST}"
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
text = src.read_text(encoding="utf-8")

if re.search(r"^Icon=.*$", text, flags=re.M):
    text = re.sub(r"^Icon=.*$", "Icon=com.yubico.yubioath", text, flags=re.M)
else:
    text += "\nIcon=com.yubico.yubioath\n"

dest.write_text(text, encoding="utf-8")
PY
  echo "Installed Yubico desktop override to ${YUBICO_DESKTOP_DEST}"
fi

# Override Toshy tray icons with themed versions when Toshy is installed.
TOSHY_ICON_CHECK="${PREFIX}/.local/share/icons/hicolor/scalable/apps/toshy_app_icon_rainbow.svg"
if [[ -f "${TOSHY_ICON_CHECK}" ]]; then
  echo
  echo "=== APP ICON OVERRIDES (Toshy) ==="
  TOSHY_ICONS_DIR="${PREFIX}/.local/share/icons/hicolor/scalable/apps"
  for icon_name in toshy_app_icon_rainbow toshy_app_icon_rainbow_inverse toshy_app_icon_rainbow_inverse_grayscale; do
    src="${ICONS_SRC}/scalable/apps/${icon_name}.svg"
    if [[ -f "${src}" ]]; then
      cp -f "${src}" "${TOSHY_ICONS_DIR}/${icon_name}.svg"
    fi
  done
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f "${PREFIX}/.local/share/icons/hicolor" || true
  fi
  echo "Installed themed Toshy icons to ${TOSHY_ICONS_DIR}"
fi

# Override Yubico Authenticator tray icon with themed version when installed.
# The app hardcodes an absolute path to its bundled 32x32 PNG for the system tray,
# so we replace that file directly (after resizing our themed icon).
YUBICO_DESKTOP_CHECK="${PREFIX}/.local/share/applications/com.yubico.yubioath.desktop"
if [[ -f "${YUBICO_DESKTOP_CHECK}" ]]; then
  echo
  echo "=== APP ICON OVERRIDES (Yubico Authenticator) ==="
  # Copy themed icons into hicolor for desktop/launcher use.
  YUBICO_ICONS_DIR="${PREFIX}/.local/share/icons/hicolor/256x256/apps"
  mkdir -p "${YUBICO_ICONS_DIR}"
  for icon_name in com.yubico.yubioath yubico-authenticator; do
    src="${ICONS_SRC}/256x256/apps/${icon_name}.png"
    if [[ -f "${src}" ]]; then
      cp -f "${src}" "${YUBICO_ICONS_DIR}/${icon_name}.png"
    fi
  done
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f "${PREFIX}/.local/share/icons/hicolor" || true
  fi
  # Replace the bundled tray icon that the app references by absolute path.
  YUBICO_EXEC=$(grep -oP '(?<=^Exec=").*(?=")' "${YUBICO_DESKTOP_CHECK}" 2>/dev/null \
             || grep -oP '(?<=^Exec=)\S+' "${YUBICO_DESKTOP_CHECK}" 2>/dev/null)
  if [[ -n "${YUBICO_EXEC}" ]]; then
    YUBICO_APP_DIR="$(dirname "${YUBICO_EXEC}")"
    YUBICO_TRAY_ICON="${YUBICO_APP_DIR}/data/flutter_assets/resources/icons/com.yubico.yubioath-32x32.png"
    if [[ -f "${YUBICO_TRAY_ICON}" ]] && command -v convert >/dev/null 2>&1; then
      convert "${ICONS_SRC}/256x256/apps/com.yubico.yubioath.png" -resize 32x32 "${YUBICO_TRAY_ICON}"
      echo "Replaced Yubico tray icon at ${YUBICO_TRAY_ICON}"
    fi
  fi
  echo "Installed themed Yubico Authenticator icons"
fi

# Optional Cursor settings merge.
# Apply when Cursor appears to be installed for this user.
if [[ -f "${CURSOR_SETTINGS_TEMPLATE}" ]]; then
  echo
  echo "=== CURSOR SETTINGS INTEGRATION ==="
  if [[ -d "${CURSOR_SETTINGS_DIR}" ]] || ([[ "${PREFIX}" == "${HOME}" ]] && command -v cursor >/dev/null 2>&1); then
    mkdir -p "${CURSOR_SETTINGS_DIR}"
    python3 - <<'PY' "${CURSOR_SETTINGS_DEST}" "${CURSOR_SETTINGS_TEMPLATE}"
import json
import pathlib
import sys

dest = pathlib.Path(sys.argv[1])
template = pathlib.Path(sys.argv[2])

template_data = json.loads(template.read_text(encoding="utf-8"))
if dest.exists():
    try:
        dest_data = json.loads(dest.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Cursor settings JSON is invalid ({dest}): {exc}") from exc
else:
    dest_data = {}

def merge_dict(base, overlay):
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            merge_dict(base[key], value)
        else:
            base[key] = value

merge_dict(dest_data, template_data)
# Cleanup for previously-added setting we reverted in repo.
if dest_data.get("window.titleBarStyle") == "native" and "window.titleBarStyle" not in template_data:
    del dest_data["window.titleBarStyle"]
dest.write_text(json.dumps(dest_data, indent=2) + "\n", encoding="utf-8")
PY
    echo "Applied Cursor settings to ${CURSOR_SETTINGS_DEST}"
  fi
fi

# Optional Tilix color scheme install.
if [[ "${PREFIX}" == "${HOME}" ]] && [[ -f "${TILIX_THEME_SCRIPT}" ]]; then
  echo
  echo "=== TILIX COLOR SCHEME ==="
  if command -v tilix >/dev/null 2>&1 || [[ -d "${HOME}/.config/tilix" ]]; then
    if bash "${TILIX_THEME_SCRIPT}"; then
      echo "Applied Tilix color scheme."
    else
      echo "Warning: Tilix color scheme install failed; continuing install." >&2
    fi
  else
    echo "Tilix not installed; skipping color scheme setup."
  fi
fi

# Optional Firefox advanced theming helper (userChrome.css).
# Only run for the active user install and only if a Firefox profile exists.
if [[ "${PREFIX}" == "${HOME}" ]] && [[ -f "${FIREFOX_USERCHROME_SCRIPT}" ]]; then
  echo
  echo "=== FIREFOX ADVANCED THEMING (userChrome) ==="
  if bash "${FIREFOX_USERCHROME_SCRIPT}"; then
    echo "Applied Firefox userChrome.css via helper script."
  else
    echo "Warning: Firefox userChrome helper failed; continuing install." >&2
  fi
fi

# Optional Vivaldi proof-of-concept UI mod install.
if [[ -f "${VIVALDI_THEME_SCRIPT}" ]]; then
  echo
  echo "=== VIVALDI UI MOD ==="
  if command -v vivaldi >/dev/null 2>&1 || command -v vivaldi-stable >/dev/null 2>&1 || [[ -d "${HOME}/.config/vivaldi" ]]; then
    if bash "${VIVALDI_THEME_SCRIPT}" --prefix "${PREFIX}"; then
      echo "Installed Vivaldi UI mod assets."
    else
      echo "Warning: Vivaldi theme helper failed; continuing install." >&2
    fi
  else
    echo "Vivaldi not installed; skipping UI mod setup."
  fi
fi

# Optional bottom panel / Dash to Panel layout helper.
if [[ "${PREFIX}" == "${HOME}" ]] && [[ -f "${BOTTOM_PANEL_SCRIPT}" ]]; then
  echo
  echo "=== BOTTOM PANEL (Dash to Panel) ==="
  if bash "${BOTTOM_PANEL_SCRIPT}"; then
    echo "Configured Dash to Panel bottom panel layout."
  else
    echo "Warning: bottom panel setup helper failed; continuing install." >&2
  fi
fi

cat <<EOF

Installation complete.
GTK theme, Shell theme, and icons have been applied via gsettings.
If the User Themes extension was just installed, log out and back in
for the Shell theme to take effect.

Optional Firefox advanced theming:
  ${FIREFOX_USERCHROME_SCRIPT}

Optional Vivaldi UI mod:
  ${VIVALDI_THEME_SCRIPT}
EOF
