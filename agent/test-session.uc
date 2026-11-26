import { initial, step, FACTORY_KEY } from 'session';
import { pending } from 'identity';
import { build } from 'discovery-wire';
let checks = 0;
function check(v) { if (!v) die('session assertion failed'); checks++; }
let s = initial(), key = '00112233445566778899aabbccddeeff';
check(step(s, { _type: 'noop', interval: 5 }, false).state.interval == 5);
check(step(s, { _type: 'setparam', mgmt_cfg: 'authkey=' + key }, false).event == 'adoption-disabled');
let keyed = step(s, { _type: 'setparam', mgmt_cfg: 'authkey=' + key + '\nuse_aes_gcm=true\ncfgversion=123' }, true).state;
check(keyed.key == key && keyed.gcm && keyed.phase == 'keyed');
check(s.key == FACTORY_KEY);
check(keyed.cfgversion == '0');
check(step(keyed, { _type: 'upgrade', url: 'http://invalid/' }, true).event == 'ignored');
check(step(keyed, { _type: 'cmd', cmd: 'run', shellcmd: 'false' }, true).event == 'ignored');
check(step(keyed, { _type: 'setparam', system_cfg: 'test=value', cfgversion: '123' }, true).state.cfgversion == '0');
let threw = false;
try { step(keyed, { _type: 'setparam', mgmt_cfg: 'authkey=ffffffffffffffffffffffffffffffff' }, true); } catch (e) { threw = true; }
check(threw);
threw = false;
try { step(s, { _type: 'noop', interval: 0 }, false); } catch (e) { threw = true; }
check(threw);
let p = pending({ mac: '023020000001', ip: '192.0.2.10', hostname: 'test', controller: '192.0.2.1', port: 8080 }, s);
check(p.mac == '02:30:20:00:00:01');
check(p._default_key && p.cfgversion == '0');
check(p.model == 'U7PG2');
let lite = { mac: '023020000003', ip: '192.0.2.11', hostname: 'test', model: 'U7LT' };
let inform = pending(lite, s), discovery = build(lite);
check(inform.model == 'U7LT' && inform.model_display == 'UniFi AP-AC-Lite');
check(index(discovery, hexdec('0c0004') + 'U7LT') >= 0 && index(discovery, hexdec('150004') + 'U7LT') >= 0);
check(length(inform.radio_table) == 1 && inform.radio_table[0].nss == 1 && length(inform.port_table) == 1);
print({ session_checks_passed: checks });
