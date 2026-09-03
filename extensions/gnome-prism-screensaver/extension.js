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

import { Keys, ScalingMode } from './enums.js';
import { InProcessVideoRenderer } from './core/in_process_renderer.js';

import { isOnBattery } from './utils/battery.js';
import { pickNextVideoPath } from './utils/video_directory.js';
import { sendErrorNotification } from './utils/notifications.js';
import { SHELL_VERSION } from './utils/shell_version.js';
import { warn, error } from './utils/logging.js';

const MAX_DIALOG_WAIT_ATTEMPTS = 100;
const DIALOG_WAIT_INTERVAL = 100;

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

        // GNOME Shell does NOT re-invoke enable()/disable() on every
        // session-mode transition just because both "user" and
        // "unlock-dialog" are declared in metadata.json -- once enabled for
        // a mode-set, it keeps running continuously across transitions
        // within that set. So we track mode changes ourselves for the
        // lifetime of this single enable() call, rather than depending on
        // GNOME calling enable()/disable() again per lock/unlock.
        this._enableUserMode();

        this._lockModeActive = false;
        this._sessionModeChangedId = Main.sessionMode.connect(
            'updated', () => this._onSessionModeChanged()
        );
        this._onSessionModeChanged();
    }

    disable() {
        if (this._sessionModeChangedId) {
            Main.sessionMode.disconnect(this._sessionModeChangedId);
            this._sessionModeChangedId = null;
        }

        this._disableLockMode();
        this._disableUserMode();
        this._settings = null;
    }

    _onSessionModeChanged() {
        const locked = Main.sessionMode.currentMode === 'unlock-dialog';

        if (locked && !this._lockModeActive) {
            this._lockModeActive = true;
            this._enableLockMode();
        } else if (!locked && this._lockModeActive) {
            this._lockModeActive = false;
            this._disableLockMode();
        }
    }

    // Called once when the extension is enabled (session start / toggle),
    // NOT once per lock cycle -- see _resetPerLockState() for that.
    _resetLockState() {
        this._resetPerLockState();

        this._quickSettingsIndicator = null;
        this._keybindingAdded = false;
        this._keybindingSettingsIds = null;

        this._lockModeActive = false;
        this._sessionModeChangedId = null;
    }

    // Called at the start of every individual lock cycle. Since enable()
    // only runs once per session (see _onSessionModeChanged()), state must
    // be reset here on each new lock, not just once in _resetLockState().
    _resetPerLockState() {
        this._videoActors = {}; // monitor index -> container actor
        this._promptShown = false;
        this._injectionManager = null;
        this._renderer = null;
        this._tapAction = null;

        this._dialogWaitId = 0;
        this._dialogWaitAttempts = 0;

        this._hideUntilInteraction = false;
        this._keepAwake = false;
        this._inhibitCookie = null;

        this._suppressedLightboxes = [];
        this._heartbeatId = 0;
        this._displayConfigProxy = null;
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
    // unlock-dialog (locked) mode: renders video directly into GNOME's lock
    // dialog using an in-process GStreamer appsink -> St.ImageContent
    // pipeline (see core/in_process_renderer.js for why this replaced the
    // original Live Lock Screen window-stealing approach).
    // ---------------------------------------------------------------------

    _enableLockMode() {
        warn('_enableLockMode() invoked');
        this._resetPerLockState();
        this._setupForLock();
    }

    // Returns the video file to play for this lock cycle: either the single
    // configured file, or -- if directory rotation is enabled -- the next
    // file from the configured directory (sequential or random order),
    // persisting the chosen index in settings so sequential order keeps
    // advancing across locks and sessions.
    _pickVideoPath() {
        const rotationEnabled = this._settings.get_boolean(Keys.VIDEO_ROTATION_ENABLED);
        const directoryPath = this._settings.get_string(Keys.VIDEO_DIRECTORY_PATH);

        if (!rotationEnabled || !directoryPath)
            return this._settings.get_string(Keys.VIDEO_PATH);

        const order = this._settings.get_int(Keys.VIDEO_ROTATION_ORDER);
        const lastIndex = this._settings.get_int(Keys.VIDEO_ROTATION_INDEX);

        let picked;
        try {
            picked = pickNextVideoPath(directoryPath, order, lastIndex);
        } catch (e) {
            warn(`Failed to read video rotation directory "${directoryPath}": ${e}`);
            return null;
        }

        if (!picked) {
            warn(`No video files found in rotation directory "${directoryPath}"`);
            return null;
        }

        this._settings.set_int(Keys.VIDEO_ROTATION_INDEX, picked.index);
        return picked.path;
    }

    _setupForLock() {
        const disableOnBatter = this._settings.get_boolean(Keys.DISABLE_ON_BATTERY);
        if (disableOnBatter && isOnBattery()) {
            warn('Skipping on battery');
            return;
        }

        const videoPath = this._pickVideoPath();
        if (!videoPath) {
            warn('Video not set, falling back');
            return;
        }

        this._fadeInDuration = this._settings.get_int(Keys.FADE_IN_DURATION);
        this._scalingMode = this._settings.get_int(Keys.SCALING_MODE);
        this._blurRadius = this._settings.get_int(Keys.BLUR_RADIUS);
        this._blurBrightness = this._settings.get_double(Keys.BLUR_BRIGHTNESS);

        this._hideUntilInteraction = this._settings.get_boolean(Keys.HIDE_UNTIL_INTERACTION);
        this._keepAwake = this._settings.get_boolean(Keys.KEEP_AWAKE);

        const volume = this._settings.get_int(Keys.AUDIO_VOLUME) / 100;
        const loop = this._settings.get_boolean(Keys.LOOPED);
        const useVideorate = this._settings.get_boolean(Keys.USE_VIDEORATE);
        const framerate = this._settings.get_int(Keys.FRAMERATE);

        this._promptSettings = {
            [Keys.PROMPT_PAUSE]:              this._settings.get_boolean(Keys.PROMPT_PAUSE),
            [Keys.PROMPT_GRAYSCALE]:          this._settings.get_boolean(Keys.PROMPT_GRAYSCALE),
            [Keys.PROMPT_CHANGE_BLUR]:        this._settings.get_boolean(Keys.PROMPT_CHANGE_BLUR),
            [Keys.PROMPT_BLUR_RADIUS]:        this._settings.get_int(Keys.PROMPT_BLUR_RADIUS),
            [Keys.PROMPT_BLUR_ANIM_DURATION]: this._settings.get_int(Keys.PROMPT_BLUR_ANIM_DURATION),
            [Keys.PROMPT_BLUR_BRIGHTNESS]:    this._settings.get_double(Keys.PROMPT_BLUR_BRIGHTNESS),
        };

        const themeContext = St.ThemeContext.get_for_stage(global.stage);
        this._blurRadius *= themeContext.scale_factor;

        this._blurEffect = {
            name: 'lockscreen-extension-blur',
            radius: this._blurRadius,
            brightness: this._blurBrightness,
        };

        // Cap decode/convert/upload resolution to the largest connected
        // monitor's physical pixel size -- without this, a source video
        // larger than any display still gets decoded, color-converted, and
        // copied into a texture at full resolution every frame, which is
        // pure wasted CPU work on the same thread the compositor runs on.
        const monitors = Main.layoutManager.monitors;
        const maxWidth = Math.max(...monitors.map(m => m.width)) * themeContext.scale_factor;
        const maxHeight = Math.max(...monitors.map(m => m.height)) * themeContext.scale_factor;

        this._renderer = new InProcessVideoRenderer({
            videoPath, loop, volume, framerate, useVideorate, maxWidth, maxHeight,
        });

        try {
            this._renderer.init((content, width, height) => {
                this._videoWidth = width;
                this._videoHeight = height;
                this._waitForDialog();
            });
            this._renderer.preroll();
        } catch (e) {
            error(`Failed to start in-process video renderer! Falling back: ${e}`);
            sendErrorNotification(
                'Screensaver video failed to start. Falling back to the normal ' +
                'lock screen. See README.md for dependency and troubleshooting info.'
            );
            this._renderer = null;
        }
    }

    _waitForDialog() {
        const dialog = Main.screenShield._dialog;

        if (!dialog) {
            if (this._dialogWaitAttempts >= MAX_DIALOG_WAIT_ATTEMPTS) {
                error(`_dialog never appeared after ${MAX_DIALOG_WAIT_ATTEMPTS} attempts, giving up`);
                this._dialogWaitAttempts = 0;
                return;
            }
            this._dialogWaitAttempts++;
            this._dialogWaitId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, DIALOG_WAIT_INTERVAL, () => {
                this._dialogWaitId = 0;
                this._waitForDialog();
                return GLib.SOURCE_REMOVE;
            });
            return;
        }

        this._dialogWaitAttempts = 0;
        this._createVideoActors(dialog);
        this._injectPromptHooks(dialog);
        this._initLoginManager();
        this._startAnimation();
        this._renderer.play();
        this._requestKeepAwake();
        this._guardDisplayPower();

        // Apply the clean state immediately for the initial locked view.
        this._applyCleanMode(dialog);

        warn('Video actors created and fade-in started');
        this._startHeartbeat();
    }

    // Diagnostic for a report of the video going black after several hours
    // of unattended overnight playback, with no error or crash logged
    // anywhere -- unlike _startWatchdog (which only covers the initial
    // preroll), nothing previously monitored a lock cycle once video
    // successfully started, so a later stall was invisible. Logs the state
    // most likely to explain a silent go-dark: whether frames are still
    // arriving, whether the curtain-suppression override is still holding
    // opacity at 0, and whether the keep-awake inhibitor is still held.
    _startHeartbeat() {
        this._heartbeatId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 300, () => {
            const frameAge = this._renderer?.secondsSinceLastFrame();
            const lightboxState = this._suppressedLightboxes
                .map(({ name, lightbox }) => `${name}=opacity:${lightbox.opacity}`)
                .join(' ');
            const powerSaveMode = this._displayConfigProxy
                ?.get_cached_property('PowerSaveMode')?.unpack() ?? 'unwatched';
            warn(`Heartbeat: last frame ${frameAge?.toFixed(1) ?? 'never'}s ago, ` +
                `inhibitor=${this._inhibitCookie !== null ? 'held' : 'not held'}, ` +
                `powerSaveMode=${powerSaveMode}, ${lightboxState}`);
            return GLib.SOURCE_CONTINUE;
        });
    }

    _stopHeartbeat() {
        if (this._heartbeatId) {
            GLib.source_remove(this._heartbeatId);
            this._heartbeatId = 0;
        }
    }

    // No window/connector/PID matching needed at all -- unlike the old
    // window-stealing approach, we already know exactly which monitors
    // exist and can size a native actor per monitor directly.
    _createVideoActors(dialog) {
        const content = this._renderer.content;

        Main.layoutManager.monitors.forEach((monitor, index) => {
            const container = new Clutter.Actor({
                clip_to_allocation: true,
                x: monitor.x, y: monitor.y,
                width: monitor.width, height: monitor.height,
            });

            const videoActor = new Clutter.Actor({ content });
            this._positionForScalingMode(videoActor, monitor);

            container.add_child(videoActor);
            dialog._backgroundGroup.add_child(container);
            dialog._backgroundGroup.set_child_above_sibling(container, null);

            container.add_effect(new Shell.BlurEffect(this._blurEffect));
            if (this._promptSettings[Keys.PROMPT_GRAYSCALE]) {
                container.add_effect_with_name(
                    'lockscreen-extension-desaturate',
                    new Clutter.DesaturateEffect({ factor: 0.0 })
                );
            }

            container.opacity = 0;
            this._videoActors[index] = { container, videoActor };
        });
    }

    // Emulates CSS-style background-size stretch/contain(fit)/cover using
    // Clutter's content-gravity plus, for cover, manual oversize+centering
    // math (Clutter has no built-in "cover" gravity).
    _positionForScalingMode(videoActor, monitor) {
        const vw = this._videoWidth, vh = this._videoHeight;
        const mw = monitor.width, mh = monitor.height;

        if (this._scalingMode === ScalingMode.STRETCH || !vw || !vh) {
            videoActor.content_gravity = Clutter.ContentGravity.RESIZE_FILL;
            videoActor.set_position(0, 0);
            videoActor.set_size(mw, mh);
            return;
        }

        const containScale = Math.min(mw / vw, mh / vh);
        const coverScale = Math.max(mw / vw, mh / vh);
        const scale = this._scalingMode === ScalingMode.COVER ? coverScale : containScale;

        const w = vw * scale, h = vh * scale;
        videoActor.content_gravity = Clutter.ContentGravity.RESIZE_FILL;
        videoActor.set_size(w, h);
        videoActor.set_position((mw - w) / 2, (mh - h) / 2);
    }

    _injectPromptHooks(dialog) {
        this._injectionManager = new InjectionManager();

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

        if (dialog._swipeTracker) {
            const gtype = dialog._swipeTracker.constructor.$gtype;
            const swipeSignalId = GObject.signal_lookup('end', gtype);
            dialog._swipeTracker.disconnect(swipeSignalId);

            dialog._swipeTracker.connectObject('end', (...args) => {
                dialog._swipeEnd(...args);
                if (dialog._activePage == dialog._clock)
                    this._onPromptHide();
                else
                    this._onPromptShow();
            }, this);
        }

        // Replacing TapAction with a fresh one if it exists (needed on
        // GNOME 48 and older; newer versions handle tap-to-reveal without
        // this shim).
        this._tapAction = (SHELL_VERSION < 49) ? new Clutter.TapAction() : null;
        if (this._tapAction) {
            this._tapAction.connectObject(
                'tap', dialog._showPrompt.bind(dialog), this
            );
        }

        this._suppressLockCurtain();
    }

    // GNOME's own ScreenShield.lock() unconditionally schedules a brief
    // "curtain" fade-to-black (Main.screenShield._shortLightbox) on every
    // lock, as a privacy transition -- it sits in Main.uiGroup, above the
    // lock dialog and our video, and only lifts once the user interacts.
    // This is normal GNOME behavior on every lock, not specific to us, but
    // it defeats the point of a screensaver (video should stay visible,
    // not go black). Since Main.uiGroup/_shortLightbox are private APIs
    // that can move between versions, this is guarded like clean mode: if
    // unavailable, we skip suppression rather than risk breaking the lock.
    _suppressLockCurtain() {
        try {
            const shield = Main.screenShield;
            // _shortLightbox is the lock-transition curtain -- always
            // suppressed, since a screensaver going black defeats its own
            // purpose regardless of power settings. _longLightbox is the
            // idle-dim (already normally prevented by our keep-awake
            // inhibitor); only suppressed here too if the user actually
            // asked to keep the display awake, so we don't override their
            // power preference otherwise.
            const targets = this._keepAwake
                ? ['_shortLightbox', '_longLightbox']
                : ['_shortLightbox'];

            for (const name of targets) {
                const lightbox = shield?.[name];
                if (!lightbox)
                    continue;

                this._suppressedLightboxes.push({ name, lightbox });

                this._injectionManager.overrideMethod(
                    lightbox, 'lightOn',
                    () => function() { /* suppressed while screensaver is visible */ }
                );
                // In case a fade was already scheduled/mid-flight before we
                // got here, make sure it isn't left visibly opaque.
                lightbox.opacity = 0;
            }
        } catch (e) {
            warn(`Failed to suppress lock-transition curtain, falling back to normal GNOME behavior: ${e}`);
        }
    }

    // ---------------------------------------------------------------------
    // Clean screensaver mode: hide (never destroy) GNOME's own clock/date/
    // notifications chrome while the video is showing, and restore it as
    // soon as the user interacts. dialog._clock / dialog._notificationsBox
    // are private GNOME Shell APIs that can move between versions, so every
    // access here is guarded — if they're missing, clean mode is silently
    // skipped and the screensaver falls back to normal, non-clean behavior
    // instead of risking a broken lock screen.
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

    // Diagnostic evidence (a heartbeat showing frames still arriving and
    // the keep-awake inhibitor still held, yet the physical screen was
    // reported black until a key was pressed) showed the SessionManager
    // idle inhibitor above doesn't stop Mutter from independently blanking
    // the monitor -- that's governed by a separate DPMS property,
    // PowerSaveMode, on org.gnome.Mutter.DisplayConfig. Actively watching
    // and reverting it (rather than assuming the idle inhibitor covers it)
    // is the direct fix.
    _guardDisplayPower() {
        if (!this._keepAwake || this._displayConfigProxy)
            return;

        try {
            this._displayConfigProxy = Gio.DBusProxy.new_for_bus_sync(
                Gio.BusType.SESSION,
                Gio.DBusProxyFlags.NONE,
                null,
                'org.gnome.Mutter.DisplayConfig',
                '/org/gnome/Mutter/DisplayConfig',
                'org.gnome.Mutter.DisplayConfig',
                null
            );
            this._displayConfigProxy.connectObject('g-properties-changed', (proxy, changed) => {
                const variant = changed.deep_unpack()['PowerSaveMode'];
                if (variant && variant.unpack() !== 0) {
                    warn(`Monitor power-save mode changed to ${variant.unpack()} while screensaver ` +
                        'active -- forcing the display back on');
                    this._forceDisplayPowerOn();
                }
            }, this);
        } catch (e) {
            warn(`Failed to watch monitor power-save mode: ${e}`);
            this._displayConfigProxy = null;
        }
    }

    _forceDisplayPowerOn() {
        try {
            this._displayConfigProxy?.call_sync(
                'org.freedesktop.DBus.Properties.Set',
                new GLib.Variant('(ssv)', [
                    'org.gnome.Mutter.DisplayConfig', 'PowerSaveMode', new GLib.Variant('i', 0),
                ]),
                Gio.DBusCallFlags.NONE, -1, null
            );
        } catch (e) {
            warn(`Failed to force monitor power-save mode back on: ${e}`);
        }
    }

    _unguardDisplayPower() {
        this._displayConfigProxy?.disconnectObject(this);
        this._displayConfigProxy = null;
    }

    _onPromptShow() {
        if (this._promptShown) return;
        this._promptShown = true;

        const containers = Object.values(this._videoActors).map(v => v.container);

        if (this._promptSettings[Keys.PROMPT_CHANGE_BLUR]) {
            const radius = this._promptSettings[Keys.PROMPT_BLUR_RADIUS];
            const brightness = radius ? this._promptSettings[Keys.PROMPT_BLUR_BRIGHTNESS] : 1;

            // Adding a slight timeout helps get rid of video stutters
            this._blurEffectTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 10, () => {
                containers.forEach(actor => {
                    actor.ease_property('@effects.lockscreen-extension-blur.radius', radius, {
                        duration: this._promptSettings[Keys.PROMPT_BLUR_ANIM_DURATION],
                        mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                    });
                    actor.ease_property('@effects.lockscreen-extension-blur.brightness', brightness, {
                        duration: this._promptSettings[Keys.PROMPT_BLUR_ANIM_DURATION],
                        mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                    });
                });

                return GLib.SOURCE_REMOVE;
            });
        }

        if (this._promptSettings[Keys.PROMPT_GRAYSCALE]) {
            containers.forEach(actor => {
                actor.ease_property('@effects.lockscreen-extension-desaturate.factor', 1.0, {
                    duration: this._promptSettings[Keys.PROMPT_BLUR_ANIM_DURATION],
                    mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                });
            });
        }

        if (this._promptSettings[Keys.PROMPT_PAUSE])
            this._renderer?.pause();
    }

    _onPromptHide() {
        if (!this._promptShown) return;
        this._promptShown = false;

        const containers = Object.values(this._videoActors).map(v => v.container);

        if (this._promptSettings[Keys.PROMPT_CHANGE_BLUR]) {
            const radius = this._blurRadius;
            const brightness = radius ? this._blurBrightness : 1;

            containers.forEach(actor => {
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
            containers.forEach(actor => {
                actor.ease_property('@effects.lockscreen-extension-desaturate.factor', 0.0, {
                    duration: this._promptSettings[Keys.PROMPT_BLUR_ANIM_DURATION],
                    mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                });
            });
        }

        if (this._promptSettings[Keys.PROMPT_PAUSE])
            this._renderer?.play();
    }

    _startAnimation() {
        Object.values(this._videoActors).forEach(({ container }) => container.ease({
            opacity: 255,
            duration: this._fadeInDuration,
            mode: Clutter.AnimationMode.EASE_IN_QUAD,
        }));
    }

    _initLoginManager() {
        this._loginManager = LoginManager.getLoginManager();
        this._loginManager.connectObject('prepare-for-sleep', (_manager, aboutToSleep) => {
            if (!this._renderer) return;
            aboutToSleep ? this._renderer.pause() : this._renderer.play();
        }, this);
    }

    _disableLockMode() {
        // User unlocked the screen. Stop the video and clean everything up.
        this._stopHeartbeat();

        if (this._dialogWaitId) {
            GLib.source_remove(this._dialogWaitId);
            this._dialogWaitId = 0;
        }
        if (this._blurEffectTimeoutId) {
            GLib.source_remove(this._blurEffectTimeoutId);
            this._blurEffectTimeoutId = 0;
        }
        this._dialogWaitAttempts = 0;

        try {
            this._restoreCleanMode(Main.screenShield._dialog);
        } catch (_) { /* dialog may already be gone */ }

        Main.screenShield._dialog?._swipeTracker?.disconnectObject(this);
        this._tapAction?.disconnectObject(this);

        this._renderer?.destroy();
        this._renderer = null;

        this._injectionManager?.clear();
        this._injectionManager = null;

        this._loginManager?.disconnectObject(this);

        Object.values(this._videoActors).forEach(({ container }) => {
            try {
                container.disconnectObject(this);
                container.remove_effect_by_name('lockscreen-extension-blur');
                container.remove_effect_by_name('lockscreen-extension-desaturate');
                container.destroy();
            } catch (e) {
                warn(`Failed to tear down a video actor during cleanup: ${e}`);
            }
        });
        this._videoActors = {};

        this._releaseKeepAwake();
        this._unguardDisplayPower();
    }
}
