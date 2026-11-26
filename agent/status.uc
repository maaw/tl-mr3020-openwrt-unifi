// SPDX-License-Identifier: GPL-2.0-or-later
import * as fs from 'fs';
import * as ubus from 'bus';
import * as net from 'socket';
import { ap_status, parse_tx_power } from 'radio-status';
function read(name) { return trim(fs.readfile('/sys/class/net/eth0/' + name) || ''); };
const lldp_address = { family: net.AF_PACKET, interface: 'eth0', protocol: 0x88cc,
    address: '01:80:c2:00:00:0e' };
const air_counters = {
    'tx bytes': 'tx_bytes', 'rx bytes': 'rx_bytes', 'tx packets': 'tx_packets',
    'rx packets': 'rx_packets', 'tx retries': 'tx_retries', 'tx failed': 'tx_dropped'
};
function add_air_stats(target, sample) {
    for (let field, key in air_counters)
        if (sample[key] != null) target[key] = (target[key] || 0) + sample[key];
};
function complete_air_stats(stats) {
    if (stats.tx_packets == null || stats.tx_retries == null || stats.tx_dropped == null) return;
    stats.wifi_tx_attempts = stats.tx_packets + stats.tx_retries;
    stats.wifi_tx_dropped = stats.tx_dropped;
    stats.tx_total = stats.tx_packets + stats.tx_dropped;
    if (stats.tx_total + stats.tx_retries > 0)
        stats.tx_retries_pct = +sprintf('%.0f', 100 * stats.tx_retries / (stats.tx_total + stats.tx_retries));
};
export function lldp_socket() {
    let sock = net.create(net.AF_PACKET, net.SOCK_RAW, 0);
    if (sock?.bind(lldp_address)) return sock;
    sock?.close();
};
function lldp_tlv(kind, value) {
    return hexdec(sprintf('%04x', (kind << 9) | length(value))) + value;
};
export function lldp_advertisement(mac, hostname) {
    let hw = hexdec(mac);
    let chassis = join(':', map([0, 2, 4, 6, 8, 10], offset => substr(mac, offset, 2)));
    return hexdec('0180c200000e') + hw + hexdec('88cc')
        + lldp_tlv(1, hexdec('07') + chassis)
        + lldp_tlv(2, hexdec('03') + hw)
        + lldp_tlv(3, hexdec('0078'))
        + lldp_tlv(4, 'eth0') + lldp_tlv(5, hostname)
        + lldp_tlv(7, hexdec('000c000c')) + hexdec('0000');
};
export function lldp_announce(sock, frame) {
    sock?.send(frame, 0, lldp_address);
};
function lldp_id(value, mac_subtype) {
    if (ord(value, 0) == mac_subtype && length(value) == 7)
        return join(':', map([1, 2, 3, 4, 5, 6], i => sprintf('%02x', ord(value, i))));
    let id = substr(value, 1);
    return match(id, /^[A-Za-z0-9_.: -]{1,64}$/) ? id : null;
};
export function parse_lldp(frame) {
    if (length(frame) < 16 || hexenc(substr(frame, 0, 6)) != '0180c200000e' ||
        hexenc(substr(frame, 12, 2)) != '88cc') return null;
    let neighbor = { local_port_name: 'eth0', local_port_idx: 1, is_wired: true };
    let ttl, offset = 14;
    while (offset + 2 <= length(frame)) {
        let header = ord(frame, offset) * 256 + ord(frame, offset + 1);
        let kind = header >> 9, size = header & 511;
        offset += 2;
        if (offset + size > length(frame)) return null;
        if (kind == 0)
            return size == 0 && neighbor.chassis_id && neighbor.port_id && ttl != null
                ? { neighbor, ttl } : null;
        let value = substr(frame, offset, size);
        offset += size;
        if (kind == 1 && size > 1) {
            neighbor.chassis_id = lldp_id(value, 4);
            if (ord(value, 0) == 7) neighbor.chassis_id_subtype = 'local';
            else if (ord(value, 0) == 4) neighbor.chassis_id_subtype = 'mac';
        }
        if (kind == 2 && size > 1) neighbor.port_id = lldp_id(value, 3);
        if (kind == 3 && size == 2) ttl = ord(value, 0) * 256 + ord(value, 1);
        if (kind == 4 && match(value, /^[A-Za-z0-9_.: -]{1,64}$/)) neighbor.port_descr = value;
    }
    return null;
};
export function lldp_read(sock, cached, uptime) {
    for (let i = 0; i < 8 && sock; i++) {
        let packet = sock.recv(1600, net.MSG_DONTWAIT);
        if (!packet) break;
        let entry = parse_lldp(packet);
        if (entry) cached = { neighbor: entry.neighbor, expires: uptime + entry.ttl };
    }
    return cached?.expires > uptime ? cached : null;
};
export function system_usage(previous, uptime) {
    let sample = split((fs.readfile('/proc/stat') || ''), '\n')[0];
    let values = map(slice(split(trim(replace(sample, / +/g, ' ')), ' '), 1, 9), n => +n);
    let total = 0;
    for (let value in values) total += value;
    let idle = (values[3] || 0) + (values[4] || 0);
    let delta = total - (previous?.total || 0), idle_delta = idle - (previous?.idle || 0);
    let cpu = previous && delta > 0 && idle_delta >= 0 && idle_delta <= delta
        ? sprintf('%.1f', 100 * (delta - idle_delta) / delta) : '0';
    let mem = fs.readfile('/proc/meminfo') || '';
    let capacity = +(match(mem, /MemTotal:[ \t]+([0-9]+)/)?.[1] || 0);
    let available = +(match(mem, /MemAvailable:[ \t]+([0-9]+)/)?.[1] || capacity);
    return { sample: { total, idle }, report: {
        cpu, mem: capacity && available <= capacity ? sprintf('%.1f', 100 * (capacity - available) / capacity) : '0',
        uptime: '' + uptime
    } };
};
export function parse_stations(output, channel, clients) {
    let stations = [], sta;
    for (let line in split(output || '', '\n')) {
        let station = match(line, /^Station ([0-9a-f:]{17}) /);
        if (station) {
            sta = { active: true, mac: station[1], channel, radio: 'ng' };
            push(stations, sta);
            continue;
        }
        if (!sta) continue;
        let field = trim(line);
        if (field == 'authorized:\tyes') sta.authorized = true;
        let counter = match(field, /^(rx bytes|tx bytes|rx packets|tx packets|tx retries|tx failed):[ \t]+([0-9]+)$/);
        if (counter) sta[air_counters[counter[1]]] = +counter[2];
        let signal = match(field, /^signal:[ \t]+(-[0-9]+)([ \t]|$)/);
        if (signal) sta.signal = +signal[1];
        let rate = match(field, /^(tx|rx) bitrate:[ \t]+([0-9]+([.][0-9]+)?) MBit\/s(.*)$/);
        if (!rate) continue;
        sta[rate[1] + '_rate'] = +sprintf('%.0f', +rate[2] * 1000);
        let ht = match(rate[4], /(^|[ \t])MCS[ \t]+([0-9]+)([ \t]|$)/);
        if (ht) sta[rate[1] + '_mcs'] = +ht[2];
    }
    for (let sta in stations) {
        complete_air_stats(sta);
        if (clients?.[sta.mac]?.ht || sta.tx_mcs != null || sta.rx_mcs != null) {
            sta.is_11n = true;
            sta.radio_proto = 'n';
            sta.nss = 1;
        }
    }
    return stations;
};
export function missing_stations(stations, clients) {
    let reported = {};
    for (let sta in stations) reported[sta.mac] = true;
    return filter(keys(clients || {}), mac => !reported[mac] && clients[mac].authorized &&
        match(mac, /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/));
};
export function experience(stations) {
    let total = 0, count = 0;
    for (let sta in stations) {
        if (!sta.authorized || sta.signal == null) continue;
        // UniFi labels signals above -60 dBm excellent and below -80 poor.
        // Report a signal-based estimate for this driver, which cannot
        // provide all the inputs used by UniFi firmware's score.
        sta.satisfaction = +sprintf('%.0f', min(100, max(0, (sta.signal + 100) * 2.5)));
        total += sta.satisfaction;
        count++;
    }
    return { total, count };
};
export function collect(state, include_stations) {
    let speed = +read('speed'), up = read('carrier') == '1';
    let out = { speed: up && speed > 0 ? speed : 0, up, full_duplex: up && read('duplex') == 'full', vaps: [] };
    let db = ubus.connect();
    if (!db) return out;
    out.ip = db.call('network.interface.lan', 'status', {})?.['ipv4-address']?.[0]?.address;
    let wireless = db.call('network.wireless', 'status', {});
    let score_total = 0, scored_clients = 0, air_stats = {};
    for (let name, r in wireless || {}) {
        for (let i in r.interfaces || []) {
            let m = match(i.section || '', /^mr3020_ssid([01])$/), s = m ? state.report?.ssids?.[+m[1]] : null;
            if (!s || !match(i.ifname || '', /^[a-zA-Z0-9_.-]{1,15}$/)) continue;
            let ap = ap_status(db, i.ifname);
            if (!ap) continue;
            let enabled = ap.status == 'ENABLED';
            if (enabled) {
                out.channel = ap.channel;
                if (out.tx_power == null) {
                    let info = fs.popen('/usr/sbin/iw dev ' + i.ifname + ' info');
                    if (info) {
                        out.tx_power = parse_tx_power(info.read('all'));
                        info.close();
                    }
                }
            }
            let stations = [], cmd = include_stations && enabled ? fs.popen('/usr/sbin/iw dev ' + i.ifname + ' station dump') : null;
            if (cmd) {
                let clients = db.call('hostapd.' + i.ifname, 'get_clients', {})?.clients;
                stations = parse_stations(cmd.read('all'), ap.channel, clients);
                cmd.close();
                // Legacy mac80211 dumps each VLAN separately. A lookup by MAC
                // on the parent BSS still sees its stations on AP/VLANs.
                for (let mac in missing_stations(stations, clients)) {
                    let lookup = fs.popen('/usr/sbin/iw dev ' + i.ifname + ' station get ' + mac + ' 2>/dev/null');
                    if (!lookup) continue;
                    let sta = parse_stations(lookup.read('all'), ap.channel, clients)[0];
                    lookup.close();
                    if (sta?.mac == mac && sta.authorized) push(stations, sta);
                }
            }
            push(out.vaps, { name: s.devname || i.ifname, radio: 'ng', radio_name: 'wifi0',
                id: s.id, wlanconf_id: s.id, essid: s.ssid, bssid: ap.bssid,
                channel: ap.channel, up: enabled, state: enabled ? 'RUN' : 'INIT',
                disabled: s.disabled, usage: 'user', is_guest: false });
            if (include_stations) {
                let vap = out.vaps[length(out.vaps) - 1];
                vap.sta_table = stations;
                vap.num_sta = length(stations);
                for (let sta in stations) add_air_stats(vap, sta);
                add_air_stats(air_stats, vap);
                complete_air_stats(vap);
                let score = experience(stations);
                if (score.count) vap.satisfaction = +sprintf('%.0f', score.total / score.count);
                score_total += score.total;
                scored_clients += score.count;
            }
        }
    }
    db.disconnect();
    complete_air_stats(air_stats);
    out.air_stats = air_stats;
    if (scored_clients) out.satisfaction = +sprintf('%.0f', score_total / scored_clients);
    return out;
};
