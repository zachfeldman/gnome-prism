#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ./scripts/setup_bottom_panel.sh [--skip-install] [--keep-ubuntu-dock]

Installs/enables Dash to Panel and configures a bottom panel layout.
EOF
}

SKIP_INSTALL=0
KEEP_UBUNTU_DOCK=0
DTP_UUID="dash-to-panel@jderose9.github.com"
DTP_INSTALLED_PATH=""
DTP_MONITOR_ID="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    --keep-ubuntu-dock)
      KEEP_UBUNTU_DOCK=1
      shift
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

# Auto-detect an existing Dash to Panel install and skip all install
# steps (including apt-get update) when it is already present.
if [[ "${SKIP_INSTALL}" -eq 0 ]]; then
  if command -v gnome-extensions >/dev/null 2>&1; then
    if gnome-extensions list | awk '/dash-to-panel/ {found=1} END {exit !found}'; then
      echo "Dash to Panel extension already present; skipping installation phase."
      SKIP_INSTALL=1
    fi
  fi

  if [[ "${SKIP_INSTALL}" -eq 0 ]] && [[ -d "${HOME}/.local/share/gnome-shell/extensions" ]]; then
    if ls "${HOME}/.local/share/gnome-shell/extensions" 2>/dev/null | awk '/dash-to-panel/ {found=1} END {exit !found}'; then
      echo "Dash to Panel files found under ~/.local/share/gnome-shell/extensions; skipping installation phase."
      SKIP_INSTALL=1
    fi
  fi
fi

install_dtp_from_extensions_gnome_org() {
  echo "Trying extensions.gnome.org fallback..."

  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for fallback installer." >&2
    exit 1
  fi
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "curl or wget is required for fallback installer." >&2
    exit 1
  fi

  SHELL_MAJOR="$(gnome-shell --version | awk '{print $3}' | awk -F. '{print $1}')"
  INFO_URL="https://extensions.gnome.org/extension-info/?uuid=${DTP_UUID}&shell_version=${SHELL_MAJOR}"
  INFO_DATA="$(python3 - <<'PY' "${INFO_URL}"
import json
import sys
from urllib.request import urlopen

url = sys.argv[1]
with urlopen(url, timeout=20) as r:
    data = json.loads(r.read().decode("utf-8"))
print(json.dumps({
    "download_url": data.get("download_url", ""),
    "uuid": data.get("uuid", "")
}))
PY
)"
  DOWNLOAD_PATH="$(python3 - <<'PY' "${INFO_DATA}"
import json
import sys
print(json.loads(sys.argv[1]).get("download_url", ""))
PY
)"
  INFO_UUID="$(python3 - <<'PY' "${INFO_DATA}"
import json
import sys
print(json.loads(sys.argv[1]).get("uuid", ""))
PY
)"
  if [[ -n "${INFO_UUID}" ]]; then
    DTP_UUID="${INFO_UUID}"
  fi

  if [[ -z "${DOWNLOAD_PATH}" ]]; then
    echo "Could not resolve Dash to Panel download URL for GNOME Shell ${SHELL_MAJOR}." >&2
    exit 1
  fi

  TMP_ZIP="$(mktemp --suffix=.zip)"
  trap 'rm -f "${TMP_ZIP}"' EXIT
  if command -v curl >/dev/null 2>&1; then
    curl -fL "https://extensions.gnome.org${DOWNLOAD_PATH}" -o "${TMP_ZIP}"
  else
    wget -qO "${TMP_ZIP}" "https://extensions.gnome.org${DOWNLOAD_PATH}"
  fi
  echo "Installing Dash to Panel from downloaded extension zip..."
  python3 - <<'PY' "${TMP_ZIP}" "${HOME}"
import json
import os
import sys
import zipfile

zip_path = sys.argv[1]
home = sys.argv[2]

with zipfile.ZipFile(zip_path) as zf:
    metadata = json.loads(zf.read("metadata.json").decode("utf-8"))
    uuid = metadata["uuid"]
    dest = os.path.join(home, ".local", "share", "gnome-shell", "extensions", uuid)
    if os.path.isdir(dest):
        import shutil
        shutil.rmtree(dest)
    os.makedirs(dest, exist_ok=True)
    zf.extractall(dest)
PY
  DTP_UUID="$(python3 - <<'PY' "${TMP_ZIP}"
import json
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as zf:
    metadata = json.loads(zf.read("metadata.json").decode("utf-8"))
print(metadata.get("uuid", "dash-to-panel@jderose9.github.com"))
PY
)"
  DTP_INSTALLED_PATH="${HOME}/.local/share/gnome-shell/extensions/${DTP_UUID}"

  if [[ -d "${DTP_INSTALLED_PATH}/schemas" ]] && command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas "${DTP_INSTALLED_PATH}/schemas" || true
  fi
}

if [[ "${SKIP_INSTALL}" -eq 0 ]]; then
  DTP_PKG_INSTALLED=false

  if command -v apt-get >/dev/null 2>&1; then
    # Debian/Ubuntu
    if dpkg -s gnome-shell-extension-dash-to-panel >/dev/null 2>&1; then
      echo "Package already installed: gnome-shell-extension-dash-to-panel"
      DTP_PKG_INSTALLED=true
    else
      if ! sudo apt-get update; then
        echo "Warning: apt-get update failed (likely due to an unrelated repository)." >&2
        echo "Continuing with cached package metadata..." >&2
      fi

      if sudo apt-get install -y gnome-shell-extension-dash-to-panel; then
        DTP_PKG_INSTALLED=true
      else
        echo "apt install failed for gnome-shell-extension-dash-to-panel."
        install_dtp_from_extensions_gnome_org
      fi
    fi
  elif command -v dnf >/dev/null 2>&1; then
    # Fedora/RHEL
    if rpm -q gnome-shell-extension-dash-to-panel >/dev/null 2>&1; then
      echo "Package already installed: gnome-shell-extension-dash-to-panel"
      DTP_PKG_INSTALLED=true
    else
      if sudo dnf install -y gnome-shell-extension-dash-to-panel; then
        DTP_PKG_INSTALLED=true
      else
        echo "dnf install failed for gnome-shell-extension-dash-to-panel."
        install_dtp_from_extensions_gnome_org
      fi
    fi
  else
    echo "No supported package manager found (apt or dnf). Trying extensions.gnome.org..."
    install_dtp_from_extensions_gnome_org
  fi
