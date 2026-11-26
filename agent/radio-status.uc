// SPDX-License-Identifier: GPL-2.0-or-later
import * as fs from 'fs';
import * as net from 'socket';

export function two_ghz(config) {
    return config?.band == '2g' || config?.hwmode == '11g';
};

export function parse_tx_power(output) {
    let power = match(output || '', /(^|\n)[ \t]+txpower[ \t]+(-?[0-9]+([.][0-9]+)?)[ \t]+dBm[ \t]*(\n|$)/);
    return power ? +sprintf('%.0f', +power[2]) : null;
};

// Older hostapd has no ubus get_status method. Its local STATUS command
// reports the running BSS without exposing the WPA passphrase.
export function parse_status(text, ifname) {
    if (type(text) != 'string' || length(text) > 8192) return null;
    let fields = {};
    for (let line in split(text, '\n')) {
        let at = index(line, '=');
        if (at > 0) fields[substr(line, 0, at)] = substr(line, at + 1);
    }
    // STATUS on a secondary BSS still returns the whole radio's BSS table.
    let number = ifname == null ? 0 : null;
    if (ifname != null)
        for (let index = 0; index < 16; index++)
            if (fields['bss[' + index + ']'] == ifname) number = index;
    if (number == null) return null;
    let ssid = fields['ssid[' + number + ']'], bssid = fields['bssid[' + number + ']'];
    let freq = +fields.freq;
    if (!fields.state || !ssid || !match(bssid || '', /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/)) return null;
    let channel = freq == 2484 ? 14 : (freq >= 2412 && freq <= 2472 && (freq - 2407) % 5 == 0 ? (freq - 2407) / 5 : null);
    if (channel == null) return null;
    return { status: fields.state, ssid, bssid: lc(bssid), channel };
};

export function ap_status(db, ifname) {
    if (!match(ifname || '', /^[a-zA-Z0-9_.-]{1,15}$/)) return null;
    let status = db.call('hostapd.' + ifname, 'get_status', {});
    if (status != null) return status;
    let dir = '/var/run/mr3020-ctrl';
    if (!fs.lstat(dir)) fs.mkdir(dir, 448);
    let info = fs.lstat(dir);
    if (!info || info.type != 'directory' || info.uid != 0 || (info.mode & 63) != 0) return null;
    let path = dir + '/reply.sock';
    if (fs.lstat(path)?.type == 'socket') fs.unlink(path);
    let sock = net.create(net.AF_UNIX, net.SOCK_DGRAM), reply = null;
    if (sock && sock.bind({ family: net.AF_UNIX, path })) {
        if (sock.send('STATUS', 0, { family: net.AF_UNIX, path: '/var/run/hostapd/' + ifname }) != null) {
            let ready = net.poll(1000, sock);
            if (ready?.[0]?.[1]) reply = sock.recv(8192, net.MSG_DONTWAIT);
        }
        fs.unlink(path);
    }
    sock?.close();
    return parse_status(reply, ifname);
};

export function managed_radio_ready(db, requested, ssids, wireless) {
    for (let name, status in wireless || {}) {
        if (!two_ghz(status.config)) continue;
        if (requested.disabled) return status.up === false;
        let interfaces = status.interfaces || [];
        for (let n = 0; n < length(ssids); n++) {
            let matches = filter(interfaces, s => s.section == 'mr3020_ssid' + n && s.ifname);
            if (ssids[n].disabled) {
                for (let item in matches)
                    if (ap_status(db, item.ifname)?.status == 'ENABLED') return false;
                continue;
            }
            if (status.up !== true || length(matches) != 1) return false;
            let ap = ap_status(db, matches[0].ifname);
            if (ap?.status != 'ENABLED' || ap?.ssid != ssids[n].ssid) return false;
        }
        return true;
    }
    return false;
};
