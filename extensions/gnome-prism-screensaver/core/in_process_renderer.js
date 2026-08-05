import Gst from 'gi://Gst';
import GstApp from 'gi://GstApp'; // eslint-disable-line no-unused-vars -- loads the typelib so appsink is properly typed
import GLib from 'gi://GLib';
import Cogl from 'gi://Cogl';
import St from 'gi://St';

import { initGst } from '../utils/safe_gst.js';
import { warn, error } from '../utils/logging.js';

// ~120Hz -- comfortably above any real video or display framerate, so the
// poll loop never becomes the bottleneck on frame delivery (see
// _startPolling for why this isn't tied to the configured framerate).
const POLL_INTERVAL_MS = 8;

// Renders decoded video frames directly into an St.ImageContent inside
// GNOME Shell's own process, instead of spawning a separate window in a
// separate process and reparenting its compositor actor into the lock
// dialog. The window-stealing approach breaks Wayland frame-callback
// delivery once the actor is moved outside Mutter's normal window
// management tree, leaving the client stalled on its first (often blank)
// committed frame until some unrelated repaint (e.g. the unlock prompt
// transition) incidentally unsticks it. Pushing raw decoded buffers
// straight into a native Clutter content object sidesteps that entirely:
// there is no separate window, no separate process, and no Wayland
// surface to go stale.
export class InProcessVideoRenderer {
    constructor({ videoPath, loop, volume, framerate, useVideorate }) {
        this._videoPath = videoPath;
        this._loop = loop;
        this._volume = volume;
        this._framerate = framerate;
        this._useVideorate = useVideorate;

        this._pipeline = null;
        this._appsink = null;
        this._bus = null;
        this._content = null;
        this._width = 0;
        this._height = 0;
        this._onReady = null;
        this._coglContext = null;
        this._pollId = 0;
        this._watchdogId = 0;
    }

    // onReady(content, width, height) is called once, the first time a
    // frame is decoded and the St.ImageContent is created.
    init(onReady) {
        initGst();

        this._onReady = onReady;
        this._coglContext = global.stage.context.get_backend().get_cogl_context();

        this._pipeline = Gst.ElementFactory.make('playbin', 'playbin');

        const rateStage = this._useVideorate
            ? `videorate skip-to-first=true ! video/x-raw,framerate=${this._framerate}/1 ! `
            : '';
        // NOTE: emit-signals is deliberately left at its default (false).
        // appsink's 'new-sample' signal fires on GStreamer's own streaming
        // thread, not the GLib main thread gnome-shell's Cogl/Clutter state
        // is bound to -- calling into Cogl/GJS from that thread caused a
        // full compositor crash (cascading into the X server and other
        // clients' GPU contexts) during testing. Polling try_pull_sample()
        // from our own GLib.timeout_add callback instead guarantees every
        // Cogl/GJS call here happens on the main thread.
        const sinkDesc =
            `videoconvert ! videoscale ! ${rateStage}video/x-raw,format=RGBA ! ` +
            `appsink name=sink sync=true max-buffers=1 drop=true`;

        const videoSinkBin = Gst.parse_bin_from_description(sinkDesc, true);
        if (!videoSinkBin)
            throw new Error('Failed to create appsink video-sink bin');

        this._appsink = videoSinkBin.get_by_name('sink');
        if (!this._appsink)
            throw new Error('Failed to find appsink in video-sink bin');

        this._pipeline.set_property('video-sink', videoSinkBin);
        // playbin has its own volume/mute properties -- no need to hand-build
        // an audio bin the way the subprocess player did.
        this._pipeline.set_property('volume', this._volume);

        this._bus = this._pipeline.get_bus();
        this._bus.add_signal_watch();
        this._bus.connect('message', (_, msg) => {
            if (this._loop && msg.type === Gst.MessageType.EOS) {
                this._pipeline.seek_simple(
                    Gst.Format.TIME,
                    Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT,
                    0
                );
            } else if (msg.type === Gst.MessageType.ERROR) {
                const [gerror, debug] = msg.parse_error();
                error(`In-process pipeline error: ${gerror.message} (${debug})`);
            }
        });

        const uri = GLib.filename_to_uri(this._videoPath, null);
        this._pipeline.set_property('uri', uri);
    }

