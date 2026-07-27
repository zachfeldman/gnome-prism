import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as LoginManager from 'resource:///org/gnome/shell/misc/loginManager.js';
import { QuickToggle, SystemIndicator } from 'resource:///org/gnome/shell/ui/quickSettings.js';

import { Extension, InjectionManager } from 'resource:///org/gnome/shell/extensions/extension.js';

import St from 'gi://St';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';

import { Keys } from './enums.js';
import { PlayerProcess } from './core/player_process.js';

import { isOnBattery } from './utils/battery.js';
import { isGtk4PaintableSinkAvailable } from './utils/check_dependencies.js';
import { sendErrorNotification } from './utils/notifications.js';
import { SHELL_VERSION } from './utils/shell_version.js';
import { warn, error } from './utils/logging.js';

const MAX_DIALOG_INJECT_ATTEMPTS = 100;
const DIALOG_INJECT_INTERVAL = 100;
const WINDOW_TIMEOUT = 10000;

// GNOME Session Manager idle-inhibit flag (see org.gnome.SessionManager D-Bus docs).
const INHIBIT_IDLE_FLAG = 8;

// Momentary Quick Settings action: clicking it requests a real GNOME lock via
// Main.screenShield.lock(), it does not track an ongoing on/off state.
const ScreensaverToggle = GObject.registerClass(
class GnomePrismScreensaverToggle extends QuickToggle {
    _init(extensionObj) {
        super._init({
            title: 'Screensaver',
            iconName: 'video-display-symbolic',
        });

        this.connect('clicked', () => {
            extensionObj.activateScreensaver();
            this.checked = false;
        });
    }
});

const ScreensaverIndicator = GObject.registerClass(
class GnomePrismScreensaverIndicator extends SystemIndicator {
    _init(extensionObj) {
        super._init();
        this.quickSettingsItems.push(new ScreensaverToggle(extensionObj));
        Main.panel.statusArea.quickSettings.addExternalIndicator(this);
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        this.quickSettingsItems = [];
        super.destroy();
    }
});

export default class GnomePrismScreensaverExtension extends Extension {
    enable() {
        this._resetLockState();
        this._settings = this.getSettings();

        if (Main.sessionMode.currentMode === 'unlock-dialog')
            this._enableLockMode();
        else
            this._enableUserMode();
    }

    disable() {
        this._disableLockMode();
        this._disableUserMode();
        this._settings = null;
    }

    _resetLockState() {
        this._backgroundCreated = false;
        this._wrapperActors = {}; // connector -> actor
        this._windowActors = {};  // connector -> actor

        this._promptShown = false;
        this._injectionManager = null;
        this._player = null;
        this._tapAction = null;

        this._injectRetryId = 0;
        this._injectAttempts = 0;
        this._blurEffectTimeoutId = 0;

        this._hideUntilInteraction = false;
        this._keepAwake = false;
        this._inhibitCookie = null;

        this._quickSettingsIndicator = null;
        this._keybindingAdded = false;
        this._keybindingSettingsIds = null;
    }

    // ---------------------------------------------------------------------
    // Normal user-session mode: Quick Settings action + keyboard shortcut.
    // Neither of these touches the lock screen itself; they only ever ask
    // GNOME to perform its own real, secure lock via Main.screenShield.lock().
    // ---------------------------------------------------------------------

    _enableUserMode() {
        this._updateQuickSettingsIndicator();
        this._updateKeybinding();

        this._keybindingSettingsIds = [
            this._settings.connect(`changed::${Keys.SHOW_START_ACTION}`, () => this._updateQuickSettingsIndicator()),
            this._settings.connect(`changed::${Keys.KEYBINDING_ENABLED}`, () => this._updateKeybinding()),
            this._settings.connect(`changed::${Keys.KEYBINDING}`, () => this._updateKeybinding()),
        ];
    }

    _disableUserMode() {
        this._quickSettingsIndicator?.destroy();
        this._quickSettingsIndicator = null;

        this._removeKeybinding();

        if (this._keybindingSettingsIds) {
            this._keybindingSettingsIds.forEach(id => this._settings?.disconnect(id));
            this._keybindingSettingsIds = null;
        }
    }

