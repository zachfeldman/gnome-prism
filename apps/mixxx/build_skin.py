#!/usr/bin/env python3
"""Build the gnome-prism Mixxx skin from the stock LateNight skin.

LateNight is CC BY-SA 3.0 and about 5 MB of assets, so instead of vendoring a
fork we copy the installed skin and restyle it onto the gnome-prism look:

- colors: dark greys collapse to black, light greys shift onto the lavender
  stroke color (#BDA7F0), saturated colors snap to the matching palette hue
  (orange highlight, green, yellow, blue, cyan, lavender) at their original
  lightness so state colors keep their meaning;
- flat, square buttons framed by a 1px lavender border, Noto Sans Mono text,
  lavender selection with black text (prism.qss);
- layout: 32px buttons instead of 26px, spinny/cover, intro/outro cues and
  beatgrid controls hidden by default for a shorter deck, and the mic/aux row
  hidden on every launch (the toolbar still toggles it).

Only the PaleMoon scheme is kept (renamed "Prism"); Classic is dropped.

Usage: build_skin.py [--src DIR] [--dest DIR]
"""

import argparse
import colorsys
import re
import shutil
import subprocess
from pathlib import Path

SKIN_NAME = "gnome-prism"
HERE = Path(__file__).resolve().parent

LAVENDER = (0xBD, 0xA7, 0xF0)
# Saturated hue families -> gnome-prism palette color. Hue ranges are 0..1.
FAMILIES = [
    (0.11, (0xFF, 0x74, 0x47)),  # red / orange -> fp_highlight
    (0.19, (0xFF, 0xCC, 0x66)),  # yellow
    (0.45, (0x7E, 0xC9, 0xA0)),  # green
    (0.55, (0x89, 0xDD, 0xFF)),  # cyan / teal
    (0.70, (0xA8, 0xC4, 0xFF)),  # blue
    (0.94, LAVENDER),            # purple / magenta
    (1.01, (0xFF, 0x74, 0x47)),  # wraps back to red
]

# Scheme variables set explicitly rather than by the generic remap.
SCHEME_OVERRIDES = {
    "SignalColor_12": "#BDA7F0",
    "SignalColor_34": "#89DDFF",
    "BgColorWaveform_12": "#000000",
    "BgColorOverview_12": "#000000",
    # Mixxx only accepts named colors for these three.
    "SignalHighColor": "lightsteelblue",
    "SignalMidColor": "mediumpurple",
    "SignalLowColor": "tomato",
    "PlayPosColor": "#BDA7F0",
    "CueColor": "#FF7447",
    "ArcColorEq": "#BDA7F0",
    "ArcColorGain": "#BDA7F0",
    "ArcColorGainLow": "#6f6290",
    "ArcColorMstBal": "#BDA7F0",
    "ArcColorFx12Quick": "#BDA7F0",
    "ArcColorFx34": "#BDA7F0",
    "ArcColorFxMix": "#BDA7F0",
    "ArcColorFxParameter": "#8a7bb0",
}

# Skin defaults (skin.xml manifest attributes).
ATTRIBUTE_OVERRIDES = {
    "[Skin],show_spinnies": "0",
    "[Skin],show_coverart": "0",
    "[Skin],show_intro_outro_cues": "0",
    "[Skin],show_beatgrid_controls": "0",
    "[Skin],show_8_hotcues": "0",
    # Main/headphone column moves into the toolbar (main_head_toolbar.xml).
    "[Skin],show_main_head_mixer": "0",
}

TOOLBAR_SPACER = "<WidgetGroup><Size>me,min</Size></WidgetGroup>"

# Button size bump, applied to size tags in these folders.
# Touch-friendly scale for the deck/mixer area: every widget size in these
# folders (widths and heights, so containers grow with their contents), the
# knob arc radii, and skin font sizes. Toolbar and library keep stock sizes.
SIZE_DIRS = ("decks", "mixer", "controls", "fx", "samplers", "mic_aux")
SIZE_SCALE = 1.25
FONT_SCALE = 1.2

MONO = '"Noto Sans Mono", "DM Mono", monospace'


def hls(rgb):
    return colorsys.rgb_to_hls(*(c / 255 for c in rgb))


