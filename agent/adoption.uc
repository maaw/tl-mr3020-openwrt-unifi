// SPDX-License-Identifier: GPL-2.0-or-later
import * as fs from 'fs';
import { FACTORY_KEY } from 'session';
export function command(text, peer, controller) {
    if (peer != controller || type(text) != 'string' || length(text) > 512) die('adoption request rejected');
    let m = match(trim(text), /^(\/usr\/bin\/)?syswrapper\.sh set-adopt (http:\/\/[^ ]+\/inform) ([0-9a-fA-F]{32})$/);
    if (!m || m[2] != 'http://' + controller + ':8080/inform' || lc(m[3]) == FACTORY_KEY)
        die('unsupported adoption command');
    return { controller, key: lc(m[3]), created: time() };
};
export function consume(path, state, controller, uid) {
    let info = fs.lstat(path);
    if (!info) return state;
    if (info.type != 'file' || info.uid != uid || (info.mode & 63) != 0 || info.size > 1024)
        die('unsafe adoption handoff');
    let request = json(fs.readfile(path));
    if (!fs.unlink(path)) die('cannot consume adoption handoff');
    if (state.key != FACTORY_KEY || request.controller != controller ||
        !match(request.key || '', /^[0-9a-f]{32}$/) || request.key == FACTORY_KEY ||
        type(request.created) != 'int' || time() - request.created > 60 || request.created > time() + 5)
        die('invalid adoption handoff');
    return { ...state, key: request.key, phase: 'keyed' };
};
