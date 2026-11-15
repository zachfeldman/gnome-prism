#!/usr/bin/env bash
# Build the gnome-prism Mixxx skin into ~/.mixxx/skins and select it.
#
# Mixxx keeps view toggles (spinnies, mic/aux row, ...) in mixxx.cfg, and a
# saved value always wins over a skin's defaults, so the compact layout is
# written to the config here. Mixxx rewrites mixxx.cfg on exit, so this
# refuses to touch it while Mixxx is running.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_DIR="${MIXXX_SETTINGS_DIR:-${HOME}/.mixxx}"
CFG="${SETTINGS_DIR}/mixxx.cfg"

if [[ ! -d /usr/share/mixxx/skins/LateNight ]]; then
  echo "Mixxx (LateNight skin) not found; skipping." >&2
  exit 0
fi

if pgrep -x mixxx >/dev/null; then
  echo "Mixxx is running; quit it first so it doesn't overwrite the config." >&2
  exit 1
fi

python3 "${SCRIPT_DIR}/build_skin.py" --dest "${SETTINGS_DIR}/skins/gnome-prism"

mkdir -p "${SETTINGS_DIR}"
touch "${CFG}"
cp "${CFG}" "${CFG}.gnome-prism.bak"

python3 - "${CFG}" <<'EOF'
import re, sys

path = sys.argv[1]
settings = {
    "Config": {"ResizableSkin": "gnome-prism", "Scheme": "Prism"},
    "Skin": {
        "show_spinnies": "0",
        "show_coverart": "0",
        "show_intro_outro_cues": "0",
        "show_beatgrid_controls": "0",
        "show_8_hotcues": "0",
        "show_main_head_mixer": "0",
        "show_microphones": "0",
    },
}

text = open(path, encoding="utf-8").read()
for group, keys in settings.items():
    header = f"[{group}]"
    if header not in text.splitlines():
        text = text.rstrip("\n") + f"\n\n{header}\n"
    start = text.index(header + "\n") + len(header) + 1
    nxt = re.search(r"^\[", text[start:], re.M)
    end = start + nxt.start() if nxt else len(text)
    body = text[start:end]
    for key, value in keys.items():
        if re.search(rf"^{key} .*$", body, re.M):
            body = re.sub(rf"^{key} .*$", f"{key} {value}", body, flags=re.M)
        else:
            body = f"{key} {value}\n" + body
    text = text[:start] + body + text[end:]
open(path, "w", encoding="utf-8").write(text)
EOF

echo "Selected the gnome-prism skin in ${CFG} (backup: ${CFG}.gnome-prism.bak)."