def remap(r, g, b, accent=None):
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    if accent and s >= 0.18 and 0.06 <= l <= 0.97:
        return accent
    if s < 0.18 or l < 0.06 or l > 0.97:
        if l <= 0.45:
            # Backgrounds and surfaces: near-black, like fp_bg / fp_surface.
            out = colorsys.hls_to_rgb(0, max(0.0, l - 0.08) * 0.7, 0)
        else:
            # Text, borders, icons: grey -> lavender ramp.
            t = (l - 0.45) / 0.55
            lh, _, ls = hls(LAVENDER)
            out = colorsys.hls_to_rgb(lh, min(l, 0.9), ls * (0.35 + 0.65 * t))
    else:
        target = next(c for limit, c in FAMILIES if h < limit)
        th, _, ts = hls(target)
        out = colorsys.hls_to_rgb(th, l, ts * min(1.0, s / 0.4))
    return tuple(round(c * 255) for c in out)


def hex_sub(m, accent=None):
    v = m.group(1)
    if len(v) == 3:
        v = "".join(c * 2 for c in v)
    r, g, b = remap(*(int(v[i:i + 2], 16) for i in (0, 2, 4)), accent=accent)
    return f"#{r:02x}{g:02x}{b:02x}"


def rgba_sub(m):
    r, g, b = remap(*(int(x) for x in m.group(2, 3, 4)))
    return f"{m.group(1)}({r}, {g}, {b}{m.group(5)})"


HEX_RE = re.compile(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})(?![0-9a-zA-Z])")
RGBA_RE = re.compile(r"(rgba?)\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*((?:,[^)]*)?)\)")
SIZE_RE = re.compile(r'(<(?:Size|MinimumSize|MaximumSize|SetVariable name="Size")>)([^<]*)(<)')


def recolor_text(text, accent=None):
    return RGBA_RE.sub(rgba_sub, HEX_RE.sub(lambda m: hex_sub(m, accent), text))


def restyle_qss(text):
    text = re.sub(r"font-family:[^;]*;", f"font-family: {MONO};", text)
    # gnome-prism is square-cornered.
    return re.sub(r"border-radius:\s*[0-4](?:\.\d+)?px", "border-radius: 0px", text)


def scale_number(m, factor):
    return f"{round(float(m.group(0)) * factor):d}"


def scale_sizes(text):
    def fix(m):
        value = re.sub(r"(?<![\w.])\d+(?:\.\d+)?", lambda n: scale_number(n, SIZE_SCALE), m.group(2))
        return m.group(1) + value + m.group(3)
    return SIZE_RE.sub(fix, text)


def scale_fonts(text):
    return re.sub(r"(font-size:\s*)(\d+(?:\.\d+)?)px",
                  lambda m: f"{m.group(1)}{round(float(m.group(2)) * FONT_SCALE)}px", text)


def flat_frame(path):
    """Replace a domed button frame SVG with a flat 1px lavender border."""
    m = re.search(r'<svg[^>]*\bwidth="([\d.]+)"[^>]*\bheight="([\d.]+)"', path.read_text())
    if not m or float(m.group(1)) <= 1:
        return  # 1x1 transparent placeholder, keep as is
    w, h = m.groups()
    name = path.stem
    # Mixxx paints this frame over the button's icon/text, so the middle must
    # stay transparent; the button background itself comes from the QSS.
    if "active" in name or "pressed" in name or name.endswith("_set") or "focus" in name:
        stroke = "#BDA7F0"
    elif "disabled" in name:
        stroke = "#3a3450"
    else:
        stroke = "#6f6290"
    path.write_text(
        f'<svg width="{w}" height="{h}" version="1.1" xmlns="http://www.w3.org/2000/svg">\n'
        f'  <rect x="0.5" y="0.5" width="{float(w) - 1:g}" height="{float(h) - 1:g}" '
        f'fill="none" stroke="{stroke}" stroke-width="1"/>\n</svg>\n')


def recolor_png(path):
    # VU meter / latency bitmaps: tint via ImageMagick if present (clipping
    # segments orange, the rest lavender). Without it they keep stock colors.
    magick = shutil.which("magick")
    if not magick:
        return
    tint = "#FF7447" if "clipping" in path.name else "#BDA7F0"
    subprocess.run([magick, str(path), "-colorspace", "gray", "-colorspace", "sRGB",
                    "-fill", tint, "-tint", "100", str(path)], check=False)


