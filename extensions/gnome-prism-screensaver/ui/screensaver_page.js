import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';
import GObject from 'gi://GObject';

import { Keys } from '../enums.js';

// GNOME Prism-specific preferences: immediate activation (Quick Settings +
// keyboard shortcut), clean screensaver mode, and keep-awake. Kept as its
// own page (rather than folded into upstream's General/Appearance pages) so
// it's clear at a glance which settings are GNOME Prism additions.
export var ScreensaverPage = GObject.registerClass(
class GnomePrismScreensaverPage extends Adw.PreferencesPage {
    _init(settings) {
        super._init({
            title: 'Screensaver',
            icon_name: 'video-display-symbolic',
            name: 'ScreensaverPage',
        });

        this._settings = settings;

        const activationGroup = new Adw.PreferencesGroup({
            title: 'Immediate activation',
            description: 'Start the screensaver on demand from the normal session',
        });
        activationGroup.add(this._buildShowStartActionRow());

        const shortcutRow = this._buildShortcutEnabledRow();
        const shortcutEntryRow = this._buildShortcutEntryRow();
        activationGroup.add(shortcutRow);
        activationGroup.add(shortcutEntryRow);

        const toggleShortcutEntry = () => shortcutEntryRow.set_sensitive(shortcutRow.active);
        toggleShortcutEntry();
        shortcutRow.connect('notify::active', toggleShortcutEntry);

        this.add(activationGroup);

        const cleanGroup = new Adw.PreferencesGroup({
            title: 'Clean screensaver mode',
            description: 'Hide the lock-screen clock, date, and notifications until you interact',
        });
        cleanGroup.add(this._buildCleanModeRow());
        this.add(cleanGroup);

        const powerGroup = new Adw.PreferencesGroup({ title: 'Power' });
        powerGroup.add(this._buildKeepAwakeRow());
        this.add(powerGroup);
    }

    _buildShowStartActionRow() {
        const row = new Adw.SwitchRow({
            title: 'Show "Start Screensaver" in Quick Settings',
        });
        this._settings.bind(Keys.SHOW_START_ACTION, row, 'active', Gio.SettingsBindFlags.DEFAULT);
        return row;
    }

    _buildShortcutEnabledRow() {
        const row = new Adw.SwitchRow({ title: 'Enable keyboard shortcut' });
        this._settings.bind(Keys.KEYBINDING_ENABLED, row, 'active', Gio.SettingsBindFlags.DEFAULT);
        return row;
    }

    _buildShortcutEntryRow() {
        const current = this._settings.get_strv(Keys.KEYBINDING)[0] ?? '';

        const row = new Adw.EntryRow({
            title: 'Shortcut',
            text: current,
        });

        row.connect('changed', () => {
            const text = row.get_text().trim();
            if (text === '') {
                this._settings.set_strv(Keys.KEYBINDING, []);
                row.remove_css_class('error');
                return;
            }

            const [ok] = Gtk.accelerator_parse(text);
            if (!ok) {
                row.add_css_class('error');
                return;
            }

            row.remove_css_class('error');
            this._settings.set_strv(Keys.KEYBINDING, [text]);
        });

        return row;
    }

    _buildCleanModeRow() {
        const row = new Adw.SwitchRow({
            title: 'Hide lock-screen interface until interaction',
            subtitle: 'Falls back to the normal animated lock screen if unsupported on this GNOME version',
        });
        this._settings.bind(Keys.HIDE_UNTIL_INTERACTION, row, 'active', Gio.SettingsBindFlags.DEFAULT);
        return row;
    }

    _buildKeepAwakeRow() {
        const row = new Adw.SwitchRow({
            title: 'Keep display awake while screensaver is visible',
        });
        this._settings.bind(Keys.KEEP_AWAKE, row, 'active', Gio.SettingsBindFlags.DEFAULT);
        return row;
    }
});
