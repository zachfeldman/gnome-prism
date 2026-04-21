#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="${REPO_ROOT}/scripts/install.sh"
UNINSTALL_SCRIPT="${REPO_ROOT}/scripts/uninstall.sh"
BOTTOM_PANEL_SCRIPT="${REPO_ROOT}/scripts/setup_bottom_panel.sh"
RELOGIN_SCRIPT="${REPO_ROOT}/scripts/relogin_resume_cursor.sh"
FIREFOX_USERCHROME_SCRIPT="${REPO_ROOT}/scripts/apply_firefox_userchrome.sh"
VIVALDI_THEME_SCRIPT="${REPO_ROOT}/scripts/apply_vivaldi_theme.sh"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

echo "Checking shell syntax..."
bash -n "${INSTALL_SCRIPT}"
bash -n "${UNINSTALL_SCRIPT}"
bash -n "${BOTTOM_PANEL_SCRIPT}"
bash -n "${RELOGIN_SCRIPT}"
bash -n "${FIREFOX_USERCHROME_SCRIPT}"
bash -n "${VIVALDI_THEME_SCRIPT}"

echo "Running install into temporary prefix..."
fake_snap_dir="${tmpdir}/fake-snap-desktop"
mkdir -p "${fake_snap_dir}"
cat > "${fake_snap_dir}/firefox_firefox.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Firefox
Exec=firefox %u
Icon=/snap/firefox/current/default256.png
EOF

cat > "${fake_snap_dir}/spotify_spotify.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Spotify
Exec=spotify %u
Icon=/snap/spotify/current/usr/share/spotify/icons/spotify-linux-128.png
EOF

mkdir -p "${tmpdir}/fake-local-apps"
cat > "${tmpdir}/fake-local-apps/com.yubico.yubioath.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Yubico Authenticator
Exec=yubioath
Icon=/tmp/absolute/path/com.yubico.yubioath.png
EOF

mkdir -p "${tmpdir}/.config/Cursor/User"
cat > "${tmpdir}/.config/Cursor/User/settings.json" <<'EOF'
{
  "window.commandCenter": true
}
EOF

FIREFOX_SNAP_DESKTOP_SRC="${fake_snap_dir}/firefox_firefox.desktop" \
SPOTIFY_SNAP_DESKTOP_SRC="${fake_snap_dir}/spotify_spotify.desktop" \
YUBICO_DESKTOP_SRC="${tmpdir}/fake-local-apps/com.yubico.yubioath.desktop" \
  "${INSTALL_SCRIPT}" --prefix "${tmpdir}" >/dev/null

test -d "${tmpdir}/.themes/gnome-prism"
test -f "${tmpdir}/.themes/gnome-prism/index.theme"
test -d "${tmpdir}/.local/share/themes/gnome-prism"
test -f "${tmpdir}/.local/share/themes/gnome-prism/index.theme"
test -d "${tmpdir}/.icons/gnome-prism"
test -f "${tmpdir}/.icons/gnome-prism/index.theme"
test -d "${tmpdir}/.local/share/icons/gnome-prism"
test -f "${tmpdir}/.local/share/icons/gnome-prism/index.theme"
test -f "${tmpdir}/.local/share/icons/gnome-prism/256x256/apps/google-chrome.png"
test -f "${tmpdir}/.local/share/icons/gnome-prism/256x256/apps/spotify.png"
test -f "${tmpdir}/.local/share/icons/gnome-prism/256x256/apps/spotify_spotify.png"
test -f "${tmpdir}/.local/share/icons/gnome-prism/256x256/apps/signal-desktop.png"
test -f "${tmpdir}/.local/share/icons/gnome-prism/256x256/apps/vivaldi.png"
test -f "${tmpdir}/.local/share/icons/gnome-prism/256x256/apps/org.gnome.eog.png"
test -f "${tmpdir}/.local/share/icons/gnome-prism/256x256/apps/co.anysphere.cursor.png"
test -d "${tmpdir}/.local/share/backgrounds/gnome-prism"
test -f "${tmpdir}/.local/share/backgrounds/gnome-prism/gnome-prism-default-background.jpg"
test -f "${tmpdir}/.local/share/gnome-prism/vivaldi/mods/custom.css"
python3 - <<'PY' "${tmpdir}/.local/share/gnome-prism/vivaldi/mods/custom.css"
import pathlib
import sys

css = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
required_snippets = [
    '.tab-position .tab .close',
    '.tab-position .tab .button-toolbar.close',
    'font-size: 125% !important;',
    'min-height: 36px !important;',
    'opacity: 1 !important;',
]
missing = [snippet for snippet in required_snippets if snippet not in css]
if missing:
    raise SystemExit(f"Missing expected persistent-tab-close CSS snippets: {missing}")
