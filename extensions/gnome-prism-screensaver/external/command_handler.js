import Gio from 'gi://Gio';
import GioUnix from 'gi://GioUnix';
import GLib from 'gi://GLib';

export default class CommandHandler {
    constructor() {
        this._stdin = null;
        this._handlers = new Map();
        this._cancelled = false;
    }

    init() {
        this._stdin = new Gio.DataInputStream({
            base_stream: new GioUnix.InputStream({ 
                fd: 0, 
                close_fd: false 
            })
        });
        this._read();
    }

    addHandler(command, callback) {
        this._handlers.set(command, callback);
    }

    removeHandler(command) {
        this._handlers.delete(command);
    }

    _read() {
        if (this._cancelled) return;

        this._stdin.read_line_async(GLib.PRIORITY_DEFAULT, null, (_, result) => {
            const [line] = this._stdin.read_line_finish(result);
            if (line) {
                const cmd = new TextDecoder().decode(line);
                const handler = this._handlers.get(cmd);
                if (handler) handler();
            }
            this._read();
        });
    }

    destroy() {
        this._cancelled = true;
        this._handlers.clear();

        if (this._stdin) {
            this._stdin.close(null);
            this._stdin = null;
        }
    }
}