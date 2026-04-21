# Firefox theming

This folder provides two Firefox options:

- `gnome-prism-theme/` - official Firefox theme add-on (stable, distributable)
- `userchrome/` - optional advanced UI overrides (more complete look, less stable)

## 1) Official Firefox theme add-on (recommended)

Path:

- `apps/firefox/gnome-prism-theme/manifest.json`

What it can style well:

- frame and tab colors
- toolbar and URL bar colors
- popup/menus and sidebar colors
- new tab page colors

What it cannot guarantee:

- exact geometry/padding everywhere
- full custom iconography
- exact chrome font replacement in all areas

### Install for testing (temporary)

1. Open `about:debugging#/runtime/this-firefox`
2. Click **Load Temporary Add-on**
3. Select:
   - `apps/firefox/gnome-prism-theme/manifest.json`

### Distribute permanently

Firefox add-ons/themes must be signed for permanent install from file.

## 2) Optional `userChrome.css` (advanced, unsupported by Mozilla)

Paths:

- `apps/firefox/userchrome/userChrome.css` (browser chrome)
- `apps/firefox/userchrome/userContent.css` (built-in pages like new tab/home)

Enable custom chrome CSS:

1. Open `about:config`
2. Set `toolkit.legacyUserProfileCustomizations.stylesheets` to `true`
3. Open `about:profiles`
4. For your active profile, open the **Root Directory**
5. Create a `chrome/` folder if missing
6. Copy:
   - `apps/firefox/userchrome/userChrome.css` -> `<profile>/chrome/userChrome.css`
   - `apps/firefox/userchrome/userContent.css` -> `<profile>/chrome/userContent.css`
7. Restart Firefox

Notes:

- This gives more precise visual control than the official theme API.
- Firefox updates may break selectors; treat this as optional and maintain over time.

### Helper script (recommended)

You can automate the copy + preference step with:

```bash
./scripts/apply_firefox_userchrome.sh
```

Useful options:

- `--profile-name <name>` target a specific profile name from `profiles.ini`
- `--profile-path <absolute-path>` target an explicit profile path
- `--dry-run` preview without writing changes
