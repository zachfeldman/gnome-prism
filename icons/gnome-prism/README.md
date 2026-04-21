# gnome-prism icons

This icon theme inherits from `Adwaita` and ships custom overrides.

## Structure

- `256x256/apps/` raster app icon overrides (PNG)
- `scalable/apps/` app icon overrides
- `scalable/status/` status icon overrides

## Current app overrides

- `org.gnome.Terminal.svg`
- `tilix.svg`
- `com.gexperts.Tilix.svg`
- `org.gnome.Nautilus.svg`
- `firefox.svg`
- `org.mozilla.firefox.svg`
- `firefox_firefox.svg`
- `code.svg`
- `vlc.svg`
- `google-chrome.png` (+ aliases for Chromium/Chrome desktop IDs)
- `sublime_text.png`
- `1password.png`
- `yubico-authenticator.png`
- `cursor.png`
- `google-sheets.png`
- `spotify.png`
- `signal-desktop.png`
- `vivaldi.png`
- `org.gnome.eog.png` (Eye of GNOME / Images)

These PNG icons are extracted from custom source art and normalized to the theme accent color.

## Current status overrides

- `bluetooth-active-symbolic.svg`
- `network-wireless-signal-excellent-symbolic.svg`
- `audio-volume-high-symbolic.svg`
- `video-display-symbolic.svg`
- `battery-level-100-symbolic.svg`

Additional aliases are provided for multiple shell states, including:

- wifi (`none`, `weak`, `ok`, `good`, `excellent`, generic)
- bluetooth (`active`, `disabled`, `acquiring`, generic)
- audio volume (`muted`, `low`, `medium`, `high`, `overamplified`)
- battery levels (`10` through `100`, plus generic)
- brightness/night light symbolic names

## Notes

- Additional icons can be added by placing SVG files into the same `scalable/*` directories using freedesktop icon names.
