// SPDX-License-Identifier: GPL-2.0-or-later
// Experimental, pure planning only. Never executes shell commands or writes UCI.
function denied_clients(cfg, devname) {
    let denied = {};
    if (cfg['macacl.status'] != 'enabled') return denied;
    for (let key in cfg) {
        let item = match(key, /^macacl\.([0-9]+)\.devname$/);
        if (!item || cfg[key] != devname) continue;
        let group = 'macacl.' + item[1] + '.';
        if (cfg[group + 'status'] != 'enabled' || cfg[group + 'acl.status'] != 'enabled' ||
            cfg[group + 'acl.policy'] != 'deny') continue;
        for (let entry in cfg) {
            let match_entry = match(entry, /^macacl\.([0-9]+)\.acl\.([0-9]+)\.mac$/);
            if (!match_entry || match_entry[1] != item[1] ||
                cfg[group + 'acl.' + match_entry[2] + '.status'] == 'disabled') continue;
            let mac = lc(cfg[entry]);
            if (!match(mac, /^[0-9a-f][02468ace](:[0-9a-f]{2}){5}$/) || mac == '00:00:00:00:00:00')
                die('invalid client MAC in deny ACL');
            denied[mac] = true;
        }
    }
    return denied;
};
export function plan(text, virtual_network_override) {
    if (type(text) != 'string' || length(text) > 65536)
        die('configuration exceeds prototype bounds');
    let cfg = {};
    for (let line in split(text, '\n')) {
        if (!length(line) || substr(line, 0, 1) == '#') continue;
        let pos = index(line, '=');
        if (pos < 1) die('invalid configuration line');
        let key = substr(line, 0, pos);
        if (exists(cfg, key)) die('duplicate configuration key');
        cfg[key] = substr(line, pos + 1);
    }
    let result = [];
    for (let key in cfg) {
        let m = match(key, /^wireless\.([0-9]+)\.ssid$/);
        if (!m) continue;
        if (length(result) >= 2) die('prototype supports at most two SSIDs');
        let id = m[1], w = 'wireless.' + id + '.', a = 'aaa.' + id + '.';
        if (cfg[w + 'parent'] != 'wifi0') die('unsupported radio');
        if (cfg[w + 'usage'] == 'uplink' || cfg[w + 'vwire'] == 'enabled' || cfg[w + 'vport'] == 'enabled')
            die('mesh is unsupported');
        let ssid = cfg[key], password = cfg[a + 'wpa.psk'];
        if (!length(ssid) || length(ssid) > 32) die('invalid SSID');
        if (cfg[a + 'wpa'] != '2' || cfg[a + 'wpa3.support'] == 'enabled' || cfg[a + 'wpa3.transition'] == 'enabled')
            die('only explicit WPA2 personal is supported');
        let pmf = cfg[a + 'pmf.status'] == 'enabled' ? +(cfg[a + 'pmf.mode'] || '1') : 0;
        if (pmf != 0 && pmf != 1 && pmf != 2) die('invalid PMF mode');
        for (let n = 1; n <= 4; n++) {
            let mgmt = cfg[a + 'wpa.key.' + n + '.mgmt'];
            if (mgmt != null && mgmt != 'WPA-PSK') die('unsupported key management');
        }
        if (type(password) != 'string' || length(password) < 8 || length(password) > 63)
            die('invalid WPA2 passphrase');
        let vlan = null;
        for (let bk in cfg) {
            let b = match(bk, /^bridge\.([0-9]+)\.port\.[0-9]+\.devname$/);
            if (!b || cfg[bk] != cfg[w + 'devname']) continue;
            let tag = match(cfg['bridge.' + b[1] + '.devname'] || '', /^br0\.([0-9]+)$/);
            if (!tag && cfg['bridge.' + b[1] + '.devname'] == 'br0') continue;
            if (!tag) die('unsupported bridge assignment');
            let vid = +tag[1];
            if (vid < 1 || vid > 4094 || (vlan != null && vlan != vid)) die('invalid VLAN assignment');
            vlan = vid;
        }
        if (cfg[a + 'wpa.1.pairwise'] != null && cfg[a + 'wpa.1.pairwise'] != 'CCMP') die('only CCMP is supported');
        let wlan_id = cfg[w + 'id'] || cfg[a + 'id'];
        if (wlan_id != null && !match(wlan_id, /^[0-9a-fA-F]{1,64}$/)) die('invalid WLAN identity');
        if (!match(cfg[w + 'devname'] || '', /^[a-zA-Z0-9_-]{1,15}$/)) die('invalid interface identity');
        let client_vlans = {};
        if (virtual_network_override) {
            let prefix = a + 'accept_mac.';
            for (let key in cfg) {
                let entry = match(key, /^aaa\.([0-9]+)\.accept_mac\.([0-9]+)\.(mac|vlanid)$/);
                if (!entry || entry[1] != id || entry[3] != 'mac') continue;
                let mac = lc(cfg[key]), tag = cfg[prefix + entry[2] + '.vlanid'];
                if (!match(mac, /^[0-9a-f][02468ace](:[0-9a-f]{2}){5}$/) || mac == '00:00:00:00:00:00' ||
                    !match(tag || '', /^[1-9][0-9]{0,3}$/) || +tag > 4094 || exists(client_vlans, mac))
                    die('invalid controller client VLAN assignment');
                client_vlans[mac] = +tag;
            }
            for (let key in cfg) {
                let entry = match(key, /^aaa\.([0-9]+)\.accept_mac\.([0-9]+)\.vlanid$/);
                if (entry && entry[1] == id && !exists(cfg, prefix + entry[2] + '.mac'))
                    die('missing MAC for controller client VLAN assignment');
            }
        }
        push(result, { ssid, key: password, encryption: 'psk2+ccmp', vlan, pmf, id: wlan_id, client_vlans,
            devname: cfg[w + 'devname'], denied_clients: denied_clients(cfg, cfg[w + 'devname']),
            hidden: cfg[w + 'hide_ssid'] == 'true' || cfg[w + 'hide_ssid'] == 'enabled',
            isolate: cfg[w + 'l2_isolation'] == 'enabled',
            disabled: cfg[w + 'status'] == 'disabled' || cfg[a + 'status'] == 'disabled' });
    }
    return result;
};

export function radio(text) {
    let cfg = {};
    for (let line in split(text, '\n')) {
        let pos = index(line, '=');
        if (pos > 0) cfg[substr(line, 0, pos)] = substr(line, pos + 1);
    }
    let prefix = null;
    for (let key in cfg) {
        let m = match(key, /^radio\.([0-9]+)\.phyname$/);
        if (!m || cfg[key] != 'wifi0') continue;
        if (prefix != null) die('duplicate physical radio');
        prefix = 'radio.' + m[1] + '.';
    }
    if (prefix == null) die('missing physical radio');
    let channel = cfg[prefix + 'channel'], mode = cfg[prefix + 'ieee_mode'];
    if (channel != 'auto' && !match(channel || '', /^([1-9]|10|11)$/)) die('unsupported 2.4 GHz channel');
    if (mode != '11nght20' && mode != '11nght40') die('unsupported radio mode');
    return { channel, htmode: mode == '11nght20' ? 'HT20' : 'HT40', disabled: cfg[prefix + 'status'] == 'disabled' };
};
