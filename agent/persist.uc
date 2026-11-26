// SPDX-License-Identifier: GPL-2.0-or-later
import * as fs from 'fs';
import { sync_fd } from 'inform';
import { initial, FACTORY_KEY } from 'session';
function owned(info, kind, uid) {
    return info && info.type == kind && info.uid == uid && (info.mode & 63) == 0;
}
function directory(path, uid) {
    if (!fs.lstat(path) && !fs.mkdir(path, 448)) die('cannot create state directory');
    if (!owned(fs.lstat(path), 'directory', uid)) die('unsafe state directory');
}
function validate(state) {
    if (type(state) != 'object' || !match(state.key || '', /^[0-9a-f]{32}$/) ||
        type(state.gcm) != 'bool' || !match(state.cfgversion || '', /^[0-9a-fA-F]{1,64}$/) ||
        (state.phase != 'pending' && state.phase != 'keyed') ||
        (state.phase == 'pending') != (state.key == FACTORY_KEY)) die('invalid saved state');
    let report = null;
    if (state.report != null) {
        let r = state.report.radio, ssids = state.report.ssids;
        if (type(r) != 'object' || (r.channel != 'auto' && !match(r.channel || '', /^([1-9]|10|11)$/)) ||
            (r.htmode != 'HT20' && r.htmode != 'HT40') || type(ssids) != 'array' || length(ssids) > 2)
            die('invalid saved radio report');
        report = { radio: { channel: r.channel, htmode: r.htmode, disabled: r.disabled === true }, ssids: [] };
        for (let s in ssids) {
            if (type(s.ssid) != 'string' || !length(s.ssid) || length(s.ssid) > 32 ||
                (s.vlan != null && (type(s.vlan) != 'int' || s.vlan < 1 || s.vlan > 4094)) ||
                (s.pmf != 0 && s.pmf != 1 && s.pmf != 2)) die('invalid saved SSID report');
            if (s.id != null && !match(s.id, /^[0-9a-fA-F]{1,64}$/)) die('invalid saved WLAN identity');
            if (s.devname != null && !match(s.devname, /^[a-zA-Z0-9_-]{1,15}$/)) die('invalid saved interface identity');
            push(report.ssids, { ssid: s.ssid, vlan: s.vlan, disabled: s.disabled === true, pmf: s.pmf, id: s.id, devname: s.devname });
        }
    }
    return { key: state.key, gcm: state.gcm, cfgversion: state.cfgversion, phase: state.phase, interval: 10, report };
}
export function load(path, uid) {
    uid = uid == null ? 0 : uid;
    directory(path, uid);
    let file = path + '/state.json', info = fs.lstat(file);
    if (!info) return initial();
    if (!owned(info, 'file', uid) || info.size > 4096) die('unsafe state file');
    let f = fs.open(file, 'r');
    if (!f) die('cannot read state file');
    let data = f.read(4097); f.close();
    return validate(json(data));
};
export function save(path, state, uid) {
    uid = uid == null ? 0 : uid;
    directory(path, uid);
    let safe = validate(state), temp = path + '/state.new', target = path + '/state.json';
    for (let name in [temp, target]) {
        let info = fs.lstat(name);
        if (info && !owned(info, 'file', uid)) die('unsafe state destination');
    }
    if (fs.lstat(temp) && !fs.unlink(temp)) die('cannot remove stale state temporary file');
    let f = fs.open(temp, 'wx', 384);
    if (!f) die('cannot create state file');
    let data = sprintf('%J', safe);
    if (f.write(data) != length(data) || !f.flush() || !sync_fd(f.fileno())) {
        f.close(); fs.unlink(temp); die('cannot persist state');
    }
    f.close();
    if (!fs.rename(temp, target)) die('cannot replace state file');
    let dir = fs.open(path, 'r');
    if (!dir || !sync_fd(dir.fileno())) { if (dir) dir.close(); die('cannot synchronize state directory'); }
    dir.close();
};
