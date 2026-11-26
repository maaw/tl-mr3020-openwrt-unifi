import * as fs from 'fs';
import * as uci from 'uci';
import { apply } from 'apply';
let dir = test_dir + '/config', journal = test_dir + '/rollback.json', n = 0;
function check(v) { if (!v) die('legacy apply assertion failed'); n++; }
fs.mkdir(dir, 448); fs.mkdir(dir + '/.save', 448);
let network = "config interface 'lan'\n option type 'bridge'\n option ifname 'eth0'\n option proto 'dhcp'\nconfig interface 'rescue'\n option ifname 'br-lan'\n option proto 'static'\n option ipaddr '169.254.30.20'\n option netmask '255.255.0.0'\n";
fs.writefile(dir + '/network', network);
fs.writefile(dir + '/wireless', "config wifi-device 'radio0'\n option type 'mac80211'\n option hwmode '11g'\n option country 'AR'\n option disabled '1'\n");
let cfg = 'radio.1.phyname=wifi0\nradio.1.channel=6\nradio.1.ieee_mode=11nght20\nwireless.1.ssid=IoT\nwireless.1.parent=wifi0\nwireless.1.devname=ath0\naaa.1.wpa=2\naaa.1.wpa.psk=test-passphrase\naaa.1.wpa.key.1.mgmt=WPA-PSK\nbridge.2.devname=br0.2\nbridge.2.port.1.devname=ath0\n';
let result = apply(cfg, dir, journal, () => true, () => true);
let c = uci.cursor(dir, dir + '/.save');
check(result.ssids[0].vlan == 2);
check(c.get('network', 'mr3020_v2', 'type') == 'bridge');
check(c.get('network', 'mr3020_v2', 'ifname') == 'eth0.2');
check(c.get('network', 'mr3020_v2', 'device') == null);
check(c.get('network', 'lan', 'ifname') == 'eth0');
check(c.get('network', 'rescue', 'ifname') == 'br-lan');
check(c.get('wireless', 'radio0', 'hwmode') == '11g');
check(c.get('wireless', 'mr3020_ssid0', 'network') == 'mr3020_v2');
apply(replace(cfg, 'br0.2', 'br0.4094'), dir, journal, () => true, () => true);
c = uci.cursor(dir, dir + '/.save');
check(c.get('network', 'mr3020_v4094', 'ifname') == 'eth0.4094');
check(length('br-mr3020_v4094') <= 15);
let saved = fs.readfile(dir + '/network'), rejected = false;
try { apply(replace(cfg, 'channel=6', 'channel=11'), dir, journal, () => true, () => false); } catch(e) { rejected = true; }
check(rejected && fs.readfile(dir + '/network') == saved && !fs.lstat(journal));
print({ legacy_apply_checks_passed: n });
