import * as inform from 'inform';
import { readfile } from 'fs';
let mac = '02:30:20:00:00:01';
let factory = 'ba86f2bbe107c7c57eb5f2690775c712';
let payload = {
    mac, serial: '023020000001', model: 'U7PG2', type: 'uap',
    model_display: 'UniFi AP-AC-Pro', display_name: 'MR3020 ucode test',
    version: '6.8.2.15592', board_rev: 0,
    ip: host_ip, netmask: '255.255.255.0', gateway_ip: controller_ip,
    hostname: 'mr3020-ucode-test', inform_url: 'http://' + controller_ip + ':8080/inform',
    inform_ip: controller_ip, uptime: 60, time: time(), cfgversion: '0',
    state: 1, default: true, _default_key: true, x_authkey: factory,
    isolated: false, locating: false, selfrun_beacon: true, fw_caps: 3,
    sshd_port: 2222, inform_min_interval: 1, uplink: 'eth0', has_eth1: false,
    if_table: [{ name: 'eth0', mac, ip: host_ip, netmask: '255.255.255.0', up: true }],
    radio_table: [{ name: 'wifi0', radio: 'ng', channel: 1, ht: '20',
        min_txpower: 0, max_txpower: 20, nss: 1, tx_power: 10,
        radio_caps: 0, antenna_gain: 0, builtin_antenna: true, builtin_ant_gain: 0 }],
    vap_table: []
};
let packet = inform.encode(hexdec(replace(mac, ':', '')), hexdec(factory), sprintf('%J', payload), false);
if (packet == null) die('encoding failed');
print(packet);
