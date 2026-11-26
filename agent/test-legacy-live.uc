// VM-only integration check. Never included by the firmware staging script.
import * as fs from 'fs';
import * as bus from 'bus';
import * as uci from 'uci';
import { apply } from 'apply';
import { ap_status } from 'radio-status';
if (!match(fs.readfile('/proc/cpuinfo') || '', /MIPS Malta/)) die('Malta test VM required');
// hwsim advertises both bands; old autodetection defaults to 5 GHz. The real
// MR3020 has only 2.4 GHz. Constrain this simulator fixture explicitly.
let c = uci.cursor();
c.set('wireless', 'radio0', 'hwmode', '11g'); c.commit('wireless');
let n = 0;
function check(v) { if (!v) die('live legacy assertion failed'); n++; }
function reload() {
    let db = bus.connect();
    db.call('network', 'reload', {});
    let error = bus.error();
    db.disconnect();
    return error == null && system('/sbin/wifi reload') == 0;
}
function healthy(r, ssids) {
    for (let attempt = 0; attempt < 60; attempt++) {
        let db = bus.connect(), good = true;
        let wireless = db.call('network.wireless', 'status', {});
        let interfaces = wireless?.radio0?.interfaces || [];
        for (let index = 0; index < length(ssids); index++) {
            let found = filter(interfaces, item => item.section == 'mr3020_ssid' + index);
            let ap = length(found) == 1 ? ap_status(db, found[0].ifname) : null;
            if (ap?.status != 'ENABLED' || ap?.ssid != ssids[index].ssid || ap?.channel != +r.channel) good = false;
        }
        let lan = db.call('network.interface.lan', 'status', {}), rescue = db.call('network.interface.rescue', 'status', {});
        db.disconnect();
        if (good && lan?.up && rescue?.up) return true;
        sleep(250);
    }
    return false;
}
let cfg = 'radio.1.phyname=wifi0\nradio.1.channel=6\nradio.1.ieee_mode=11nght20\n';
for (let index = 1; index <= 2; index++) {
    let w = 'wireless.' + index + '.', a = 'aaa.' + index + '.';
    cfg += w + 'ssid=MR3020 simulation ' + index + '\n' + w + 'parent=wifi0\n' + w + 'devname=ath' + (index - 1) + '\n';
    cfg += a + 'wpa=2\n' + a + 'wpa.psk=simulation-only-password\n' + a + 'wpa.key.1.mgmt=WPA-PSK\n';
    if (index == 1) cfg += a + 'pmf.status=enabled\n' + a + 'pmf.mode=1\nbridge.2.devname=br0.2\nbridge.2.port.1.devname=ath0\n';
}
fs.mkdir('/tmp/mr3020-live', 448);
let result = apply(cfg, '/etc/config', '/tmp/mr3020-live/rollback.json', reload, healthy);
check(length(result.ssids) == 2);
check(fs.lstat('/sys/class/net/eth0.2') != null);
check(healthy(result.radio, result.ssids));
let saved = fs.readfile('/etc/config/network'), rejected = false;
try { apply(replace(cfg, 'channel=6', 'channel=11'), '/etc/config', '/tmp/mr3020-live/rollback.json', reload, () => false); }
catch(e) { rejected = true; }
check(rejected && fs.readfile('/etc/config/network') == saved && !fs.lstat('/tmp/mr3020-live/rollback.json'));
check(healthy(result.radio, result.ssids));
print({ live_legacy_checks_passed: n, ssids: 2, channel: 6, vlan_interface: 'eth0.2', rollback: true, physical_radio_tested: false });
