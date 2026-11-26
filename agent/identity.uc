// SPDX-License-Identifier: GPL-2.0-or-later
import { FACTORY_KEY } from 'session';
export function device_model(profile) {
    return profile.model == 'U7LT'
        ? { code: 'U7LT', display: 'UniFi AP-AC-Lite' }
        : { code: 'U7PG2', display: 'UniFi AP-AC-Pro' };
};
export function pending(profile, state) {
    let parts = [];
    for (let n = 0; n < 12; n += 2) push(parts, substr(profile.mac, n, 2));
    let mac = join(':', parts);
    let model = device_model(profile), tx_power = profile.live?.tx_power;
    let power = tx_power == null ? {} : { tx_power };
    return {
        mac, serial: uc(profile.mac), model: model.code, type: 'uap',
        model_display: model.display, version: '6.8.2.15592', board_rev: 0,
        ip: profile.ip, netmask: '255.255.255.0', gateway_ip: profile.controller,
        hostname: profile.hostname, inform_ip: profile.controller,
        inform_url: 'http://' + profile.controller + ':' + profile.port + '/inform',
        uptime: profile.uptime || 0, time: time(), cfgversion: state.cfgversion,
        state: state.phase == 'pending' ? 1 : 4,
        default: state.key == FACTORY_KEY, _default_key: state.key == FACTORY_KEY,
        x_authkey: state.key, x_aes_gcm: state.gcm, isolated: false, locating: false, fw_caps: profile.virtual_network_override === true ? 3 - 2147483648 : 3,
        wifi_caps: profile.lock_to_ap === true ? 0x1000000 : 0,
        sshd_port: 2222, inform_min_interval: 1, uplink: 'eth0', has_eth1: false,
        if_table: [{ name: 'eth0', mac, ip: profile.ip, up: profile.live?.up !== false,
            speed: profile.live?.speed || 0, full_duplex: profile.live?.full_duplex || false }],
        port_table: [{ port_idx: 1, name: 'eth0', up: profile.live?.up !== false, enable: true,
            speed: profile.live?.speed || 0, full_duplex: profile.live?.full_duplex || false, is_uplink: true, media: 'FE', port_poe: false }],
        radio_table: [{ name: 'wifi0', radio: 'ng', channel: profile.live?.channel || state.report?.radio?.channel || 1,
            ht: state.report?.radio?.htmode == 'HT40' ? '40' : '20', nss: 1,
            // UniFi renders 1x1 from this capability bit, separately from nss.
            min_txpower: 0, max_txpower: 20, radio_caps: 0x8,
            ...power,
            antenna_gain: 0, builtin_antenna: true, builtin_ant_gain: 0 }],
        radio_table_stats: profile.live?.channel == null ? [] :
            [{ name: 'wifi0', channel: profile.live.channel, ...power, ...(profile.live.air_stats || {}) }],
        'system-stats': profile.live?.system_stats,
        lldp_table: profile.live?.lldp ? [profile.live.lldp] : [],
        ...(profile.live?.satisfaction == null ? {} : { satisfaction: profile.live.satisfaction }),
        vap_table: map(profile.live?.vaps || [], vap => vap.up ? { ...vap, ...power } : vap)
    };
};