    _updateQuickSettingsIndicator() {
        this._quickSettingsIndicator?.destroy();
        this._quickSettingsIndicator = null;

        if (this._settings.get_boolean(Keys.SHOW_START_ACTION))
            this._quickSettingsIndicator = new ScreensaverIndicator(this);
    }

    _updateKeybinding() {
        this._removeKeybinding();

        if (!this._settings.get_boolean(Keys.KEYBINDING_ENABLED))
            return;

        try {
            // Shell.ActionMode.NORMAL means this shortcut is only live in the
            // normal user session; it is inert while the screen is locked, so
            // it can never capture input during unlock-dialog mode.
            Main.wm.addKeybinding(
                Keys.KEYBINDING,
                this._settings,
                Meta.KeyBindingFlags.NONE,
                Shell.ActionMode.NORMAL,
                () => this.activateScreensaver()
            );
            this._keybindingAdded = true;
        } catch (e) {
            warn(`Failed to register keybinding: ${e}`);
        }
    }

    _removeKeybinding() {
        if (!this._keybindingAdded)
            return;

        try {
            Main.wm.removeKeybinding(Keys.KEYBINDING);
        } catch (e) {
            warn(`Failed to remove keybinding: ${e}`);
        }
        this._keybindingAdded = false;
    }

    // Requests GNOME's own real, secure lock. This never creates a fake lock
    // screen or bypasses authentication — it is the same call GNOME itself
    // uses for Super+L. Once locked, this extension's unlock-dialog mode
    // (_enableLockMode) takes over to show the video.
    activateScreensaver() {
        Main.screenShield.lock(true);
    }

    // ---------------------------------------------------------------------
    // unlock-dialog (locked) mode: video-on-lock-screen behavior, forked
    // from Live Lock Screen. See NOTICE.md for what changed vs upstream.
    // ---------------------------------------------------------------------

    _enableLockMode() {
        if (!isGtk4PaintableSinkAvailable()) {
            sendErrorNotification(
                'gtk4paintablesink is not available.' +
                'See README.md for installation instructions.'
            );
            return;
        }

        this._setupForLock();
    }

