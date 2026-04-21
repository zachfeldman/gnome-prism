#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

PREFIX="${HOME}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./scripts/apply_vivaldi_theme.sh [--prefix <path>] [--dry-run] [--help]

Install gnome-prism Vivaldi custom UI CSS mod files.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || { echo "Missing value for --prefix" >&2; exit 1; }
      PREFIX="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

SOURCE_DIR="${REPO_ROOT}/apps/vivaldi/mods"
DEST_ROOT="${PREFIX}/.local/share/gnome-prism/vivaldi"
DEST_DIR="${DEST_ROOT}/mods"

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "Vivaldi mods source directory not found: ${SOURCE_DIR}" >&2
  exit 1
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "Would install Vivaldi mods to ${DEST_DIR}"
  exit 0
fi

mkdir -p "${DEST_ROOT}"
rm -rf "${DEST_DIR}"
cp -a "${SOURCE_DIR}" "${DEST_DIR}"

echo "Installed Vivaldi mods to ${DEST_DIR}"

if [[ "${PREFIX}" == "${HOME}" ]]; then
  cat <<EOF
Enable in Vivaldi:
  1) Open vivaldi://flags and turn on "Allow CSS modifications"
  2) Open vivaldi://settings/appearance
  3) Set Custom UI Modifications folder to:
     ${DEST_DIR}
  4) Restart Vivaldi
EOF
fi
