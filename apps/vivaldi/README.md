# Vivaldi theming (proof of concept)

This folder contains a `gnome-prism` UI mod for Vivaldi using custom CSS.

## Files

- `apps/vivaldi/mods/custom.css` - custom UI CSS overrides

## Install via helper script

From repo root:

```bash
./scripts/apply_vivaldi_theme.sh
```

This installs to:

- `~/.local/share/gnome-prism/vivaldi/mods/custom.css`

## Enable in Vivaldi

1. Open `vivaldi://flags` and turn on **Allow CSS modifications**
2. Open `vivaldi://settings/appearance`
3. In **Custom UI Modifications**, set folder to:
   - `~/.local/share/gnome-prism/vivaldi/mods`
4. Restart Vivaldi

## Notes

- This is a proof-of-concept and depends on Vivaldi DOM/class names.
- Vivaldi updates may require CSS selector adjustments.
