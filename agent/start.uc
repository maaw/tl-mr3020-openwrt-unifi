// SPDX-License-Identifier: GPL-2.0-or-later
import * as fs from 'fs';
import * as ubus from 'bus';
import { ipv4 } from 'transport';
let profile = json(fs.readfile('/etc/mr3020.json'));
if (profile.enabled !== true || !ipv4(profile.controller)) exit(1);
let ip, mac;
// Wait without a crash loop when Ethernet/DHCP is slower than service startup.
while (true) {
    let db = ubus.connect();
    let lan = db?.call('network.interface.lan', 'status', {});
    db?.disconnect();
    ip = lan?.['ipv4-address']?.[0]?.address;
    mac = lc(replace(trim(fs.readfile('/sys/class/net/eth0/address') || ''), ':', ''));
    if (ipv4(ip) && match(mac, /^[0-9a-f]{12}$/)) break;
    sleep(2000);
}
// Fixed local paths and device identity; never copied from the synthetic lab profile.
profile = { enabled: true, controller: profile.controller, allow_adoption: profile.allow_adoption === true,
    mac, ip, model: profile.model, client_vlans: profile.client_vlans, hostname: 'mr3020', port: 8080, daemon: true, state_dir: '/etc/mr3020-state',
    virtual_network_override: profile.virtual_network_override === true && !!fs.lstat('/lib/netifd/hostapd.sh') &&
        index(fs.readfile('/lib/netifd/hostapd.sh') || '', 'config_add_array mr3020_client_vlans') >= 0,
    lock_to_ap: profile.lock_to_ap === true,
    adoption_file: '/var/run/mr3020-adopt/request.json', adoption_uid: 453,
    apply_mode: 'hardware', config_dir: '/etc/config' };
include('/usr/lib/mr3020/runner.uc', { profile });
