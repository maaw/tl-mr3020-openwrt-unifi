// SPDX-License-Identifier: GPL-2.0-or-later
// Public factory credential; enabled only for explicit bootstrap, never recovery.
import * as fs from 'fs';
import { sync_fd } from 'inform';
export function lock(path, locked, uid) {
    uid = uid == null ? 0 : uid;
    let info = fs.lstat(path);
    if (!info || info.type != 'file' || info.uid != uid || (info.mode & 63) != 0) die('unsafe password database');
    let text = fs.readfile(path), lines = split(text, '\n'), found = 0;
    for (let n = 0; n < length(lines); n++) {
        if (substr(lines[n], 0, 5) != 'ubnt:') continue;
        let fields = split(lines[n], ':');
        fields[1] = locked ? '!' : '$5$mr3020lab$59piH6WyDR1luSD5.apY.mp4GqFgoEkXAyKIf85l0a0';
        lines[n] = join(':', fields); found++;
    }
    if (found != 1 || fs.lstat(path + '.mr3020-new')) die('invalid password database');
    let f = fs.open(path + '.mr3020-new', 'wx', 384);
    if (!f || f.write(join('\n', lines)) == null || !f.flush() || !sync_fd(f.fileno())) die('password database write failed');
    f.close();
    if (!fs.rename(path + '.mr3020-new', path)) die('password database replacement failed');
};
