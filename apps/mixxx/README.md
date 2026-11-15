# Mixxx

A gnome-prism skin for Mixxx, generated from the stock **LateNight** skin
(CC BY-SA 3.0) rather than vendored, so it tracks the installed Mixxx version.

```sh
apps/mixxx/install.sh   # quit Mixxx first
```

This builds the skin into `~/.mixxx/skins/gnome-prism` and selects it (skin
`gnome-prism`, scheme `Prism`) in `~/.mixxx/mixxx.cfg`, backing the config up to
`mixxx.cfg.gnome-prism.bak`. Re-run it after a Mixxx upgrade.

What changes versus LateNight / PaleMoon:

- black backgrounds, lavender (`#BDA7F0`) text, icons, knob arcs, pointers and
  fader handles; other state colors snapped to the gnome-prism palette;
- flat, square buttons with a 1px lavender border; Noto Sans Mono;
  lavender selection with black text (`prism.qss`);
- touch-friendly deck/mixer/FX area: every widget size scaled 1.25x (buttons,
  knobs, faders, knob arcs) and skin text 1.2x; toolbar and library unchanged
  (`SIZE_SCALE` / `FONT_SCALE` in `build_skin.py`);
- main/headphone controls (gain, balance, head gain/mix, split) moved into the
  top toolbar (`main_head_toolbar.xml`) and the side column hidden, giving the
  decks and mixer that width;
- less clutter: 4 hotcues instead of 8; spinny/cover, intro/outro cues and
  beatgrid controls off; the mic/aux row hidden at every launch. All can be
  re-enabled from the skin settings menu / toolbar.

The library track table font comes from Mixxx's own preferences
(Preferences → Library → Library font), not the skin.