PY
test -f "${tmpdir}/.local/share/applications/firefox_firefox.desktop"
test -f "${tmpdir}/.local/share/applications/spotify_spotify.desktop"
test -f "${tmpdir}/.local/share/applications/com.yubico.yubioath.desktop"
test -f "${tmpdir}/.config/Cursor/User/settings.json"
python3 - <<'PY' "${tmpdir}/.local/share/applications/firefox_firefox.desktop"
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
if "\nIcon=firefox_firefox\n" not in f"\n{text}\n":
    raise SystemExit("Expected Icon=firefox_firefox in desktop override")
PY
python3 - <<'PY' "${tmpdir}/.local/share/applications/spotify_spotify.desktop" "${tmpdir}/.local/share/applications/com.yubico.yubioath.desktop"
import pathlib
import sys

spotify = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
yubico = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
if "\nIcon=spotify_spotify\n" not in f"\n{spotify}\n":
    raise SystemExit("Expected Icon=spotify_spotify in desktop override")
if "\nIcon=com.yubico.yubioath\n" not in f"\n{yubico}\n":
    raise SystemExit("Expected Icon=com.yubico.yubioath in desktop override")
PY
python3 - <<'PY' "${tmpdir}/.config/Cursor/User/settings.json"
import json
import pathlib
import sys

settings = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
if settings.get("window.commandCenter") is not True:
    raise SystemExit("Expected existing Cursor setting to be preserved")
if settings.get("workbench.colorTheme") != "Default High Contrast":
    raise SystemExit("Expected Cursor workbench.colorTheme to be applied")
if settings.get("editor.fontFamily") != "DM Mono, Noto Sans Mono, monospace":
    raise SystemExit("Expected Cursor editor font family to be applied")
if "workbench.colorCustomizations" not in settings:
    raise SystemExit("Expected Cursor color customizations to be applied")
PY

echo "Running uninstall from temporary prefix..."
"${UNINSTALL_SCRIPT}" --prefix "${tmpdir}" >/dev/null

test ! -e "${tmpdir}/.themes/gnome-prism"
test ! -e "${tmpdir}/.local/share/themes/gnome-prism"
test ! -e "${tmpdir}/.icons/gnome-prism"
test ! -e "${tmpdir}/.local/share/icons/gnome-prism"
test ! -e "${tmpdir}/.local/share/backgrounds/gnome-prism"
test ! -e "${tmpdir}/.local/share/gnome-prism/vivaldi"
test ! -e "${tmpdir}/.local/share/applications/firefox_firefox.desktop"
test ! -e "${tmpdir}/.local/share/applications/spotify_spotify.desktop"
test ! -e "${tmpdir}/.local/share/applications/com.yubico.yubioath.desktop"

echo "Validating Firefox theme assets..."
test -f "${REPO_ROOT}/apps/firefox/gnome-prism-theme/manifest.json"
test -f "${REPO_ROOT}/apps/firefox/userchrome/userChrome.css"
test -f "${REPO_ROOT}/apps/firefox/userchrome/userContent.css"
test -f "${REPO_ROOT}/apps/firefox/README.md"
python3 - <<'PY' "${REPO_ROOT}/apps/firefox/gnome-prism-theme/manifest.json"
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
if manifest.get("manifest_version") != 2:
    raise SystemExit("Firefox theme manifest_version must be 2")
if "theme" not in manifest or "colors" not in manifest["theme"]:
    raise SystemExit("Firefox theme manifest is missing theme.colors")
required = {"frame", "toolbar", "toolbar_field", "tab_selected", "popup"}
missing = sorted(required - set(manifest["theme"]["colors"]))
if missing:
    raise SystemExit(f"Firefox theme manifest missing required colors: {', '.join(missing)}")
PY

echo "Testing Firefox userChrome helper script..."
fake_firefox_dir="${tmpdir}/.mozilla/firefox"
fake_profile_dir="${fake_firefox_dir}/abc.default-release"
mkdir -p "${fake_profile_dir}"
cat > "${fake_firefox_dir}/profiles.ini" <<'EOF'
[Profile0]
Name=default-release
IsRelative=1
Path=abc.default-release
Default=1
EOF

"${FIREFOX_USERCHROME_SCRIPT}" --prefix "${tmpdir}" >/dev/null
test -f "${fake_profile_dir}/chrome/userChrome.css"
test -f "${fake_profile_dir}/chrome/userContent.css"
test -f "${fake_profile_dir}/user.js"
python3 - <<'PY' "${fake_profile_dir}/user.js"
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
needle = 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
if needle not in text:
    raise SystemExit("Missing toolkit legacy pref in Firefox user.js")
PY

echo "All script tests passed."