    // Runs on the GLib main loop (guaranteed, since it's only ever invoked
    // from our own GLib.timeout_add callback) -- safe to touch Cogl/GJS
    // objects here, unlike in an appsink signal handler.
    _pullFrame() {
        if (!this._appsink)
            return;

        try {
            // The prerolled frame (available once PAUSED, before PLAYING
            // ever starts) is only reliably retrieved via try_pull_preroll;
            // try_pull_sample alone never returns it while still paused.
            const sample = this._appsink.try_pull_preroll(0) ?? this._appsink.try_pull_sample(0);
            if (!sample)
                return;

            const buffer = sample.get_buffer();
            const caps = sample.get_caps();
            const struct = caps.get_structure(0);
            const width = struct.get_int('width')[1];
            const height = struct.get_int('height')[1];
            const rowstride = width * 4;

            const [ok, mapInfo] = buffer.map(Gst.MapFlags.READ);
            if (!ok)
                return;

            try {
                const bytes = GLib.Bytes.new(mapInfo.data);

                if (!this._content || this._width !== width || this._height !== height) {
                    this._content = St.ImageContent.new_with_preferred_size(width, height);
                    this._width = width;
                    this._height = height;
                    this._clearWatchdog();
                    warn(`First frame decoded (${width}x${height}), handing off to lock dialog`);
                    const readyCb = this._onReady;
                    this._onReady = null;
                    readyCb?.(this._content, width, height);
                }

                this._content.set_bytes(
                    this._coglContext, bytes, Cogl.PixelFormat.RGBA_8888,
                    width, height, rowstride
                );
            } finally {
                buffer.unmap(mapInfo);
            }
        } catch (e) {
            warn(`In-process frame upload failed: ${e}`);
        }
    }

    // Deliberately not derived from this._framerate: that setting only
    // actually re-times the pipeline when useVideorate is on (it's off by
    // default), so polling at the configured output framerate instead of
    // the source video's native framerate caused a beat pattern against
    // appsink's sync=true delivery -- some polls missed a frame that had
    // already been dropped (max-buffers=1), others re-grabbed a stale one,
    // producing visible jitter. appsink only makes a sample available once
    // its timestamp has passed, so polling faster than any real video
    // framerate is safe -- an early poll just returns null immediately.
    _startPolling() {
        if (this._pollId)
            return;

        this._pollId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, POLL_INTERVAL_MS, () => {
            this._pullFrame();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _stopPolling() {
        if (this._pollId) {
            GLib.source_remove(this._pollId);
            this._pollId = 0;
        }
    }

    // Diagnostic for a black-screen report where the lock UI came up with
    // no video and no error was ever logged -- if GStreamer's preroll
    // stalls silently (no bus ERROR message), _pullFrame just keeps
    // polling forever with nothing to show. This makes that stall visible
    // in the logs instead of indistinguishable from a working, still-
    // starting pipeline.
    _startWatchdog() {
        this._clearWatchdog();
        this._watchdogId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 6, () => {
            this._watchdogId = 0;
            const [, state] = this._pipeline?.get_state(0) ?? [null, Gst.State.NULL];
            warn(`No video frame after 6s of preroll -- pipeline state is still ${state}. ` +
                'The GStreamer pipeline may be stuck; the lock screen will stay blank until it recovers.');
            return GLib.SOURCE_REMOVE;
        });
    }

    _clearWatchdog() {
        if (this._watchdogId) {
            GLib.source_remove(this._watchdogId);
            this._watchdogId = 0;
        }
    }

    get content() {
        return this._content;
    }

    setVolume(volume) {
        this._pipeline?.set_property('volume', volume);
    }

    preroll() {
        this._pipeline.set_state(Gst.State.PAUSED);
        // A prerolled sample is available in PAUSED state -- start polling
        // immediately so onReady (and a first visible frame) fires without
        // waiting for an explicit play().
        this._startPolling();
        this._startWatchdog();
    }

    play() {
        this._pipeline?.set_state(Gst.State.PLAYING);
        this._startPolling();
    }

    pause() {
        this._pipeline?.set_state(Gst.State.PAUSED);
    }

    destroy() {
        this._stopPolling();
        this._clearWatchdog();

        if (this._bus) {
            this._bus.remove_signal_watch();
            this._bus = null;
        }
        if (this._pipeline) {
            this._pipeline.set_state(Gst.State.NULL);
            this._pipeline = null;
        }
        this._appsink = null;
        this._content = null;
    }
}
