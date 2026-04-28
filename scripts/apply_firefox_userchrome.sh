#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

PREFIX="${HOME}"
PROFILE_PATH=""
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./scripts/apply_firefox_userchrome.sh [options]

Copy gnome-prism userChrome.css into all Firefox profiles and enable
toolkit.legacyUserProfileCustomizations.stylesheets via user.js.

Options:
  --prefix <path>        Home prefix to target (default: $HOME)
  --profile-path <path>  Apply to a single profile path only
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

apply_to_profile() {
  local profile_path="$1"
  local chrome_dir="${profile_path}/chrome"
  local dest_chrome_css="${chrome_dir}/userChrome.css"
  local dest_content_css="${chrome_dir}/userContent.css"
  local user_js="${profile_path}/user.js"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "Would apply to profile: ${profile_path}"
    return 0
  fi

  mkdir -p "${chrome_dir}"
  cp -f "${SOURCE_CHROME_CSS}" "${dest_chrome_css}"
  cp -f "${SOURCE_CONTENT_CSS}" "${dest_content_css}"

  python3 - <<'PY' "${user_js}"
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

  echo "Applied to profile: ${profile_path}"
}

# If explicit profile path provided, just use that
if [[ -n "${PROFILE_PATH}" ]]; then
  if [[ ! -d "${PROFILE_PATH}" ]]; then
    echo "Firefox profile path not found: ${PROFILE_PATH}" >&2
    exit 1
  fi
  apply_to_profile "${PROFILE_PATH}"
  echo "Restart Firefox to apply changes."
  exit 0
fi

# Otherwise, find all profiles and apply to each
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

# Get all profile paths
ALL_PROFILES="$(python3 - <<'PY' "${PROFILES_INI}" "${FIREFOX_DIR}"
import configparser
import pathlib
import sys

profiles_ini = pathlib.Path(sys.argv[1])
firefox_dir = pathlib.Path(sys.argv[2])

cp = configparser.RawConfigParser()
cp.read(profiles_ini, encoding="utf-8")

for section in cp.sections():
    if not section.startswith("Profile"):
        continue
    path = cp.get(section, "Path", fallback="")
    is_relative = cp.getint(section, "IsRelative", fallback=1)
    if not path:
        continue
    resolved = (firefox_dir / path) if is_relative == 1 else pathlib.Path(path)
    if resolved.is_dir():
        print(str(resolved))
PY
)"

if [[ -z "${ALL_PROFILES}" ]]; then
  echo "No Firefox profiles found in profiles.ini" >&2
  exit 1
fi

PROFILE_COUNT=0
while IFS= read -r profile_path; do
  apply_to_profile "${profile_path}"
  PROFILE_COUNT=$((PROFILE_COUNT + 1))
done <<< "${ALL_PROFILES}"

echo "Applied Firefox theme to ${PROFILE_COUNT} profile(s)."
echo "Restart Firefox to apply changes."
