import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import { RotationOrder } from '../enums.js';

const VIDEO_EXTENSIONS = ['.mp4', '.webm', '.mkv', '.mov', '.avi', '.m4v', '.ogv', '.gif'];

// Sorted list of video/GIF files directly inside dirPath (no recursion),
// matched by extension since directory enumeration gives us filenames, not
// GStreamer-detected mime types.
export function listVideoFiles(dirPath) {
    const dir = Gio.File.new_for_path(dirPath);
    const files = [];

    const enumerator = dir.enumerate_children(
        'standard::name,standard::type',
        Gio.FileQueryInfoFlags.NONE, null
    );

    let info;
    while ((info = enumerator.next_file(null)) !== null) {
        if (info.get_file_type() !== Gio.FileType.REGULAR)
            continue;

        const name = info.get_name();
        const lower = name.toLowerCase();
        if (VIDEO_EXTENSIONS.some(ext => lower.endsWith(ext)))
            files.push(GLib.build_filenamev([dirPath, name]));
    }
    enumerator.close(null);

    files.sort();
    return files;
}

// Picks the next video path to play from dirPath, given the rotation order
// (see enums.js RotationOrder) and the index last played (for sequential
// order). Returns null if the directory has no recognized video files.
export function pickNextVideoPath(dirPath, order, lastIndex) {
    const files = listVideoFiles(dirPath);
    if (files.length === 0)
        return null;

    const index = order === RotationOrder.RANDOM
        ? Math.floor(Math.random() * files.length)
        : (lastIndex + 1) % files.length;

    return { path: files[index], index };
}
