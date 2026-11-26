import { parse_status, parse_tx_power, two_ghz } from 'radio-status';
import { experience, lldp_advertisement, lldp_read, missing_stations, parse_lldp, parse_stations } from 'status';
let n = 0;
function check(v) { if (!v) die('legacy status assertion failed'); n++; }
check(two_ghz({ hwmode: '11g' }));
check(two_ghz({ band: '2g' }));
check(!two_ghz({ hwmode: '11a' }));
let status = parse_status('state=ENABLED\nfreq=2437\nbssid[0]=02:30:20:00:00:02\nssid[0]=IoT = test\n');
check(status.status == 'ENABLED' && status.channel == 6 && status.ssid == 'IoT = test');
check(parse_status('state=ENABLED\nfreq=5180\nbssid[0]=02:30:20:00:00:02\nssid[0]=IoT\n') == null);
check(parse_status('FAIL\n') == null);
let multiple = 'state=ENABLED\nfreq=2437\nbss[0]=wlan0\nbssid[0]=02:30:20:00:00:02\nssid[0]=First\nbss[1]=wlan0-1\nbssid[1]=02:30:20:00:00:03\nssid[1]=Second\n';
check(parse_status(multiple, 'wlan0-1').ssid == 'Second');
check(parse_status(multiple, 'absent') == null);
check(parse_status(replace(multiple, 'freq=2437', 'freq=2472'), 'wlan0').channel == 13);
check(parse_tx_power('Interface wlan0\n\tchannel 13 (2472 MHz), width: 20 MHz\n\ttxpower 17.00 dBm\n') === 17);
check(parse_tx_power('\ttxpower 0.00 dBm\n') === 0);
check(parse_tx_power('\ttxpower -2.50 dBm\n') === -2);
check(parse_tx_power('Interface wlan0\n') == null);
let stations = parse_stations('Station 02:30:20:00:00:01 (on wlan0)\n\tsignal: \t-22 [-22] dBm\n\tsignal avg: \t-21 [-21] dBm\n\ttx bitrate:\t65.0 MBit/s MCS 7\n\trx bitrate:\t1.0 MBit/s\n\tauthorized:\tyes\nStation 02:30:20:00:00:02 (on wlan0)\n\trx bitrate:\t54.0 MBit/s\n', 13);
check(length(stations) == 2 && stations[0].channel == 13 && stations[0].authorized);
check(stations[0].signal == -22 && stations[0].is_11n && stations[0].nss == 1 && stations[0].tx_mcs == 7);
check(stations[0].tx_rate == 65000 && stations[0].rx_rate == 1000 && stations[0].rx_mcs == null);
check(stations[1].rx_rate == 54000 && stations[1].signal == null && stations[1].is_11n == null);
stations = parse_stations('Station 02:30:20:00:00:02 (on wlan0)\n\trx bitrate:\t1.0 MBit/s\n', 13, { '02:30:20:00:00:02': { ht: true } });
check(stations[0].is_11n && stations[0].rx_rate == 1000 && stations[0].rx_mcs == null);
let missing = missing_stations(stations, {
    '02:30:20:00:00:01': { authorized: true },
    '02:30:20:00:00:02': { authorized: true },
    '02:30:20:00:00:03': { authorized: false },
    'not-a-mac': { authorized: true }
});
check(length(missing) == 1 && missing[0] == '02:30:20:00:00:01');
check(length(missing_stations(stations, null)) == 0);
let samples = [{ authorized: true, signal: -37 }, { authorized: true, signal: -88 },
    { authorized: true }, { authorized: false, signal: -55 }];
let score = experience(samples);
check(score.count == 2 && score.total == 130);
check(samples[0].satisfaction == 100 && samples[1].satisfaction == 30);
check(samples[2].satisfaction == null && experience([]).count == 0);
let air = parse_stations('Station 02:30:20:00:00:01 (on wlan0)\n\trx bytes:\t86023\n\ttx bytes:\t10179\n\trx packets:\t1265\n\ttx packets:\t91\n\ttx retries:\t4\n\ttx failed:\t2\n', 13)[0];
check(air.rx_bytes == 86023 && air.tx_bytes == 10179 && air.rx_packets == 1265);
check(air.wifi_tx_attempts == 95 && air.tx_total == 93 && air.wifi_tx_dropped == 2 && air.tx_retries_pct == 4);
let lldp = hexdec('0180c200000e1c0b8be8663588cc02120731633a30623a38623a65383a36363a33330407031c0b8be86635060200780804657468320000');
let peer = parse_lldp(lldp);
check(peer.neighbor.chassis_id == '1c:0b:8b:e8:66:33' && peer.neighbor.port_id == '1c:0b:8b:e8:66:35');
check(peer.neighbor.port_descr == 'eth2' && peer.neighbor.local_port_idx == 1 && peer.ttl == 120);
check(parse_lldp(substr(lldp, 0, -1)) == null && parse_lldp('') == null);
let packets = [lldp];
let cached = lldp_read({ recv: () => pop(packets) }, null, 30);
check(cached.expires == 150 && lldp_read(null, cached, 150) == null);
let announcement = lldp_advertisement('023020000001', 'mr3020-test');
let advertised = parse_lldp(announcement);
check(advertised.ttl == 120 && advertised.neighbor.chassis_id == '02:30:20:00:00:01');
check(advertised.neighbor.port_id == advertised.neighbor.chassis_id && advertised.neighbor.port_descr == 'eth0');
print({ legacy_status_checks_passed: n });
