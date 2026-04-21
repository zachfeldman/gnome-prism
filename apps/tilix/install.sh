#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
THEME_JSON="${SCRIPT_DIR}/gnome-prism.json"
TILIX_SCHEMES_DIR="/usr/share/tilix/schemes"

if [[ ! -f "${THEME_JSON}" ]]; then
  echo "Error: theme file not found: ${THEME_JSON}" >&2
  exit 1
fi

if [[ ! -d "${TILIX_SCHEMES_DIR}" ]]; then
  echo "Tilix does not appear to be installed (${TILIX_SCHEMES_DIR} not found); skipping." >&2
  exit 0
fi

echo "Installing Tilix color scheme to ${TILIX_SCHEMES_DIR} (requires sudo)."
sudo cp "${THEME_JSON}" "${TILIX_SCHEMES_DIR}/gnome-prism.json"
echo "Installed. Select 'gnome-prism' in Tilix Preferences → Profiles → Color → Color scheme."