fi

if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "gnome-extensions command not found." >&2
  exit 1
fi

# Find extension UUID from installed list or local path.
LISTED_UUID="$(gnome-extensions list | awk '/dash-to-panel/ {print; exit}')"
if [[ -n "${LISTED_UUID}" ]]; then
  DTP_UUID="${LISTED_UUID}"
elif [[ -d "${HOME}/.local/share/gnome-shell/extensions/${DTP_UUID}" ]]; then
  DTP_INSTALLED_PATH="${HOME}/.local/share/gnome-shell/extensions/${DTP_UUID}"
else
  ALT_UUID="$(ls "${HOME}/.local/share/gnome-shell/extensions" 2>/dev/null | awk '/dash-to-panel/ {print; exit}')"
  if [[ -n "${ALT_UUID}" ]]; then
    DTP_UUID="${ALT_UUID}"
    DTP_INSTALLED_PATH="${HOME}/.local/share/gnome-shell/extensions/${DTP_UUID}"
  fi
fi

if [[ -z "${DTP_UUID}" ]]; then
  echo "Dash to Panel extension not found after installation attempt." >&2
  echo "Expected under ~/.local/share/gnome-shell/extensions/ or gnome-extensions list." >&2
  exit 1
fi

if ! gnome-extensions enable "${DTP_UUID}"; then
  if [[ -n "${DTP_INSTALLED_PATH}" && -d "${DTP_INSTALLED_PATH}" ]]; then
    echo "Extension files are present but GNOME Shell has not registered it yet."
    echo "Queuing enablement in org.gnome.shell enabled-extensions..."
    python3 - <<'PY' "${DTP_UUID}"
import ast
import subprocess
import sys

uuid = sys.argv[1]
current = subprocess.check_output(
    ["gsettings", "get", "org.gnome.shell", "enabled-extensions"],
    text=True
).strip()
try:
    items = ast.literal_eval(current)
except Exception:
    items = []

if uuid not in items:
    items.append(uuid)
    value = "[" + ", ".join("'" + i.replace("'", "\\'") + "'" for i in items) + "]"
    subprocess.check_call(
        ["gsettings", "set", "org.gnome.shell", "enabled-extensions", value]
    )
PY
    echo "Dash to Panel will be enabled after next login."
  else
    echo "Failed to enable ${DTP_UUID}. Make sure extension is installed and GNOME Shell is running." >&2
    exit 1
  fi
fi

if [[ "${KEEP_UBUNTU_DOCK}" -eq 0 ]]; then
  UBUNTU_DOCK_UUID="ubuntu-dock@ubuntu.com"
  if gnome-extensions info "${DTP_UUID}" 2>/dev/null | grep -q "State: ENABLED"; then
    echo "Disabling Ubuntu Dock now that Dash to Panel is enabled..."
    gnome-extensions disable "${UBUNTU_DOCK_UUID}" || true
  else
    # Dash to Panel isn't loaded yet (e.g. just installed on Wayland).
    # Leave a one-shot autostart helper that will disable Ubuntu Dock on
    # next login once Dash to Panel is active.
    AUTOSTART_DIR="${HOME}/.config/autostart"
    AUTOSTART_ENTRY="${AUTOSTART_DIR}/gnome-prism-disable-dock.desktop"
    mkdir -p "${AUTOSTART_DIR}"
    cat > "${AUTOSTART_ENTRY}" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=GNOME Prism — disable Ubuntu Dock
Comment=One-shot helper: disables Ubuntu Dock once Dash to Panel is active, then removes itself.
Exec=/bin/bash -c 'sleep 3; if gnome-extensions info dash-to-panel@jderose9.github.com 2>/dev/null | grep -q "State: ACTIVE"; then gnome-extensions disable ubuntu-dock@ubuntu.com 2>/dev/null; fi; rm -f "$HOME/.config/autostart/gnome-prism-disable-dock.desktop"'
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP
    echo "Dash to Panel is not yet active; installed one-shot autostart helper"
    echo "to disable Ubuntu Dock on next login."
  fi
fi

SCHEMA="org.gnome.shell.extensions.dash-to-panel"

set_dtp_setting() {
  local key="$1"
  local value="$2"
  gsettings set "${SCHEMA}" "${key}" "${value}" >/dev/null 2>&1 || true
  dconf write "/org/gnome/shell/extensions/dash-to-panel/${key}" "${value}" >/dev/null 2>&1 || true
}

set_interface_setting() {
  local key="$1"
  local value="$2"
  gsettings set org.gnome.desktop.interface "${key}" "${value}" >/dev/null 2>&1 || true
  dconf write "/org/gnome/desktop/interface/${key}" "${value}" >/dev/null 2>&1 || true
}

set_dtp_show_apps_icon() {
  local icon_path
  icon_path="${REPO_ROOT}/assets/dash-to-panel/show-apps-icon.svg"
  if [[ -f "${icon_path}" ]]; then
    set_dtp_setting "show-apps-icon-file" "'${icon_path}'"
  fi
}

set_dtp_panel_elements_layout() {
  local panel_positions_raw monitor_id layout_json quoted_layout
  panel_positions_raw="$(dconf read /org/gnome/shell/extensions/dash-to-panel/panel-positions || echo "'{}'")"
  monitor_id="$(python3 - <<'PY' "${panel_positions_raw}"
import ast
import sys

raw = sys.argv[1]
try:
    data = ast.literal_eval(raw)
except Exception:
    data = {}

if isinstance(data, dict) and data:
    print(next(iter(data.keys())))
else:
    print("0")
PY
)"
  DTP_MONITOR_ID="${monitor_id}"

  layout_json="$(python3 - <<'PY' "${monitor_id}"
import json
import sys

