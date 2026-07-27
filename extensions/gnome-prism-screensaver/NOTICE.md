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
  upstream's normal animated lock screen if the relevant private API isn't
  found on the running GNOME Shell version.
- New "keep display awake while screensaver is visible" preference, backed
  by a `org.gnome.SessionManager` idle inhibitor.
- Preferences, notification titles, and log prefixes renamed/reskinned for
  GNOME Prism; a few new preference rows were added (see `ui/screensaver_page.js`).

Everything else — the per-monitor GStreamer/GTK4 video pipeline, the actor
reparenting into the lock screen's background group, suspend/resume
handling, and the prompt-triggered blur/grayscale/pause behavior — is
unchanged from upstream.
