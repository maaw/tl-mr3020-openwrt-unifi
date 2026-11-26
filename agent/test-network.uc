import { post } from 'transport';
import { build, reply } from 'discovery-wire';
let p = { mac: '023020000001', ip: '192.0.2.10', hostname: 'mr3020-test' };
let n = 0;
function check(x) { if (!x) die('network assertion failed'); n++; }
check(substr(hexenc(build(p)), 0, 4) == '0206');
check(substr(hexenc(reply(hexdec('01000000'), p)), 0, 4) == '0100');
check(substr(hexenc(reply(hexdec('02080000'), p)), 0, 4) == '0209');
check(reply(hexdec('01040006023020000002'), p) == null);
check(reply(hexdec('01040006023020000001'), p) != null);
check(reply(build(p), p) == null);
let result = post('127.0.0.1', test_port, 'test-body');
check(result.status == expected_status);
check(hexenc(result.body) == expected_hex);
print({ checks_passed: n });