mid = sys.argv[1]
layout = {
    mid: [
        {"element": "showAppsButton", "visible": True, "position": "stackedTL"},
        {"element": "activitiesButton", "visible": False, "position": "stackedTL"},
        {"element": "leftBox", "visible": True, "position": "stackedTL"},
        {"element": "taskbar", "visible": True, "position": "stackedTL"},
        {"element": "centerBox", "visible": False, "position": "stackedBR"},
        {"element": "rightBox", "visible": True, "position": "stackedBR"},
        {"element": "systemMenu", "visible": True, "position": "stackedBR"},
        {"element": "dateMenu", "visible": True, "position": "stackedBR"},
        {"element": "desktopButton", "visible": False, "position": "stackedBR"},
    ]
}
print(json.dumps(layout, separators=(",", ":")))
PY
)"

  quoted_layout="'${layout_json}'"
  set_dtp_setting "panel-element-positions" "${quoted_layout}"
}

set_dtp_panel_geometry() {
  local lengths_json anchors_json quoted_lengths quoted_anchors
  lengths_json="$(python3 - <<'PY' "${DTP_MONITOR_ID}"
import json
import sys
mid = sys.argv[1]
print(json.dumps({mid: 100}, separators=(",", ":")))
PY
)"
  anchors_json="$(python3 - <<'PY' "${DTP_MONITOR_ID}"
import json
import sys
mid = sys.argv[1]
print(json.dumps({mid: "MIDDLE"}, separators=(",", ":")))
PY
)"
  quoted_lengths="'${lengths_json}'"
  quoted_anchors="'${anchors_json}'"
  set_dtp_setting "panel-lengths" "${quoted_lengths}"
  set_dtp_setting "panel-anchors" "${quoted_anchors}"
  # Inset panel from edges so transparent desktop shows around it.
  # This creates left/right and bottom breathing room.
  set_dtp_setting "panel-side-margins" "12"
  set_dtp_setting "panel-top-bottom-margins" "10"
}

apply_dtp_stylesheet_overrides() {
  local stylesheet_path
  stylesheet_path="${HOME}/.local/share/gnome-shell/extensions/${DTP_UUID}/stylesheet.css"
  [[ -f "${stylesheet_path}" ]] || return 0

  python3 - <<'PY' "${stylesheet_path}"
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

begin = "/* GNOME_PRISM_OVERRIDES_BEGIN */"
end = "/* GNOME_PRISM_OVERRIDES_END */"

if begin in text and end in text:
    pre = text.split(begin, 1)[0]
    post = text.split(end, 1)[1]
    text = pre.rstrip() + "\n\n" + post.lstrip()

override = f"""
{begin}
#dashtopanelTaskbar .dash-item-container .overview-tile .dtp-container,
#dashtopanelTaskbar .dash-item-container .show-apps {{
  min-width: 50px !important;
  min-height: 50px !important;
  border-top: 1px solid #bda7f0 !important;
  border-bottom: 1px solid #bda7f0 !important;
  border-left: 1px solid #bda7f0 !important;
  border-right: 0 !important;
  margin: 0 !important;
  padding: 0 !important;
  border-radius: 0 !important;
}}

#dashtopanelTaskbar .dash-item-container .show-apps,
#dashtopanelTaskbar .dash-item-container .show-apps:hover,
#dashtopanelTaskbar .dash-item-container .show-apps:focus,
#dashtopanelTaskbar .dash-item-container .show-apps:active {{
  background: #bda7f0 !important;
}}

.dashtopanelMainPanel .dash-item-container .show-apps,
.dashtopanelMainPanel .dash-item-container .show-apps:hover,
.dashtopanelMainPanel .dash-item-container .show-apps:focus,
.dashtopanelMainPanel .dash-item-container .show-apps:active {{
  background: #bda7f0 !important;
}}

#dashtopanelTaskbar .dash-item-container:last-child .overview-tile .dtp-container,
#dashtopanelTaskbar .dash-item-container:last-child .show-apps {{
  border-right: 1px solid #bda7f0 !important;
}}

#dashtopanelTaskbar .dash-item-container:first-child,
#dashtopanelTaskbar .dash-item-container:first-child > StWidget,
#dashtopanelTaskbar .dash-item-container:first-child .show-apps {{
  min-width: 75px !important;
  max-width: 75px !important;
  width: 75px !important;
}}

#dashtopanelTaskbar .overview-icon,
#dashtodockContainer .overview-icon,
#dash .overview-icon {{
  icon-size: 7px !important;
  padding: 7px !important;
  margin: 0 !important;
  animation: none !important;
}}

#dashtopanelTaskbar .dash-item-container .overview-tile .dtp-container,
#dashtopanelTaskbar .dash-item-container .show-apps {{
  transition:
    border-color 120ms ease-out,
    box-shadow 120ms ease-out,
    background-color 120ms ease-out !important;
}}

#dashtopanelTaskbar .dash-item-container .overview-tile .dtp-container:hover,
#dashtopanelTaskbar .dash-item-container .overview-tile .dtp-container:focus,
#dashtopanelTaskbar .dash-item-container .show-apps:hover,
#dashtopanelTaskbar .dash-item-container .show-apps:focus {{
  border-color: #ff7447 !important;
  box-shadow: inset 0 0 0 1px rgba(255, 116, 71, 0.25) !important;
}}

#dashtopanelTaskbar .dash-item-container .overview-tile .dtp-container:active,
#dashtopanelTaskbar .dash-item-container .show-apps:active {{
  border-color: #ff7447 !important;
  background-color: rgba(255, 116, 71, 0.45) !important;
}}

#dashtopanelTaskbar .dash-item-container .show-apps .overview-icon,
#dashtopanelTaskbar .dash-item-container .show-apps:hover .overview-icon {{
  color: #000000 !important;
}}

.dashtopanelMainPanel .dash-item-container .show-apps .overview-icon,
.dashtopanelMainPanel .dash-item-container .show-apps:hover .overview-icon,
.dashtopanelMainPanel .dash-item-container .show-apps .show-apps-icon,
.dashtopanelMainPanel .dash-item-container .show-apps:hover .show-apps-icon {{
  color: #000000 !important;
}}

#dashtopanelScrollview .badge,
#dashtopanelTaskbar .badge,
.dashtopanelMainPanel .badge,
#dashtopanelScrollview .number-overlay,
#dashtopanelTaskbar .number-overlay,
.dashtopanelMainPanel .number-overlay,
#dashtopanelScrollview .notification-badge,
#dashtopanelTaskbar .notification-badge,
.dashtopanelMainPanel .notification-badge {{
  border-radius: 0 !important;
  font-family: "Noto Sans Mono", "DM Mono", monospace !important;
  font-weight: 400 !important;
  font-size: 10px !important;
  line-height: 1.1 !important;
  min-width: 1.1em !important;
  min-height: 1.1em !important;
  padding: 0.05em 0.2em !important;
  margin: 0 0 0 2px !important;
  text-align: center !important;
  color: #bda7f0 !important;
  border: 1px solid #bda7f0 !important;
  background-color: #000000 !important;
  box-shadow: none !important;
}}

#dashtopanelTaskbar .dash-item-container,
#dashtopanelTaskbar .overview-tile,
#dashtopanelTaskbar .app-well-app,
#dashtopanelTaskbar .app-well-app:hover,
#dashtopanelTaskbar .app-well-app:focus,
#dashtopanelTaskbar .app-well-app:active,
#dashtopanelTaskbar .highlight-appicon-hover,
#dashtopanelTaskbar .highlight-appicon-hover * {{
  animation: none !important;
}}

.dashtopanelPanel,
.dashtopanelPanel .dashtopanelMainPanel,
.dashtopanelMainPanel {{
  border: 1px solid #bda7f0 !important;
  border-top: 1px solid #bda7f0 !important;
  border-right: 1px solid #bda7f0 !important;
  border-bottom: 1px solid #bda7f0 !important;
  border-left: 1px solid #bda7f0 !important;
  outline: 1px solid #bda7f0 !important;
  outline-offset: -1px !important;
  border-radius: 0 !important;
  background: #000000 !important;
  box-shadow: none !important;
}}

.dashtopanelMainPanel #panelRight {{
  border: 0 !important;
  border-top: 1px solid #bda7f0 !important;
  border-bottom: 1px solid #bda7f0 !important;
  border-right: 1px solid #bda7f0 !important;
  border-radius: 0 !important;
  padding: 0 6px !important;
  margin: 0 !important;
  background: #000000 !important;
  box-shadow: inset 0 1px 0 #bda7f0, inset 0 -1px 0 #bda7f0 !important;
}}

.dashtopanelMainPanel #panelRight .panel-button,
.dashtopanelMainPanel #panelRight .panel-button:hover,
.dashtopanelMainPanel #panelRight .panel-button:focus,
.dashtopanelMainPanel #panelRight .panel-button:checked,
.dashtopanelMainPanel .panel-button.clock-display,
.dashtopanelMainPanel .panel-button.clock-display:hover,
.dashtopanelMainPanel .panel-button.clock-display:focus,
.dashtopanelMainPanel .panel-button.clock-display:checked {{
  border: 0 !important;
  border-radius: 0 !important;
  padding: 0 4px !important;
  margin: 0 !important;
  min-width: 0 !important;
  color: #bda7f0 !important;
  background: #000000 !important;
  box-shadow: none !important;
}}

.dashtopanelMainPanel .panel-button.clock-display {{
  min-width: 92px !important;
}}

.dashtopanelMainPanel #panelRight .panel-button.clock-display .clock {{
  text-align: center !important;
}}

.dashtopanelMainPanel #panelLeft > #showAppsButton,
.dashtopanelMainPanel #panelLeft > #showAppsButton .show-apps {{
  background: #bda7f0 !important;
}}

.dashtopanelMainPanel #panelLeft > #showAppsButton .show-apps .overview-icon {{
  color: #000000 !important;
}}
{end}
"""

text = text.rstrip() + "\n\n" + override + "\n"
path.write_text(text, encoding="utf-8")
PY
}

