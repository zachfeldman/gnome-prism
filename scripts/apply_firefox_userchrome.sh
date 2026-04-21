#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

PREFIX="${HOME}"
PROFILE_NAME=""
PROFILE_PATH=""
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./scripts/apply_firefox_userchrome.sh [options]

Copy gnome-prism userChrome.css into a Firefox profile and enable
toolkit.legacyUserProfileCustomizations.stylesheets via user.js.

Options:
  --prefix <path>        Home prefix to target (default: $HOME)
  --profile-name <name>  Firefox profile name from profiles.ini
  --profile-path <path>  Absolute profile path (overrides profile-name/default)
  --dry-run              Print planned actions only
  --help                 Show this message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || { echo "Missing value for --prefix" >&2; exit 1; }
      PREFIX="$2"
      shift 2
      ;;
    --profile-name)
      [[ $# -ge 2 ]] || { echo "Missing value for --profile-name" >&2; exit 1; }
      PROFILE_NAME="$2"
      shift 2
      ;;
    --profile-path)
      [[ $# -ge 2 ]] || { echo "Missing value for --profile-path" >&2; exit 1; }
      PROFILE_PATH="$2"
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

SOURCE_CHROME_CSS="${REPO_ROOT}/apps/firefox/userchrome/userChrome.css"
SOURCE_CONTENT_CSS="${REPO_ROOT}/apps/firefox/userchrome/userContent.css"
FIREFOX_DIR="${PREFIX}/.mozilla/firefox"
SNAP_FIREFOX_COMMON_DIR="${PREFIX}/snap/firefox/common/.mozilla/firefox"
SNAP_FIREFOX_CURRENT_DIR="${PREFIX}/snap/firefox/current/.mozilla/firefox"
PROFILES_INI=""

if [[ ! -f "${SOURCE_CHROME_CSS}" ]]; then
  echo "Source userChrome.css not found: ${SOURCE_CHROME_CSS}" >&2
  exit 1
fi

if [[ ! -f "${SOURCE_CONTENT_CSS}" ]]; then
  echo "Source userContent.css not found: ${SOURCE_CONTENT_CSS}" >&2
  exit 1
fi

if [[ -z "${PROFILE_PATH}" ]]; then
  for candidate in \
    "${FIREFOX_DIR}" \
    "${SNAP_FIREFOX_COMMON_DIR}" \
    "${SNAP_FIREFOX_CURRENT_DIR}"; do
    if [[ -f "${candidate}/profiles.ini" ]]; then
      FIREFOX_DIR="${candidate}"
      PROFILES_INI="${candidate}/profiles.ini"
      break
    fi
  done

  if [[ -z "${PROFILES_INI}" ]]; then
    echo "Firefox profiles.ini not found in any supported path:" >&2
    echo "  ${FIREFOX_DIR}/profiles.ini" >&2
    echo "  ${SNAP_FIREFOX_COMMON_DIR}/profiles.ini" >&2
    echo "  ${SNAP_FIREFOX_CURRENT_DIR}/profiles.ini" >&2
    echo "Open Firefox once to create a profile, then rerun this script." >&2
    exit 1
  fi

  PROFILE_PATH="$(python3 - <<'PY' "${PROFILES_INI}" "${FIREFOX_DIR}" "${PROFILE_NAME}"
import configparser
import pathlib
import sys

profiles_ini = pathlib.Path(sys.argv[1])
firefox_dir = pathlib.Path(sys.argv[2])
requested_name = sys.argv[3].strip()

cp = configparser.RawConfigParser()
cp.read(profiles_ini, encoding="utf-8")

candidates = []
for section in cp.sections():
    if not section.startswith("Profile"):
        continue
    name = cp.get(section, "Name", fallback="")
    path = cp.get(section, "Path", fallback="")
    is_relative = cp.getint(section, "IsRelative", fallback=1)
    default = cp.getint(section, "Default", fallback=0)
    if not path:
        continue
    resolved = (firefox_dir / path) if is_relative == 1 else pathlib.Path(path)
    candidates.append({
        "name": name,
        "default": default,
        "path": resolved,
    })

if not candidates:
    raise SystemExit("No Firefox profiles found in profiles.ini")

if requested_name:
    for item in candidates:
        if item["name"] == requested_name:
            print(str(item["path"]))
            raise SystemExit(0)
    raise SystemExit(f"Requested profile name not found: {requested_name}")

defaults = [item for item in candidates if item["default"] == 1]
chosen = defaults[0] if defaults else candidates[0]
print(str(chosen["path"]))
PY
)"
fi

if [[ ! -d "${PROFILE_PATH}" ]]; then
  echo "Firefox profile path not found: ${PROFILE_PATH}" >&2
  exit 1
fi

CHROME_DIR="${PROFILE_PATH}/chrome"
DEST_CHROME_CSS="${CHROME_DIR}/userChrome.css"
DEST_CONTENT_CSS="${CHROME_DIR}/userContent.css"
USER_JS="${PROFILE_PATH}/user.js"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "Would copy:"
  echo "  ${SOURCE_CHROME_CSS}"
  echo "to:"
  echo "  ${DEST_CHROME_CSS}"
  echo "Would copy:"
  echo "  ${SOURCE_CONTENT_CSS}"
  echo "to:"
  echo "  ${DEST_CONTENT_CSS}"
  echo "Would ensure in ${USER_JS}:"
  echo "  user_pref(\"toolkit.legacyUserProfileCustomizations.stylesheets\", true);"
  exit 0
fi

mkdir -p "${CHROME_DIR}"
cp -f "${SOURCE_CHROME_CSS}" "${DEST_CHROME_CSS}"
cp -f "${SOURCE_CONTENT_CSS}" "${DEST_CONTENT_CSS}"

python3 - <<'PY' "${USER_JS}"
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
pref_line = 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
text = path.read_text(encoding="utf-8") if path.exists() else ""

pattern = r'^user_pref\("toolkit\.legacyUserProfileCustomizations\.stylesheets",\s*(true|false)\s*\);\s*$'
if re.search(pattern, text, flags=re.M):
    text = re.sub(pattern, pref_line, text, flags=re.M)
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += pref_line + "\n"

path.write_text(text, encoding="utf-8")
PY

echo "Installed Firefox userChrome.css to ${DEST_CHROME_CSS}"
echo "Installed Firefox userContent.css to ${DEST_CONTENT_CSS}"
echo "Enabled toolkit.legacyUserProfileCustomizations.stylesheets in ${USER_JS}"
echo "Restart Firefox to apply changes."