    _setupForLock() {
        const disableOnBatter = this._settings.get_boolean(Keys.DISABLE_ON_BATTERY);
        if (disableOnBatter && isOnBattery()) {
            warn('Skipping on battery');
            return;
        }

        const videoPath = this._settings.get_string(Keys.VIDEO_PATH);
        if (!videoPath) {
            warn('Video not set, falling back');
            return;
        }

        this._fadeInDuration  = this._settings.get_int(Keys.FADE_IN_DURATION);
        this._scalingMode = this._settings.get_int(Keys.SCALING_MODE);
        this._blurRadius = this._settings.get_int(Keys.BLUR_RADIUS);
        this._blurBrightness = this._settings.get_double(Keys.BLUR_BRIGHTNESS);
        this._forceFullscreen = this._settings.get_boolean(Keys.DEBUG_FORCE_FULLSCREEN);

        this._hideUntilInteraction = this._settings.get_boolean(Keys.HIDE_UNTIL_INTERACTION);
        this._keepAwake = this._settings.get_boolean(Keys.KEEP_AWAKE);

        const volume = this._settings.get_int(Keys.AUDIO_VOLUME) / 100;
        const loop = this._settings.get_boolean(Keys.LOOPED);
        const useVideorate = this._settings.get_boolean(Keys.USE_VIDEORATE);
        const framerate = this._settings.get_int(Keys.FRAMERATE);
        const colorAccurate = this._settings.get_boolean(Keys.DEBUG_USE_COLOR_ACCURATE);

        this._promptSettings = {
            [Keys.PROMPT_PAUSE]:              this._settings.get_boolean(Keys.PROMPT_PAUSE),
            [Keys.PROMPT_GRAYSCALE]:          this._settings.get_boolean(Keys.PROMPT_GRAYSCALE),
            [Keys.PROMPT_CHANGE_BLUR]:        this._settings.get_boolean(Keys.PROMPT_CHANGE_BLUR),
            [Keys.PROMPT_BLUR_RADIUS]:        this._settings.get_int(Keys.PROMPT_BLUR_RADIUS),
            [Keys.PROMPT_BLUR_ANIM_DURATION]: this._settings.get_int(Keys.PROMPT_BLUR_ANIM_DURATION),
            [Keys.PROMPT_BLUR_BRIGHTNESS]:    this._settings.get_double(Keys.PROMPT_BLUR_BRIGHTNESS),
        };

        const themeContext = St.ThemeContext.get_for_stage(global.stage);
        this._blurRadius  *= themeContext.scale_factor;

        this._blurEffect = {
            name: 'lockscreen-extension-blur',
            radius: this._blurRadius,
            brightness: this._blurBrightness,
        };

        this._player = new PlayerProcess({
            playerPath: this.path + '/external/run.js',
            videoPath,
            scalingMode: this._scalingMode,
            loop,
            volume,
            useVideorate,
            framerate,
            colorAccurate: colorAccurate
        });

        try {
            this._player.run();
        } catch (e) {
            error('Failed to run video player! Falling back...', e);
            this._player = null;
            return;
        }

        // Temporarily hide all animations for windows
        this._injectionManager = new InjectionManager();
        this._injectionManager.overrideMethod(
            Main.wm,
            '_shouldAnimateActor',
            (original) => {
                return function(actor, types) {
                    return false;
                };
            }
        );

        const monitorCount = Main.layoutManager.monitors.length;
        this._player.waitForWindows(monitorCount, WINDOW_TIMEOUT, (data) => {
            for (const win of data) {
                //NOTE: Relying on connector name for better reliability (indices are not static)
                const title = win.get_title() || '';
                const match = title.match(/^LLS-Player-(.+)$/);
                const connector = match ? match[1] : null;
                this._windowActors[connector] = win.get_compositor_private();
            }

            this._injectIntoDialog();
        }, (err) => {
            error(`Unable to intercept all windows: ${err}`);
        })
    }

    _injectIntoDialog() {
        const dialog = Main.screenShield._dialog;
        const gtype = dialog._swipeTracker.constructor.$gtype;

        if (!dialog) {
            if (this._injectAttempts >= MAX_DIALOG_INJECT_ATTEMPTS) {
                error(`_dialog never appeared after ${MAX_DIALOG_INJECT_ATTEMPTS} attempts, giving up`);
                this._injectAttempts = 0;
                return;
            }
            this._injectAttempts++;
            this._injectRetryId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, DIALOG_INJECT_INTERVAL, () => {
                this._injectRetryId = 0;
                this._injectIntoDialog();
                return GLib.SOURCE_REMOVE;
            });
            return;
        }

        this._injectAttempts = 0;
        this._injectCreateBackground();

        this._injectionManager.overrideMethod(
            dialog, '_showPrompt',
            (original) => {
                const self = this;
                return function(...args) {
                    // Reveal any clean-mode-hidden clock/notification chrome
                    // before GNOME's own clock->prompt transition runs, so
                    // the normal unlock animation looks correct.
                    self._restoreCleanMode(this);
                    original.call(this, ...args);
                    self._onPromptShow();
                };
            }
        );

        // Removing the existing signal to use our custom one
        const swipeSignalId = GObject.signal_lookup('end', gtype);
        dialog._swipeTracker.disconnect(swipeSignalId);

        dialog._swipeTracker.connectObject('end', (...args) => {
            dialog._swipeEnd(...args);
            if (dialog._activePage == dialog._clock)
                this._onPromptHide();
            else
                this._onPromptShow();
        }, this);

        this._injectionManager.overrideMethod(
            dialog, '_showClock',
            (original) => {
                const self = this;
                return function(...args) {
                    original.call(this, ...args);
                    self._onPromptHide();
                    // Hide clock/date/notifications again once we're back on
                    // the clock page, so the screensaver stays clean.
                    self._applyCleanMode(this);
                };
            }
        );