apply_dtp_code_overrides() {
  local panel_js_path appicons_js_path taskbar_js_path
  panel_js_path="${HOME}/.local/share/gnome-shell/extensions/${DTP_UUID}/panel.js"
  appicons_js_path="${HOME}/.local/share/gnome-shell/extensions/${DTP_UUID}/appIcons.js"
  taskbar_js_path="${HOME}/.local/share/gnome-shell/extensions/${DTP_UUID}/taskbar.js"
  [[ -f "${panel_js_path}" ]] || return 0

  python3 - <<'PY' "${panel_js_path}"
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

begin = "// GNOME_PRISM_CLOCK_OVERRIDE_BEGIN"
end = "// GNOME_PRISM_CLOCK_OVERRIDE_END"

if begin in text and end in text:
    pre = text.split(begin, 1)[0]
    post = text.split(end, 1)[1]
    text = pre + post

needle = "      if (this.geom.vertical) {\n"
inject = """      // GNOME_PRISM_CLOCK_OVERRIDE_BEGIN
      if (!this.geom.vertical && this.statusArea.dateMenu) {
        const _gnomePrismApplyRightPanelBorders = () => {
          const rightActors = []
          const systemName = Utils.getSystemMenuInfo().name
          const systemContainer = this.statusArea[systemName]?.container
          const dateContainer = this.statusArea.dateMenu?.container
          if (systemContainer) rightActors.push(systemContainer)
          if (dateContainer) rightActors.push(dateContainer)
          if (this._rightBox) rightActors.push(this._rightBox)

          rightActors.forEach((actor) => {
            const rightPadding = actor === dateContainer ? 20 : 0
            actor.set_style(
              'border-top: 1px solid #bda7f0;' +
                'border-bottom: 1px solid #bda7f0;' +
                'border-right: 0;' +
                'border-left: 0;' +
                'border-radius: 0;' +
                'margin: 0;' +
                'padding: 0 ' + rightPadding + 'px 0 0;' +
                'background: #000000;' +
                'box-shadow: none;',
            )
          })
        }

        const _gnomePrismIfaceSettings = new imports.gi.Gio.Settings({ schema_id: 'org.gnome.desktop.interface' })
        const _gnomePrismClockUpdate = () => {
          const dt = GLib.DateTime.new_now_local()
          const is12h = _gnomePrismIfaceSettings.get_string('clock-format') === '12h'
          const time = is12h ? dt.format('%l:%M %p').trim() : dt.format('%H:%M')
          const date = dt.format('%m/%d/%Y')
          const clockText = this.statusArea.dateMenu._clockDisplay.clutter_text
          clockText.set_use_markup(true)
          clockText.set_markup(
            `<span font_desc=\"Noto Sans Mono Bold 13\">${time}</span>\n<span font_desc=\"Noto Sans Mono 8\">${date}</span>`,
          )
          clockText.ellipsize = Pango.EllipsizeMode.NONE
          if (clockText.set_line_alignment) {
            clockText.set_line_alignment(Pango.Alignment.CENTER)
          }
          if (clockText.set_justify) {
            clockText.set_justify(true)
          }
          this.statusArea.dateMenu._clockDisplay.x_align = Clutter.ActorAlign.CENTER
        }
        _gnomePrismApplyRightPanelBorders()
        _gnomePrismClockUpdate()
        this._signalsHandler.add([
          this.panel,
          'style-changed',
          () => _gnomePrismApplyRightPanelBorders(),
        ])
        this._signalsHandler.add([
          this.statusArea.dateMenu._clock,
          'notify::clock',
          () => _gnomePrismClockUpdate(),
        ])
      }
      // GNOME_PRISM_CLOCK_OVERRIDE_END
"""

if needle in text:
    text = text.replace(needle, inject + needle, 1)

path.write_text(text, encoding="utf-8")
PY

  [[ -f "${taskbar_js_path}" ]] || return 0
  python3 - <<'PY' "${taskbar_js_path}"
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old = """        this._timeoutsHandler.add([
          T1,
          100,
          () =>
            Utils.ensureActorVisibleInScrollView(
              this._scrollView,
              appIcon,
              this._scrollView._dtpFadeSize,
            ),
        ])
"""

new = """        // GNOME_PRISM_HOVER_SCROLL_SUPPRESS_BEGIN
        // Suppress hover-time auto-scroll nudges that can look like
        // lateral icon drift while hover animation is active.
        // Keep click/focus visibility behavior intact elsewhere.
        // GNOME_PRISM_HOVER_SCROLL_SUPPRESS_END
"""

if old in text:
    text = text.replace(old, new, 1)

# Replace SIMPLE hover clone raise() calls with direct actor translation.
# This avoids clone/source alignment drift and avoids relying on CSS :hover
# support for St.Icon nodes.
old_simple_hover = """        if (!appIcon.isDragged && iconAnimationSettings.type == 'SIMPLE')
          appIcon.get_parent().raise(1)
        else if (
          !appIcon.isDragged &&
          (iconAnimationSettings.type == 'RIPPLE' ||
            iconAnimationSettings.type == 'PLANK')
        )
          this._updateIconAnimations()
      } else {
        this._timeoutsHandler.remove(T1)

        if (!appIcon.isDragged && iconAnimationSettings.type == 'SIMPLE')
          appIcon.get_parent().raise(0)
      }
"""

new_simple_hover = """        if (!appIcon.isDragged && iconAnimationSettings.type == 'SIMPLE') {
          Utils.stopAnimations(appIcon)
          Utils.animate(appIcon, {
            // Counter residual left/down drift by explicitly nudging
            // right and up on horizontal panels.
            translation_x: this.dtpPanel.geom.vertical ? 0 : 4,
            translation_y: this.dtpPanel.geom.vertical ? 0 : -5,
            time: 0.12,
            transition: 'easeOutQuad',
          })
        } else if (
          !appIcon.isDragged &&
          (iconAnimationSettings.type == 'RIPPLE' ||
            iconAnimationSettings.type == 'PLANK')
        ) {
          this._updateIconAnimations()
        }
      } else {
        this._timeoutsHandler.remove(T1)

        if (!appIcon.isDragged && iconAnimationSettings.type == 'SIMPLE') {
          Utils.stopAnimations(appIcon)
          Utils.animate(appIcon, {
            translation_x: 0,
            translation_y: 0,
            time: 0.12,
            transition: 'easeOutQuad',
          })
        }
      }
"""

if old_simple_hover in text:
    text = text.replace(old_simple_hover, new_simple_hover, 1)

# If a prior direct-translation patch is already present, retune it in place.
old_simple_hover_patched = """        if (!appIcon.isDragged && iconAnimationSettings.type == 'SIMPLE') {
          Utils.stopAnimations(appIcon)
          Utils.animate(appIcon, {
            translation_x: 0,
            translation_y: this.dtpPanel.geom.vertical ? 0 : -1,
            time: 0.12,
            transition: 'easeOutQuad',
          })
        } else if (
          !appIcon.isDragged &&
          (iconAnimationSettings.type == 'RIPPLE' ||
            iconAnimationSettings.type == 'PLANK')
        ) {
          this._updateIconAnimations()
        }
      } else {
        this._timeoutsHandler.remove(T1)

        if (!appIcon.isDragged && iconAnimationSettings.type == 'SIMPLE') {
          Utils.stopAnimations(appIcon)
          Utils.animate(appIcon, {
            translation_x: 0,
            translation_y: 0,
            time: 0.12,
            transition: 'easeOutQuad',
          })
        }
      }
"""

if old_simple_hover_patched in text:
    text = text.replace(old_simple_hover_patched, new_simple_hover, 1)

# Fallback retune for already-patched variants with different x-counter values.
text = text.replace(
    "translation_x: this.dtpPanel.geom.vertical ? 0 : 1,",
    "translation_x: this.dtpPanel.geom.vertical ? 0 : 4,",
)
text = text.replace(
    "translation_x: this.dtpPanel.geom.vertical ? 0 : 2,",
    "translation_x: this.dtpPanel.geom.vertical ? 0 : 4,",
)
text = text.replace(
    "translation_x: this.dtpPanel.geom.vertical ? 0 : 3,",
    "translation_x: this.dtpPanel.geom.vertical ? 0 : 4,",
)

# Ensure hover raise animation on horizontal panels never drifts on X.
old_raise = """      options[vertical ? 'translation_x' : 'translation_y'] =
        translationDirection * translationEnd
"""
new_raise = """      if (vertical) {
        options.translation_x = translationDirection * translationEnd
        options.translation_y = 0
      } else {
        options.translation_x = 0
        options.translation_y = translationDirection * translationEnd
      }
"""
if old_raise in text:
    text = text.replace(old_raise, new_raise, 1)

# Ensure stretch animation also pins the orthogonal axis to zero.
old_stretch = """        let options = {
          time: duration,
          transition: 'easeOutQuad',
        }
        options[animatedProperty] = zoom * translation
"""
new_stretch = """        let options = {
          time: duration,
          transition: 'easeOutQuad',
        }
        if (this._dtpPanel.geom.vertical) {
          options.translation_x = zoom * translation
          options.translation_y = 0
        } else {
          options.translation_y = zoom * translation
          options.translation_x = 0
        }
"""
if old_stretch in text:
    text = text.replace(old_stretch, new_stretch, 1)

# Pin the initial raised clone X position so it cannot animate diagonally
# from a stale translation_x value on hover-in / hover-out.
pin_needle = "      this._raisedClone = cloneButton.child\n"
pin_line = "      if (!this._dtpPanel.geom.vertical) this._raisedClone.translation_x = 0\n"
if pin_needle in text and pin_line not in text:
    text = text.replace(pin_needle, pin_needle + pin_line, 1)

# Pin the source container X as well; cloneContainer translation_x is
# bound to this.translation_x, and stale X can cause apparent left bias.
pin_container_needle = "      let vertical =\n        panelPosition == St.Side.LEFT || panelPosition == St.Side.RIGHT\n"
pin_container_line = pin_container_needle + "      if (!vertical) this.translation_x = 0\n"
if pin_container_needle in text and pin_container_line not in text:
    text = text.replace(pin_container_needle, pin_container_line, 1)

# Robust axis decision: in raise(), force "vertical" to match the panel's
# canonical geom flag, rather than relying on panelPosition calculations.
vertical_pin_old = "      let vertical =\n        panelPosition == St.Side.LEFT || panelPosition == St.Side.RIGHT\n"
vertical_pin_new = "      let vertical = this._dtpPanel.geom.vertical\n"
if vertical_pin_old in text:
    text = text.replace(vertical_pin_old, vertical_pin_new, 1)

# Ensure translation_x is pinned before the clone is created, so the clone
# doesn't start with a stale X that can visually look like left drift.
old_raise_block = """    raise(level) {
      if (this._raisedClone) Utils.stopAnimations(this._raisedClone)
      else if (level) this._createRaisedClone()
      else return

"""
new_raise_block = """    raise(level) {
      if (!this._dtpPanel.geom.vertical) this.translation_x = 0
      if (this._raisedClone) Utils.stopAnimations(this._raisedClone)
      else if (level) this._createRaisedClone()
      else return

"""
if old_raise_block in text and new_raise_block not in text:
    text = text.replace(old_raise_block, new_raise_block, 1)

# Align raised clone to source icon for horizontal panels.
# In some themed setups the clone appears ~1px left of the source on hover-in.
old_update_clone = """    _updateCloneContainerPosition(cloneContainer) {
      let [stageX, stageY] = this.get_transformed_position()

      cloneContainer.set_position(
        stageX - this._dtpPanel.panelBox.translation_x - this.translation_x,
        stageY - this._dtpPanel.panelBox.translation_y - this.translation_y,
      )
    }
"""
new_update_clone = """    _updateCloneContainerPosition(cloneContainer) {
      let [stageX, stageY] = this.get_transformed_position()
      const horizontalCloneXCorrection = this._dtpPanel.geom.vertical ? 0 : 1

      cloneContainer.set_position(
        stageX -
          this._dtpPanel.panelBox.translation_x -
          this.translation_x +
          horizontalCloneXCorrection,
        stageY - this._dtpPanel.panelBox.translation_y - this.translation_y,
      )
    }
"""
if old_update_clone in text:
    text = text.replace(old_update_clone, new_update_clone, 1)

# ── GNOME_PRISM: final-pass regex cleanup ──────────────────────────
# Regardless of which earlier patches matched, these regexes ensure the
# installed file ends up in the correct state.
import re as _re

# 1. Restore hover-in SIMPLE branch to call raise(1).
_hover_in_pat = _re.compile(
    r"(if \(!appIcon\.isDragged && iconAnimationSettings\.type == 'SIMPLE'\))"
    r"([\s\S]*?)"
    r"(else if \(\s*\n?\s*!appIcon\.isDragged &&\s*\n?\s*\(iconAnimationSettings\.type == 'RIPPLE')",
)
_hover_in_replacement = (
    r"\1\n"
    r"          appIcon.get_parent().raise(1)\n"
    r"        \3"
)
text = _hover_in_pat.sub(_hover_in_replacement, text, count=1)

# 2. Restore hover-out SIMPLE branch to call raise(0).
_hover_out_pat = _re.compile(
    r"(this\._timeoutsHandler\.remove\(T1\)[ \t]*\n[ \t]*\n[ \t]*)"
    r"if \(!appIcon\.isDragged && iconAnimationSettings\.type == 'SIMPLE'\)"
    r"[\s\S]*?"
    r"(\n      \})",
)
text = _hover_out_pat.sub(
    r"\1if (!appIcon.isDragged && iconAnimationSettings.type == 'SIMPLE')\n"
    r"          appIcon.get_parent().raise(0)\2",
    text, count=1,
)

# 3. Replace the entire raise() method with a clone-free, vertical-only
#    implementation.  The original creates a raised clone whose X position
#    drifts on horizontal panels; this version animates the real container
#    on the Y axis only, which eliminates the drift entirely.
_raise_pat = _re.compile(
    r"    raise\(level\) \{\n[\s\S]*?(?=\n    stretch\(translation\) \{)",
)
_new_raise = """\
    raise(level) {
      // GNOME_PRISM: Lift only the icon image inside its bordered cell.
      // The _dtpIconContainer (border) stays put; only _iconBin moves.
      if (this._raisedClone) {
        this._raisedClone.source.opacity = 255
        Utils.stopAnimations(this._raisedClone)
        this._raisedClone.destroy()
        delete this._raisedClone
      }

      const appIcon = this.child
      const iconBin = appIcon?.icon?._iconBin
      if (!iconBin) return

      // _fpBaselineY is the resting translation_y set by _setAppIconPadding.
      const baseline = iconBin._fpBaselineY !== undefined ? iconBin._fpBaselineY : 0

      Utils.stopAnimations(iconBin)
      if (!this._dtpPanel.geom.vertical && level > 0) {
        Utils.animate(iconBin, {
          translation_y: baseline - 5,
          translation_x: 0,
          time: 0.12,
          transition: 'easeOutQuad',
        })
      } else {
        Utils.animate(iconBin, {
          translation_y: baseline,
          translation_x: 0,
          time: 0.12,
          transition: 'easeOutQuad',
        })
      }
    }
"""
text = _raise_pat.sub(_new_raise, text, count=1)

# 4. Click-background handler is now in appIcons.js _setAppIconPadding.

path.write_text(text, encoding="utf-8")
PY

  [[ -f "${appicons_js_path}" ]] || return 0
  python3 - <<'PY' "${appicons_js_path}"
import sys
import subprocess
import re
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# Detect ESM (GNOME 45+) vs legacy imports to pick the right Meta.Cursor path.
_is_esm = "from 'gi://" in text

if _is_esm:
    # ESM: ensure `import Meta from 'gi://Meta'` is present.
    _meta_import = "import Meta from 'gi://Meta'"
    if _meta_import not in text:
        lines = text.split('\n')
        last_gi = -1
        for i, ln in enumerate(lines):
            if "from 'gi://" in ln:
                last_gi = i
        if last_gi >= 0:
            lines.insert(last_gi + 1, _meta_import)
            text = '\n'.join(lines)
    _meta_cursor = "Meta.Cursor"
else:
    _meta_cursor = "imports.gi.Meta.Cursor"

def _detect_primary_height():
    try:
        out = subprocess.check_output(["xrandr"], text=True)
    except Exception:
        return None

    m = re.search(r" primary (\d+)x(\d+)\+", out)
    if m:
        return int(m.group(2))

    m = re.search(r" connected [^(]*?(\d+)x(\d+)\+", out)
    if m:
        return int(m.group(2))

    return None

height = _detect_primary_height()
if height is not None:
    # Tune per-resolution; smaller/shorter displays get a slightly
    # stronger upward nudge so icons appear optically centered.
    # Zach's 13\" laptop panel is 2880x1920; give it a stronger lift.
    if height <= 900:
        icon_offset = -5
    elif height <= 1200:
        icon_offset = -4
    elif 1900 <= height <= 2000:
        icon_offset = -6
    else:
        icon_offset = -3
else:
    # Fallback that matches the original development machine feel.
    icon_offset = -3

start = "    _setAppIconPadding() {\n"
end = "    _setAppIconStyle() {\n"
TEMPLATE = """    _setAppIconPadding() {
      const padding = getIconPadding(this.dtpPanel)
      const margin = SETTINGS.get_int('appicon-margin')
      let vertical = this.dtpPanel.geom.vertical

      if (this.icon && this.icon._iconBin) {
        this.icon._iconBin.y_align = Clutter.ActorAlign.CENTER
        this.icon._iconBin.x_align = Clutter.ActorAlign.CENTER
        this.icon._iconBin.translation_y = ICON_VERTICAL_OFFSET_VALUE
        this.icon._iconBin._fpBaselineY = ICON_VERTICAL_OFFSET_VALUE
        if (this.icon._iconBin.child) {
          this.icon._iconBin.child.y_align = Clutter.ActorAlign.CENTER
          this.icon._iconBin.child.x_align = Clutter.ActorAlign.CENTER
          this.icon._iconBin.child.translation_y = ICON_VERTICAL_OFFSET_VALUE
        }
      }
      this._iconContainer.y_align = Clutter.ActorAlign.CENTER
      this._iconContainer.x_align = Clutter.ActorAlign.CENTER
      this._iconContainer.translation_y = ICON_VERTICAL_OFFSET_VALUE
      this._dtpIconContainer.y_align = Clutter.ActorAlign.CENTER
      this._dtpIconContainer.x_align = Clutter.ActorAlign.CENTER
      this._dtpIconContainer.translation_y = ICON_VERTICAL_OFFSET_VALUE
      this._dotsContainer.y_align = Clutter.ActorAlign.CENTER
      this._dotsContainer.x_align = Clutter.ActorAlign.CENTER
      this._dtpIconContainer.set_style(getIconContainerStyle(vertical))

      this.set_style(
        `padding: ${vertical ? margin : 0}px ${vertical ? 0 : margin}px;`,
      )
      this._iconContainer.set_style(
        vertical
          ? `padding: ${padding}px;`
          : `padding: ${padding}px;`,
      )

      // GNOME_PRISM: click-background feedback via St pseudo-class.
      // Inline style manipulation gets overwritten by set_style() calls
      // elsewhere, so we toggle the :active pseudo-class instead and
      // let the CSS rule handle the visual feedback.
      if (!this._fpClickConnected) {
        this._fpClickConnected = true
        const ctr = this._container
        this.connect('button-press-event', () => {
          ctr.add_style_pseudo_class('active')
          return false
        })
        this.connect('button-release-event', () => {
          ctr.remove_style_pseudo_class('active')
          return false
        })
        this.connect('leave-event', () => {
          ctr.remove_style_pseudo_class('active')
          try {
            if (typeof META_CURSOR_EXPR !== 'undefined' &&
                META_CURSOR_EXPR.DEFAULT !== undefined)
              global.display.set_cursor(META_CURSOR_EXPR.DEFAULT)
          } catch (_e) { /* cursor API unavailable */ }
          return false
        })
        this.connect('enter-event', () => {
          try {
            if (typeof META_CURSOR_EXPR !== 'undefined' &&
                META_CURSOR_EXPR.POINTING_HAND !== undefined)
              global.display.set_cursor(META_CURSOR_EXPR.POINTING_HAND)
          } catch (_e) { /* cursor API unavailable */ }
          return false
        })
      }
    }

"""
replacement = TEMPLATE.replace("ICON_VERTICAL_OFFSET_VALUE", str(icon_offset)).replace("META_CURSOR_EXPR", _meta_cursor)
if start in text and end in text:
    pre = text.split(start, 1)[0]
    rest = text.split(start, 1)[1]
    post = rest.split(end, 1)[1]
    text = pre + replacement + end + post

# Safety cleanup: ensure Show Apps padding function has no injected border/shadow.
start2 = "  setShowAppsPadding() {"
end2 = "  createMenu() {"
replacement2 = """  setShowAppsPadding() {
    let padding = getIconPadding(this.realShowAppsIcon._dtpPanel)
    let sidePadding = SETTINGS.get_int('show-apps-icon-side-padding')
    let isVertical = this.realShowAppsIcon._dtpPanel.geom.vertical

    this.actor.set_style(
      'padding:' +
        (padding + (isVertical ? sidePadding : 0)) +
        'px ' +
        (padding + (isVertical ? 0 : sidePadding)) +
        'px;',
    )
  }

"""

if start2 in text and end2 in text:
    pre2 = text.split(start2, 1)[0]
    rest2 = text.split(start2, 1)[1]
    post2 = rest2.split(end2, 1)[1]
    text = pre2 + replacement2 + end2 + post2

path.write_text(text, encoding="utf-8")
PY
}

