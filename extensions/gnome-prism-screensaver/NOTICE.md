# Notice

`gnome-prism-screensaver` is a fork of
[Live Lock Screen](https://github.com/nick-redwill/LiveLockScreen) by
nick-redwill, licensed under the **GNU Affero General Public License v3.0**
(see `LICENSE.txt` in this directory). This directory remains AGPL-3.0
licensed, independent of the MIT license used elsewhere in the GNOME Prism
repository.

Upstream project: https://github.com/nick-redwill/LiveLockScreen

## What changed vs. upstream

- New extension UUID (`gnome-prism-screensaver@zachfeldman`) and GSettings
  schema id (`org.gnome.shell.extensions.gnome-prism-screensaver`) so this
  fork installs independently of the upstream extension.
- `session-modes` now includes `"user"` in addition to `"unlock-dialog"`, so
  the extension can register a Quick Settings action and keyboard shortcut in
  the normal session (upstream only ever runs while the screen is locked).
- New "Start Screensaver" Quick Settings toggle and configurable keyboard
  shortcut (default `<Super><Shift>l`), both of which only ever call GNOME's
  own `Main.screenShield.lock()` — they never bypass or reimplement
  authentication.
- New "clean screensaver mode": hides (never destroys) the lock screen's
  clock/date/notifications chrome while idle, restoring it as soon as the
  user interacts, using the same `_showClock` / `_showPrompt` hook points
  upstream already uses for its blur/grayscale/pause behavior. Falls back to
  normal (non-clean) behavior if the relevant private API isn't found on the
  running GNOME Shell version.
- New folder-rotation mode: instead of a single video file, point at a
  folder and the extension picks a different video from it (sequential or
  random order) each time the screensaver starts.
- New "keep display awake while screensaver is visible" preference, backed
  by an `org.gnome.SessionManager` idle inhibitor, plus suppression of
  GNOME's own lock-transition "curtain" overlay (`ScreenShield._shortLightbox`)
  so the video stays visible through the initial lock rather than briefly
  going black — see "Video rendering" below for why the curtain needed
  suppressing at all.
- **Video rendering was completely re-architected** (see below) — this is
  the single biggest change from upstream.
- Preferences, notification titles, and log prefixes renamed/reskinned for
  GNOME Prism; a few new preference rows were added (see `ui/screensaver_page.js`).
  The Debug page and its three settings (color-accurate pipeline, force
  fullscreen, force GIF support) were removed — they configured internals of
  upstream's player/window mechanism that no longer exist in this fork.

### Video rendering (major departure from upstream)

Upstream spawns a separate `gjs` subprocess that opens an independent GTK4
window, decodes video via GStreamer + `gtk4paintablesink` inside that
window, then reparents the window's compositor actor into the lock dialog's
background group once GNOME Shell detects it mapped.

On current GNOME Shell versions (tested against 50.1), that reparenting
trick breaks Wayland frame-callback delivery to the subprocess: the actor
looks correctly placed and "mapped" in the compositor's scene graph, but the
client stalls on whatever frame it had already committed at the moment of
reparenting (almost always the first, near-blank frame) and never renders
another one — until some unrelated compositor repaint (like the swipe/tap
that reveals the password prompt) incidentally un-sticks it. That produces
exactly the "black lock screen, video appears only once you interact"
failure this fork spent a long debugging session chasing down, and it's not
fixable from extension code — it's a property of stealing a window's actor
out of Mutter's normal window-management tree.

This fork replaces the entire subprocess/window/`gtk4paintablesink`
mechanism with **in-process rendering**: `core/in_process_renderer.js` runs
a GStreamer pipeline directly inside GNOME Shell's own process, pulls
decoded RGBA frames via `appsink.try_pull_preroll()`/`try_pull_sample()` on
a `GLib.timeout_add` poll (deliberately not the `new-sample` signal, which
fires on GStreamer's own streaming thread rather than the main thread and
crashed the compositor in testing), and pushes each frame straight into a
native `St.ImageContent` set as a `Clutter.Actor`'s content — the same kind
of content object GNOME Shell itself uses for screenshots and backgrounds.
There is no second window, no second process, and no Wayland surface to go
stale, so this sidesteps the frame-callback problem entirely rather than
working around it.

Practical consequences of this change:
- **`gtk4paintablesink` is no longer required at all.** The extension only
  needs GStreamer's standard `playbin`/`appsink`/`videoconvert`/`videoscale`
  elements (all in `gstreamer-plugins-base`, essentially always present) plus
  ordinary codec plugins (good/bad/ugly) for whatever video format you use.
  This also removes the Ubuntu-24.04-lacks-`gstreamer1.0-gtk4` dependency gap
  entirely.
- Per-monitor actor placement (including scaling mode: stretch/fit/cover) is
  computed directly from `Main.layoutManager.monitors`, since there's no
  window/connector/PID matching to do anymore.
- Prompt-triggered blur/grayscale/pause effects are applied to this fork's
  own actors instead of a reparented window's wrapper, using the same
  `Shell.BlurEffect`/`Clutter.DesaturateEffect` upstream already used.
- Audio volume uses `playbin`'s own `volume` property directly instead of a
  hand-built audio bin, since there's no longer a separate player process to
  build one in.