        //NOTE: Replacing TapAction with a fresh one if exists (for gnome 48 and older)
        this._tapAction = (SHELL_VERSION < 49) ? new Clutter.TapAction() : null;
        if (this._tapAction) {
            this._tapAction.connectObject(
                'tap', dialog._showPrompt.bind(dialog), this
            );
        }

        dialog._updateBackgrounds();

        // Apply the clean state immediately for the initial locked view,
        // in case _showClock isn't invoked again right after this injection.
        this._applyCleanMode(dialog);
    }

    _injectCreateBackground() {
        this._injectionManager.overrideMethod(
            Main.screenShield._dialog, '_createBackground',
            (original) => {
                const self = this;
                return function(monitorIndex) {
                    original.call(this, monitorIndex);
                    self._handleMonitor(monitorIndex);
                };
            }
        );
    }

    // ---------------------------------------------------------------------
    // Clean screensaver mode: hide (never destroy) GNOME's own clock/date/
    // notifications chrome while the video is showing, and restore it as
    // soon as the user interacts. dialog._clock / dialog._notificationsBox
    // are private GNOME Shell APIs that can move between versions, so every
    // access here is guarded — if they're missing, clean mode is silently
    // skipped and the normal (non-clean) Live Lock Screen behavior is used
    // instead, rather than risking a broken lock screen.
    // ---------------------------------------------------------------------

    _getCleanModeActors(dialog) {
        return [dialog?._clock, dialog?._notificationsBox].filter(Boolean);
    }

    _applyCleanMode(dialog) {
        if (!this._hideUntilInteraction)
            return;

        try {
            for (const actor of this._getCleanModeActors(dialog))
                actor.visible = false;
        } catch (e) {
            warn(`Clean screensaver mode unsupported on this GNOME Shell version, falling back: ${e}`);
            this._hideUntilInteraction = false;
        }
    }

    _restoreCleanMode(dialog) {
        if (!this._hideUntilInteraction)
            return;

        try {
            for (const actor of this._getCleanModeActors(dialog))
                actor.visible = true;
        } catch (e) {
            warn(`Failed to restore lock-screen interface: ${e}`);
        }
    }

    // ---------------------------------------------------------------------
    // Keep display awake while the screensaver video is visible, via the
    // standard GNOME Session Manager idle inhibitor (no root, no daemons).
    // ---------------------------------------------------------------------

    _requestKeepAwake() {
        if (!this._keepAwake || this._inhibitCookie !== null)
            return;

        try {
            const proxy = Gio.DBusProxy.new_for_bus_sync(
                Gio.BusType.SESSION,
                Gio.DBusProxyFlags.NONE,
                null,
                'org.gnome.SessionManager',
                '/org/gnome/SessionManager',
                'org.gnome.SessionManager',
                null
            );
            const result = proxy.call_sync(
                'Inhibit',
                new GLib.Variant('(susu)', [
                    'gnome-prism-screensaver', 0, 'Screensaver video is visible', INHIBIT_IDLE_FLAG,
                ]),
                Gio.DBusCallFlags.NONE, -1, null
            );
            this._inhibitCookie = result.deep_unpack()[0];
        } catch (e) {
            warn(`Failed to inhibit idle for keep-awake: ${e}`);
            this._inhibitCookie = null;
        }
    }

    _releaseKeepAwake() {
        if (this._inhibitCookie === null)
            return;

        try {
            const proxy = Gio.DBusProxy.new_for_bus_sync(
                Gio.BusType.SESSION,
                Gio.DBusProxyFlags.NONE,
                null,
                'org.gnome.SessionManager',
                '/org/gnome/SessionManager',
                'org.gnome.SessionManager',
                null
            );
            proxy.call_sync(
                'Uninhibit',
                new GLib.Variant('(u)', [this._inhibitCookie]),
                Gio.DBusCallFlags.NONE, -1, null
            );
        } catch (e) {
            warn(`Failed to release keep-awake inhibitor: ${e}`);
        } finally {
            this._inhibitCookie = null;
        }
    }

    _onPromptShow() {
        if (this._promptShown) return;
        this._promptShown = true;

        if (this._promptSettings[Keys.PROMPT_CHANGE_BLUR]) {
            const radius = this._promptSettings[Keys.PROMPT_BLUR_RADIUS];
            const brightness = radius ? this._promptSettings[Keys.PROMPT_BLUR_BRIGHTNESS] : 1;

            // Adding a slight timeout helps get rid of video stutters
            this._blurEffectTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 10, () => {
                Object.values(this._wrapperActors).forEach(actor => {
                    actor.ease_property('@effects.lockscreen-extension-blur.radius', radius, {
                        duration: this._promptSettings[Keys.PROMPT_BLUR_ANIM_DURATION],
                        mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                    });
                    actor.ease_property('@effects.lockscreen-extension-blur.brightness', brightness, {
                        duration: this._promptSettings[Keys.PROMPT_BLUR_ANIM_DURATION],
                        mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                    });
                })

                return GLib.SOURCE_REMOVE;
            });
        }

        if (this._promptSettings[Keys.PROMPT_GRAYSCALE]) {
            Object.values(this._wrapperActors).forEach(actor => {
                actor.ease_property('@effects.lockscreen-extension-desaturate.factor', 1.0, {
                    duration: this._promptSettings[Keys.PROMPT_BLUR_ANIM_DURATION],
                    mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                });
            })
        }

        if (this._promptSettings[Keys.PROMPT_PAUSE])
            this._player?.pause();

    }

    _onPromptHide() {
        if (!this._promptShown) return;
        this._promptShown = false;

        if (this._promptSettings[Keys.PROMPT_CHANGE_BLUR]) {
            const radius = this._blurRadius;
            const brightness = radius ? this._blurBrightness : 1;

            Object.values(this._wrapperActors).forEach(actor => {
                actor.ease_property('@effects.lockscreen-extension-blur.radius', radius, {
                    duration: this._promptSettings[Keys.PROMPT_BLUR_ANIM_DURATION],
                    mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                });
                actor.ease_property('@effects.lockscreen-extension-blur.brightness', brightness, {
                    duration: this._promptSettings[Keys.PROMPT_BLUR_ANIM_DURATION],
                    mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                });
            });
        }

        if (this._promptSettings[Keys.PROMPT_GRAYSCALE]) {
            Object.values(this._wrapperActors).forEach(actor => {
                actor.ease_property('@effects.lockscreen-extension-desaturate.factor', 0.0, {
                    duration: this._promptSettings[Keys.PROMPT_BLUR_ANIM_DURATION],
                    mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                });
            })
        }

        if (this._promptSettings[Keys.PROMPT_PAUSE])
            this._player?.play();
    }

    _handleMonitor(monitorIndex) {
        let targetConnector = null;
        const monitorManager = global.backend.get_monitor_manager();

        for (let connector of Object.keys(this._windowActors)) {
            const idx = monitorManager.get_monitor_for_connector(connector);
            if (idx == monitorIndex) {
                targetConnector = connector;
                break;
            }
        }

        if (!targetConnector) {
            warn(`Actor not found for monitor ${monitorIndex}! Skipping...`);
            return;
        }

        if (targetConnector in this._wrapperActors) {
            warn(`Wrapper already exists for monitor ${targetConnector}, skipping`);
            return;
        }

        const isLastMonitor = monitorIndex === Main.layoutManager.monitors.length - 1;
        const monitor = Main.layoutManager.monitors[monitorIndex];
        const windowActor = this._windowActors[targetConnector];

        if (windowActor) {
            const parent = windowActor.get_parent();
            if (parent) parent.remove_child(windowActor);

            const wrapper = new Clutter.Actor();

            Main.screenShield._dialog._backgroundGroup.add_child(wrapper);
            Main.screenShield._dialog._backgroundGroup.set_child_above_sibling(wrapper, null);

            wrapper.add_effect(new Shell.BlurEffect(this._blurEffect));

            // Adding color desaturation effect if needed
            if (this._promptSettings[Keys.PROMPT_GRAYSCALE]) {
                wrapper.add_effect_with_name(
                    'lockscreen-extension-desaturate',
                    new Clutter.DesaturateEffect({ factor: 0.0 })
                );
            }

            if (!this._backgroundCreated)
                wrapper.opacity = 0;

            wrapper.add_child(windowActor);
            wrapper.set_child_above_sibling(windowActor, null);
            wrapper.connectObject('destroy', () => {
                const p = windowActor.get_parent();
                if (p) p.remove_child(windowActor);
                global.window_group.add_child(windowActor);
                delete this._wrapperActors[targetConnector];
            });

            if (this._forceFullscreen) {
                wrapper.set_position(0, 0);

                const win = windowActor.get_meta_window();
                win.move_to_monitor(monitorIndex);
                win.make_fullscreen();

            } else {
                wrapper.set_position(monitor.x, monitor.y);
                wrapper.set_size(monitor.width, monitor.height);
                wrapper.set_clip_to_allocation(true);

                // NOTE:
                // This might look like an overkill,
                // but you really need to aggressively position actors on any
                // size/position change
                const fixPositionAndScale = () => {
                    windowActor.set_translation(
                        -windowActor.x, -windowActor.y, 0
                    );
                    windowActor.set_pivot_point(0, 0);
                    windowActor.set_scale(1, 1);
                };
                windowActor.connectObject('notify::x', fixPositionAndScale, this);
                windowActor.connectObject('notify::y', fixPositionAndScale, this);
                windowActor.connectObject('notify::width', fixPositionAndScale, this);
                windowActor.connectObject('notify::height', fixPositionAndScale, this);

                fixPositionAndScale();
            }

            this._wrapperActors[targetConnector] = wrapper;

        } else {
            warn(`No window actor for monitor ${targetConnector}, skipping`);
        }

        if (!this._backgroundCreated && isLastMonitor) {
            this._initLoginManager();
            this._startAnimation();
            this._player.play();
            this._requestKeepAwake();

            this._backgroundCreated = true;
        }
    }

    _startAnimation() {
        Object.values(this._wrapperActors).forEach(actor => actor.ease({
            opacity: 255,
            duration: this._fadeInDuration,
            mode: Clutter.AnimationMode.EASE_IN_QUAD,
        }));
    }

    _initLoginManager() {
        this._loginManager = LoginManager.getLoginManager();
        this._loginManager.connectObject('prepare-for-sleep', (_manager, aboutToSleep) => {
            if (!this._player) return;
            aboutToSleep ? this._player.pause() : this._player.play();
        }, this);
    }

    _disableLockMode() {
        /*
         * User unlocked the screen.
         * Stopping the videoplayblack and cleaning everything up
        */
        if (this._injectRetryId) {
            GLib.source_remove(this._injectRetryId);
            this._injectRetryId = 0;
        }
        if (this._blurEffectTimeoutId) {
            GLib.source_remove(this._blurEffectTimeoutId);
            this._blurEffectTimeoutId = 0;
        }
        this._injectAttempts = 0;

        try {
            this._restoreCleanMode(Main.screenShield._dialog);
        } catch (_) { /* dialog may already be gone */ }

        Main.screenShield._dialog?._swipeTracker?.disconnectObject(this);
        this._tapAction?.disconnectObject(this);

        // Return all window actors to window_group before destroying
        for (const windowActor of Object.values(this._windowActors)) {
            const parent = windowActor.get_parent();
            if (parent) parent.remove_child(windowActor);

            windowActor.disconnectObject(this);
            global.window_group.add_child(windowActor);
            windowActor.hide();
        }
        this._windowActors = {};

        this._player?.destroy();
        this._player = null;

        this._injectionManager?.clear();
        this._injectionManager = null;

        this._loginManager?.disconnectObject(this);

        Object.values(this._wrapperActors).forEach(actor => {
            actor.disconnectObject(this);
            actor.remove_effect_by_name('lockscreen-extension-blur');
            actor.remove_effect_by_name('lockscreen-extension-desaturate');
            actor.destroy()
        })
        this._wrapperActors = {};

        this._releaseKeepAwake();
    }
}