# Position/layout
set_dtp_setting "panel-position" "'BOTTOM'"
set_dtp_setting "panel-positions" "'{\"0\":\"BOTTOM\"}'"
set_dtp_setting "stockgs-keep-top-panel" "false"
set_dtp_setting "panel-element-positions-monitors-sync" "true"
set_dtp_panel_elements_layout
set_dtp_panel_geometry

# Match reference panel density and icon sizing more closely
set_dtp_setting "panel-size" "55"
set_dtp_setting "appicon-padding" "10"
set_dtp_setting "appicon-margin" "0"
set_dtp_setting "tray-padding" "0"
set_dtp_setting "leftbox-padding" "0"
set_dtp_setting "status-icon-padding" "0"
set_dtp_setting "panel-top-bottom-padding" "0"
set_dtp_setting "panel-side-padding" "0"
# Show Apps width is computed separately in Dash-to-Panel; bump side padding
# so tile width matches neighboring app tiles.
set_dtp_setting "show-apps-icon-side-padding" "12"
set_dtp_show_apps_icon
set_dtp_setting "tray-size" "14"
set_dtp_setting "leftbox-size" "14"

# Keep a crisp outlined panel style
set_dtp_setting "trans-use-custom-bg" "true"
set_dtp_setting "trans-bg-color" "'#000000'"
set_dtp_setting "trans-use-border" "true"
set_dtp_setting "trans-border-width" "1"
set_dtp_setting "trans-border-use-custom-color" "true"
set_dtp_setting "trans-border-custom-color" "'#BDA7F0'"

