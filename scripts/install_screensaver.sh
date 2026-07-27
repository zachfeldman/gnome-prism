#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

PREFIX="${HOME}"
EXT_UUID="gnome-prism-screensaver@zachfeldman"
EXT_SRC="${REPO_ROOT}/extensions/gnome-prism-screensaver"

usage() {
  cat <<EOF
Usage: $0 [--prefix <path>] [--help]

Installs the optional GNOME Prism screensaver GNOME Shell extension
(${EXT_UUID}), a maintained fork of Live Lock Screen that plays a
user-selected video on GNOME's real lock screen.

Installs into:
  <prefix>/.local/share/gnome-shell/extensions/${EXT_UUID}

This script:
  - detects your distro (Ubuntu/Debian via apt, Fedora via dnf) and installs
    the GStreamer plugins the extension needs, warning (not failing) if a
    package is unavailable for your distro/version;
  - copies the extension and compiles its GSettings schema;
  - enables the extension via gnome-extensions, or queues it to enable on
    next login if GNOME Shell hasn't loaded it yet (Wayland).

You still need to select a video file afterwards via the extension's
preferences (gnome-extensions prefs ${EXT_UUID}).
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

if [[ ! -d "${EXT_SRC}" ]]; then
  echo "Screensaver extension source not found: ${EXT_SRC}" >&2
  exit 1
fi

METADATA_UUID="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['uuid'])" "${EXT_SRC}/metadata.json")"
if [[ "${METADATA_UUID}" != "${EXT_UUID}" ]]; then
  echo "Error: metadata.json uuid (${METADATA_UUID}) does not match expected ${EXT_UUID}" >&2
  exit 1
fi

install_packages_apt() {
  echo "Installing GStreamer packages via apt (requires sudo)..."
  local pkg_cmd="apt-get"
  command -v apt >/dev/null 2>&1 && pkg_cmd="apt"

  sudo "${pkg_cmd}" -y install \
    gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
    || echo "Warning: failed to install one or more core GStreamer plugin packages." >&2

  # gstreamer1.0-gtk4 is only packaged on Ubuntu 24.10+ / newer Debian; it does
  # not exist on Ubuntu 24.04. Try it, but only warn (never fail the install)
  # if it's not available for this release.
  if ! sudo "${pkg_cmd}" -y install gstreamer1.0-gtk4 2>/dev/null; then
    echo "Warning: gstreamer1.0-gtk4 is not available for this Ubuntu/Debian release" >&2
    echo "(known gap on Ubuntu 24.04 and older). The screensaver requires it." >&2
    echo "You may need to build it from source or use a newer release. See README.md." >&2
  fi
}

install_packages_dnf() {
  echo "Installing GStreamer packages via dnf (requires sudo)..."
  sudo dnf install -y \
    gstreamer1-plugins-good gstreamer1-plugins-bad-free \
    gstreamer1-plugins-ugly gstreamer1-plugins-bad-free-extras \
    gstreamer1-plugin-gtk4 \
    || echo "Warning: failed to install one or more GStreamer packages via dnf." >&2
}

# Only install system packages for the active user install, not test/scratch
# prefixes -- mirrors the PREFIX == HOME guard used elsewhere in the installer
# for sudo/system-wide actions.
if [[ "${PREFIX}" != "${HOME}" ]]; then
  echo "Note: --prefix given; skipping system package installation and dependency checks." >&2
elif command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
  install_packages_apt
elif command -v dnf >/dev/null 2>&1; then
  install_packages_dnf
else
  echo "Warning: no supported package manager (apt/dnf) detected." >&2
  echo "Install GStreamer good/bad/ugly plugins and a gtk4paintablesink-providing" >&2
  echo "package for your distribution manually. See README.md for details." >&2
fi

if [[ "${PREFIX}" == "${HOME}" ]] && command -v gst-inspect-1.0 >/dev/null 2>&1; then
  if ! gst-inspect-1.0 gtk4paintablesink >/dev/null 2>&1; then
    echo "Warning: gtk4paintablesink is not available after package installation." >&2
    echo "The screensaver will refuse to activate until this is resolved." >&2
    echo "Run 'gst-inspect-1.0 gtk4paintablesink' to check again after fixing your setup." >&2
  fi
elif [[ "${PREFIX}" == "${HOME}" ]]; then
  echo "Note: gst-inspect-1.0 not found; skipping gtk4paintablesink availability check." >&2
fi

EXT_DEST_DIR="${PREFIX}/.local/share/gnome-shell/extensions"
EXT_DEST="${EXT_DEST_DIR}/${EXT_UUID}"

echo
echo "=== SCREENSAVER EXTENSION FILES ==="
mkdir -p "${EXT_DEST_DIR}"
rm -rf "${EXT_DEST}"
cp -a "${EXT_SRC}" "${EXT_DEST}"
# Never ship a stale compiled schema; always recompile below.
rm -f "${EXT_DEST}/schemas/gschemas.compiled"
echo "Installed screensaver extension to ${EXT_DEST}"

if command -v glib-compile-schemas >/dev/null 2>&1; then
  glib-compile-schemas "${EXT_DEST}/schemas"
  echo "Compiled GSettings schema"
else
  echo "Warning: glib-compile-schemas not found; the extension's preferences will not work" >&2
  echo "until you install it (part of libglib2.0-dev-bin / glib2-devel) and run:" >&2
  echo "  glib-compile-schemas ${EXT_DEST}/schemas" >&2
fi

# Only attempt to enable the extension for the active user install, not test prefixes.
if [[ "${PREFIX}" == "${HOME}" ]] && command -v gnome-extensions >/dev/null 2>&1; then
  if gnome-extensions enable "${EXT_UUID}" 2>/dev/null; then
    echo "Enabled ${EXT_UUID}."
  else
    # On Wayland, GNOME Shell only discovers newly-installed extensions after
    # a login cycle, so enable can fail even though the files are correct.
    # Queue it via dconf/gsettings so it activates on next login, mirroring
    # the fallback used by scripts/setup_bottom_panel.sh.
    current="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")"
    if ! echo "${current}" | grep -q "${EXT_UUID}"; then
      if [[ "${current}" == "@as []" ]]; then
        new_val="['${EXT_UUID}']"
      else
        new_val="$(echo "${current}" | sed "s/]\$/, '${EXT_UUID}']/")"
      fi
      gsettings set org.gnome.shell enabled-extensions "${new_val}" 2>/dev/null || true
    fi
    echo "${EXT_UUID} is installed but GNOME Shell has not loaded it yet."
    echo "It will activate on next login."
  fi
fi

cat <<EOF

============================================================

Screensaver extension installed.

NEXT STEPS:
  1. Log out and back in (required on Wayland for the extension to load).
  2. Select a video: gnome-extensions prefs ${EXT_UUID}
  3. Start it any time via Quick Settings ("Screensaver") or the default
     keyboard shortcut (Super+Shift+L), both configurable in preferences.

To uninstall: ./scripts/uninstall.sh (removes only this extension's files;
your selected video file is never touched).
EOF
