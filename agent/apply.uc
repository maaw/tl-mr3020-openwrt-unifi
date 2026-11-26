// SPDX-License-Identifier: GPL-2.0-or-later
// Owns only mr3020_* network/wireless sections and the single 2.4 GHz radio.
import * as fs from 'fs';
import * as uci from 'uci';
import { plan, radio } from 'planner';
import { sync_fd } from 'inform';
import { two_ghz } from 'radio-status';
function write_private(path, data) {
    let f = fs.open(path, 'w', 384);
    if (!f || f.write(data) != length(data) || !f.flush() || !sync_fd(f.fileno())) die('configuration write failed');
    f.close();
    fs.chmod(path, 384);
};
function cursor(dir) { return uci.cursor(dir, dir + '/.save'); };
function check_dir(dir) {
    let d = fs.lstat(dir);
    if (!d || d.type != 'directory' || (d.mode & 18) != 0) die('unsafe configuration directory');
    for (let name in ['network', 'wireless']) {
        let f = fs.lstat(dir + '/' + name);
        if (!f || f.type != 'file' || f.size > 65536) die('unsafe configuration file');
    }
};
export function recover(dir, journal, activate) {
    if (!fs.lstat(journal)) return false;
    let info = fs.lstat(journal);
    if (info.type != 'file' || (info.mode & 63) != 0 || info.size > 140000) die('unsafe rollback journal');
    let before = json(fs.readfile(journal));
    if (type(before.network) != 'string' || type(before.wireless) != 'string') die('invalid rollback journal');
    for (let name in ['network', 'wireless']) write_private(dir + '/' + name, before[name]);
    for (let name in ['network', 'wireless']) fs.unlink(dir + '/.save/' + name);
    if (!activate()) die('rollback reload failed');
    if (!fs.unlink(journal)) die('cannot clear rollback journal');
    return true;
};
export function attach_client_vlans(dir) {
    let c = cursor(dir), ready = true;
    c.foreach('wireless', 'wifi-iface', s => {
        if (!match(s['.name'], /^mr3020_ssid[01]$/) || s.disabled == '1') return;
        for (let entry in s.mr3020_client_vlans || []) {
            let m = match(entry, /^[0-9a-f:]{17},([0-9]{1,4}),(mrv[01]_[0-9]{1,4})$/);
            if (!m || m[2] != 'mrv' + substr(s['.name'], -1) + '_' + m[1] || +m[1] < 2 || +m[1] > 4094) {
                ready = false;
                continue;
            }
            let bridge = 'br-mr3020_v' + m[1], port = m[2];
            let members = '/sys/class/net/' + bridge + '/brif/';
            if (!fs.lstat(members + 'eth0.' + m[1]) || !fs.lstat('/sys/class/net/' + port)) {
                ready = false;
                continue;
            }
            // Legacy netifd can see a new AP VLAN without adding it to the bridge.
            if (!fs.lstat(members + port))
                system('/usr/sbin/brctl addif ' + bridge + ' ' + port);
            if (!fs.lstat(members + port)) ready = false;
        }
    });
    return ready;
};
export function apply(text, dir, journal, activate, healthy, client_vlans, virtual_network_override) {
    let ssids = plan(text, virtual_network_override), r = radio(text);
    if (client_vlans != null && type(client_vlans) != 'object') die('invalid per-client VLAN configuration');
    check_dir(dir);
    if (fs.lstat(journal)) die('unfinished transaction requires recovery');
    let c = cursor(dir), physical = [];
    c.foreach('wireless', 'wifi-device', s => { if (two_ghz(s)) push(physical, s['.name']); });
    if (length(physical) != 1) die('expected exactly one existing 2.4 GHz radio');
    let name = physical[0];
    let factory_interface = null;
    c.foreach('wireless', 'wifi-iface', s => {
        if (s.device != name || match(s['.name'], /^mr3020_/) || s.disabled == '1') return;
        if (s['.name'] == 'default_radio0' && s.ssid == 'OpenWrt' && s.encryption == 'none') factory_interface = s['.name'];
        else die('unmanaged Wi-Fi interface would be enabled');
    });
    let protected = { lan: c.get_all('network', 'lan'), rescue: c.get_all('network', 'rescue'), bridges: [] };
    c.foreach('network', 'device', s => { if (s.name == 'br-lan') push(protected.bridges, s); });
    let legacy = protected.lan?.type == 'bridge' && protected.lan?.ifname == 'eth0' && !protected.lan?.device;
    if (!protected.lan || !protected.rescue || (legacy ? length(protected.bridges) != 0 : length(protected.bridges) != 1))
        die('management recovery configuration missing');
    let before = { network: fs.readfile(dir + '/network'), wireless: fs.readfile(dir + '/wireless') };
    write_private(journal, sprintf('%J', before));
    let journal_dir = fs.open(fs.dirname(journal), 'r');
    if (!journal_dir || !sync_fd(journal_dir.fileno())) die('cannot synchronize rollback journal');
    journal_dir.close();
    let stage = 'prepare';
    try {
        // No evaluation of controller strings or shell interpolation.
        for (let package in ['network', 'wireless']) {
            let remove = [];
            c.foreach(package, null, s => { if (match(s['.name'], /^mr3020_/)) push(remove, s['.name']); });
            for (let section in remove) c.delete(package, section);
        }
        if (factory_interface != null) c.set('wireless', factory_interface, 'disabled', '1');
        c.set('wireless', name, 'disabled', r.disabled ? '1' : '0');
        c.set('wireless', name, 'channel', r.channel);
        c.set('wireless', name, 'htmode', r.htmode);
        // Country is a local installation setting; controller cannot override it.
        let vlans = {};
        function vlan_network(vid) {
            // Legacy netifd prefixes bridge names with br- (IFNAMSIZ=16).
            let network = (legacy ? 'mr3020_v' : 'mr3020_vlan') + vid;
            if (vlans[vid]) return network;
            c.set('network', network, 'interface');
            c.set('network', network, 'proto', 'none');
            if (legacy) {
                c.set('network', network, 'type', 'bridge');
                c.set('network', network, 'ifname', 'eth0.' + vid);
            } else {
                let tag = 'mr3020_tag' + vid, bridge = 'mr3020_bridge' + vid;
                c.set('network', tag, 'device');
                for (let k, v in { type: '8021q', ifname: 'eth0', vid: '' + vid, name: 'eth0.' + vid }) c.set('network', tag, k, v);
                c.set('network', bridge, 'device');
                for (let k, v in { type: 'bridge', name: 'br-mr' + vid, ports: ['eth0.' + vid] }) c.set('network', bridge, k, v);
                c.set('network', network, 'device', 'br-mr' + vid);
            }
            vlans[vid] = true;
            return network;
        }
        for (let n = 0; n < length(ssids); n++) {
            let s = ssids[n], network = s.vlan == null ? 'lan' : vlan_network(s.vlan);
            let section = 'mr3020_ssid' + n;
            c.set('wireless', section, 'wifi-iface');
            for (let k, v in { device: name, mode: 'ap', network, ssid: s.ssid, key: s.key,
                encryption: s.encryption, ieee80211w: '' + s.pmf, hidden: s.hidden ? '1' : '0',
                isolate: s.isolate ? '1' : '0', disabled: s.disabled ? '1' : '0' }) c.set('wireless', section, k, v);
            let entries = client_vlans?.[s.ssid];
            let denied = keys(s.denied_clients);
            if (length(denied)) {
                c.set('wireless', section, 'macfilter', 'deny');
                c.set('wireless', section, 'maclist', denied);
            }
            if (s.disabled) continue;
            if (length(keys(s.client_vlans))) {
                if (entries != null) die('local and controller client VLANs overlap this SSID');
                entries = s.client_vlans;
            }
            if (entries == null) continue;
            if (!legacy || s.vlan != null || s.isolate || length(filter(ssids, item => item.ssid == s.ssid)) != 1 ||
                type(entries) != 'object' || length(keys(entries)) > 32)
                die('unsupported per-client VLAN configuration');
            let clients = [], interfaces = {};
            for (let mac, vid in entries) {
                if (!match(mac, /^[0-9a-f][02468ace](:[0-9a-f]{2}){5}$/) || mac == '00:00:00:00:00:00' ||
                    type(vid) != 'int' || vid < 1 || vid > 4094)
                    die('invalid client VLAN assignment');
                // hostapd checks a MAC in the VLAN accept file before its deny file.
                if (vid == 1 || s.denied_clients[mac]) continue;
                let port = 'mrv' + n + '_' + vid;
                if (!interfaces[vid]) {
                    let bridge = vlan_network(vid);
                    c.set('network', bridge, 'ifname', c.get('network', bridge, 'ifname') + ' ' + port);
                    interfaces[vid] = port;
                }
                push(clients, mac + ',' + vid + ',' + port);
            }
            if (length(clients)) c.set('wireless', section, 'mr3020_client_vlans', clients);

        }
        stage = 'commit';
        if (!c.commit('network') || !c.commit('wireless')) die('configuration commit failed');
        stage = 'read-back';
        c = cursor(dir);
        let after = { lan: c.get_all('network', 'lan'), rescue: c.get_all('network', 'rescue'), bridges: [] };
        c.foreach('network', 'device', s => { if (s.name == 'br-lan') push(after.bridges, s); });
        if (sprintf('%J', protected) != sprintf('%J', after)) die('management configuration changed');
        for (let n = 0; n < length(ssids); n++) {
            let section = 'mr3020_ssid' + n;
            if (c.get('wireless', section, 'key') != ssids[n].key || c.get('wireless', section, 'ssid') != ssids[n].ssid)
                die('wireless configuration read-back failed');
        }
        stage = 'reload';
        if (!activate()) die('configuration reload failed');
        stage = 'health-check';
        if (!healthy(r, ssids)) die('configuration health check failed');
        if (!fs.unlink(journal)) die('cannot finish configuration transaction');
        return { radio: r, ssids: map(ssids, s => ({ ssid: s.ssid, vlan: s.vlan, disabled: s.disabled, pmf: s.pmf, id: s.id, devname: s.devname })) };
    } catch (e) {
        recover(dir, journal, activate);
        die('configuration rejected and rolled back at ' + stage);
    }
};