def build_skin_xml(text):
    # Drop the Classic scheme; rename PaleMoon -> Prism.
    text = re.sub(r"\s*<Scheme>\s*<Name>Classic</Name>.*?</Scheme><!-- Classic -->", "", text, flags=re.S)
    text = text.replace("<Name>PaleMoon</Name>", "<Name>Prism</Name>")
    text = re.sub(r"<title>.*?</title>", f"<title>{SKIN_NAME}</title>", text, count=1)
    text = re.sub(r"<description>(.*?)</description>",
                  r"<description>LateNight restyled for gnome-prism. \1</description>", text, count=1)
    text = recolor_text(text)
    for name, value in SCHEME_OVERRIDES.items():
        text = re.sub(rf'(<SetVariable name="{name}">)[^<]*(</SetVariable>)', rf"\g<1>{value}\g<2>", text)
    for key, value in ATTRIBUTE_OVERRIDES.items():
        text = re.sub(rf'(config_key="{re.escape(key)}">)[^<]*(<)', rf"\g<1>{value}\g<2>", text)
    text = re.sub(r'(<SetVariable name="ArcRadius\w+">)([\d.]+)(<)',
                  lambda m: f"{m.group(1)}{float(m.group(2)) * SIZE_SCALE:g}{m.group(3)}", text)
    # Mic/aux: not persisted, so it starts hidden every launch.
    text = text.replace('<attribute persist="true" config_key="[Skin],show_microphones">',
                        '<attribute config_key="[Skin],show_microphones">')
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="/usr/share/mixxx/skins/LateNight")
    ap.add_argument("--dest", default=str(Path.home() / ".mixxx" / "skins" / SKIN_NAME))
    args = ap.parse_args()
    src, dest = Path(args.src), Path(args.dest)

    if not (src / "skin.xml").is_file():
        raise SystemExit(f"LateNight skin not found at {src}")

    shutil.rmtree(dest, ignore_errors=True)
    shutil.copytree(src, dest, ignore=shutil.ignore_patterns("classic", "style_classic.qss",
                                                            "skin_preview_Classic.png"))
    (dest / "skin_preview_PaleMoon.png").rename(dest / "skin_preview_Prism.png")
    shutil.copy(HERE / "main_head_toolbar.xml", dest / "main_head_toolbar.xml")

    for path in dest.rglob("*"):
        rel = path.relative_to(dest)
        if path.suffix in (".xml", ".qss", ".svg"):
            text = path.read_text(encoding="utf-8")
            # "skins:" only searches Mixxx's system skin dir; "skin:" is relative
            # to the loaded skin, so the copy works from ~/.mixxx/skins too.
            text = text.replace("url(skins:LateNight/", "url(skin:/").replace("skins:LateNight/", "skin:")
            if rel == Path("skin.xml"):
                text = build_skin_xml(text)
            elif path.name.startswith(("knob_indicator_", "knob_")) and \
                    path.parent.name in ("knobs", "sliders"):
                # Knob pointers and fader handles: all lavender, whatever
                # their stock accent color.
                text = recolor_text(text, accent=LAVENDER)
            else:
                text = recolor_text(text)
            if path.suffix == ".qss":
                text = restyle_qss(text)
            if path.suffix == ".xml" and rel.parts[0] in SIZE_DIRS:
                text = scale_sizes(text)
            if rel == Path("style.qss"):
                text = scale_fonts(text)
            if rel == Path("mic_aux_rack.xml"):
                text = text.replace('<ConfigKey persist="true">[Skin],show_microphones',
                                    "<ConfigKey>[Skin],show_microphones")
            if rel == Path("toolbar.xml"):
                assert TOOLBAR_SPACER in text, "toolbar.xml layout changed"
                text = text.replace(TOOLBAR_SPACER, TOOLBAR_SPACER +
                                    '\n      <Template src="skin:main_head_toolbar.xml"/>', 1)
            if rel == Path("style_palemoon.qss"):
                text += "\n" + (HERE / "prism.qss").read_text(encoding="utf-8")
            path.write_text(text, encoding="utf-8")
            if path.suffix == ".svg" and path.parent.name == "buttons" and \
                    path.name.startswith(("btn_embedded_", "btn_flat_")):
                flat_frame(path)
        elif path.suffix == ".png" and path.parent.name == "style":
            recolor_png(path)

    print(f"Built Mixxx skin at {dest}")


if __name__ == "__main__":
    main()