# More square/compact indicator behavior
set_dtp_setting "dot-style-focused" "'SQUARES'"
set_dtp_setting "dot-style-unfocused" "'SQUARES'"
set_dtp_setting "dot-position" "'BOTTOM'"
set_dtp_setting "dot-size" "0"
set_dtp_setting "focus-highlight" "false"
set_dtp_setting "group-apps-underline-unfocused" "false"
# Keep micro-interactions subtle but present.
# Keep this enabled so the SIMPLE branch is active, but neutralize built-in
# travel/zoom and let our direct JS translation drive visible movement.
set_dtp_setting "animate-appicon-hover" "true"
set_dtp_setting "highlight-appicon-hover" "false"
set_dtp_setting "animate-appicon-hover-animation-type" "'SIMPLE'"
set_dtp_setting "animate-appicon-hover-animation-duration" "{'SIMPLE':0.0,'RIPPLE':0.0,'PLANK':0.0}"
set_dtp_setting "animate-app-switch" "false"
set_dtp_setting "animate-window-launch" "false"
set_dtp_setting "show-window-previews" "false"
set_dtp_setting "show-tooltip" "false"
set_dtp_setting "animate-appicon-hover-animation-travel" "{'SIMPLE':0.0,'RIPPLE':0.0,'PLANK':0.0}"
set_dtp_setting "animate-appicon-hover-animation-zoom" "{'SIMPLE':1.0,'RIPPLE':1.0,'PLANK':1.0}"
set_dtp_setting "animate-appicon-hover-animation-rotation" "{'SIMPLE':0,'RIPPLE':0,'PLANK':0}"
set_dtp_setting "global-border-radius" "0"

# Clock defaults: date visible, no weekday.
set_interface_setting "clock-show-date" "true"
set_interface_setting "clock-show-weekday" "false"
set_interface_setting "clock-show-seconds" "false"

# Fallback for systems still using Ubuntu Dock.
if gsettings list-schemas | awk '$0=="org.gnome.shell.extensions.dash-to-dock"{found=1} END {exit !found}'; then
  gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM' || true
fi

apply_dtp_stylesheet_overrides
apply_dtp_code_overrides

# Reload extension to apply placement/styling keys immediately.
gnome-extensions disable "${DTP_UUID}" >/dev/null 2>&1 || true
gnome-extensions enable "${DTP_UUID}" >/dev/null 2>&1 || true

echo
echo "============================================================"
echo "Dash to Panel setup complete."
echo "If the panel does not move to the bottom immediately,"
echo "FULLY LOG OUT OF YOUR SESSION AND LOG BACK IN."
echo "============================================================"
