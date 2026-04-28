# gnome-prism

<p align="center">
  <img src="docs/screenshots/gnome-prism-tilix-desktop.png" width="96%" alt="Tilix terminal on desktop" />
</p>
<p align="center">
  <img src="docs/screenshots/gnome-prism-framework-desktop.jpg" width="32%" alt="Desktop" />
  <img src="docs/screenshots/gnome-prism-framework-neofetch.jpg" width="32%" alt="Neofetch" />
  <img src="docs/screenshots/gnome-prism-framework-terminal.jpg" width="32%" alt="Terminal" />
</p>

A desktop theme for GNOME with a dark, high-contrast aesthetic. Works on Ubuntu, Fedora, and other GNOME-based distributions.

**Design tokens:**
- Background: `#000000`
- Accent/stroke: `#BDA7F0` (lavender)
- Highlight: `#FF7447` (orange)
- Surface: `#191919`

## Quick Start

### 1. Install prerequisites

<details>
<summary><strong>Ubuntu / Debian</strong></summary>

```bash
sudo apt update
sudo apt install -y git gnome-tweaks gnome-shell-extensions
```
</details>

<details>
<summary><strong>Fedora</strong></summary>

```bash
sudo dnf install -y git gnome-tweaks gnome-extensions-app
```
</details>

### 2. Enable the User Themes extension

The **User Themes** extension allows GNOME Shell to use custom themes. You need to enable it before the shell theme will apply.

**Option A: Via Extensions app (recommended)**
1. Open the **Extensions** app (search for "Extensions" in your app launcher)
2. Find **User Themes** in the list and toggle it **ON**
3. If you don't see it, you may need to log out and back in first

**Option B: Via extensions.gnome.org**
1. Visit [extensions.gnome.org/extension/19/user-themes](https://extensions.gnome.org/extension/19/user-themes/)
2. Click the toggle to install/enable it
3. You may need to install the browser extension first if prompted

**Option C: Via command line**
```bash
gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com
```

> **Note:** The install script will attempt to enable User Themes automatically, but enabling it manually first ensures everything works smoothly.

### 3. Clone and install the theme

```bash
git clone https://github.com/FrameworkComputer/gnome-prism.git
cd gnome-prism
./scripts/install.sh
```

### 4. Log out and back in

This restarts GNOME Shell and applies all theme changes.

- **Wayland (Fedora default):** You must log out and back in
- **X11 (Ubuntu default):** You can also press `Alt+F2`, type `r`, and press Enter

---

## What the install script does

The install script automatically:
- Installs the GTK theme, Shell theme, and icon theme
- Downloads and installs the DM Mono font
- Sets your wallpaper and lock screen background
- Configures Dash to Panel for a bottom taskbar layout
- Applies Firefox and Vivaldi browser theming
- Applies Cursor/VS Code editor settings

You don't need to run any manual `gsettings` commands — the script handles everything.

## Uninstall

```bash
./scripts/uninstall.sh
```

Removes all installed `gnome-prism` files from user paths.

## Re-applying Theme Settings

If a GNOME update resets your settings, re-run the install script. To re-apply manually:

```bash
gsettings set org.gnome.desktop.interface gtk-theme 'gnome-prism'
gsettings set org.gnome.shell.extensions.user-theme name 'gnome-prism'
gsettings set org.gnome.desktop.interface icon-theme 'gnome-prism'
```

## App-Specific Setup

### Firefox

Two levels of Firefox theming are available:

1. **Theme add-on** (`apps/firefox/gnome-prism-theme/`) — install as a temporary extension in Firefox for toolbar/tab colors
2. **userChrome.css** — deeper UI customization:

```bash
./scripts/apply_firefox_userchrome.sh
```

### Vivaldi

```bash
./scripts/apply_vivaldi_theme.sh
```

Installs a CSS mod to `~/.local/share/gnome-prism/vivaldi/` and opens Vivaldi's mod path settings.

### Cursor / VS Code

The install script automatically applies `apps/cursor/gnome-prism-settings.json` to `~/.config/Cursor/User/settings.json`, merging color theme, font, and color customizations while preserving existing settings. The same settings work for VS Code (`~/.config/Code/User/settings.json`).

## Icon Theme

The icon theme ships overrides for 100+ applications as SVG (scalable) and PNG (256×256), including:

- GNOME core apps (Files, Settings, Terminal, Calculator, Calendar, Text Editor, etc.)
- Browsers: Firefox, Chrome, Chromium, Vivaldi
- Dev tools: Cursor, VS Code, Sublime Text, btop, htop
- Media: Spotify, VLC, Rhythmbox, Tenacity
- Productivity: LibreOffice (Writer, Calc, Impress, Draw), Evince, Shotwell
- Comms: Signal, Thunderbird
- Utilities: 1Password, Yubico Authenticator, Steam, Transmission, Remmina
- Framework-specific: Factory Reset Tools, Firmware Updater

Status/tray icon overrides: Wi-Fi, Bluetooth, audio volume, battery levels, brightness, night light, display.

## Troubleshooting

**Shell theme not applying:**
1. Make sure the **User Themes** extension is enabled (see Step 2 above)
2. Log out and back in (required on Wayland)
3. Run `gnome-extensions list` and confirm `user-theme@gnome-shell-extensions.gcampax.github.com` is listed

**Theme not showing in GNOME Tweaks:**
1. Confirm install ran without `sudo`
2. Check `~/.themes/gnome-prism` and `~/.local/share/themes/gnome-prism` exist
3. Fully quit and reopen Tweaks, or log out/in

**libadwaita apps (Files, Settings) not themed:**
GTK4 theming relies on `~/.config/gtk-4.0/gtk.css`. The install script writes this file. Re-run `./scripts/install.sh` if it was removed.

**Icons not updating for some apps:**
Some apps (especially Snaps and Flatpaks) use hardcoded icon paths. The install script creates overrides for common apps, but you may need to log out/in or run `gtk-update-icon-cache ~/.local/share/icons/gnome-prism` to refresh.

**Taskbar icons look misaligned (Fedora):**
Re-run `./scripts/setup_bottom_panel.sh` after logging in. The Dash to Panel extension needs to be fully loaded before the script can apply all settings.

## Contributing

Contributions are welcome! If you have a bug report, feature request, or question, please [file a GitHub issue](https://github.com/FrameworkComputer/framework-prism/issues).

## Development Notes

- All public-facing names use `gnome-prism`
- libadwaita apps may ignore parts of custom GTK theming by design
- Best visual consistency comes from coordinating shell + GTK + icons + wallpaper

## Credits

- **Gaurav Singh** — theme design
- **Ross Jernigan** ([@bonkrat](https://github.com/bonkrat)) — design input and guidance
- **Zach Feldman** ([@zachfeldman](https://github.com/zachfeldman)) — implementation, vibe-coded this into a real Ubuntu theme
