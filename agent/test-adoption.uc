import * as fs from 'fs';
import { initial } from 'session';
import { command, consume } from 'adoption';
let n = 0, peer = '192.0.2.1', key = '00112233445566778899aabbccddeeff';
function check(v) { if (!v) die('adoption assertion failed'); n++; }
let text = '/usr/bin/syswrapper.sh set-adopt http://' + peer + ':8080/inform ' + key;
check(command(text, peer, peer).key == key);
for (let bad in [text + '; id', replace(text, peer, '192.0.2.2'), replace(text, key, 'invalid'),
    'sh -c ' + text, replace(text, 'set-adopt', 'set-inform')]) {
    let rejected = false;
    try { command(bad, peer, peer); } catch(e) { rejected = true; }
    check(rejected);
}
let rejected = false;
try { command(text, '192.0.2.2', peer); } catch(e) { rejected = true; }
check(rejected);
let path = test_dir + '/adoption.json';
fs.writefile(path, sprintf('%J', command(text, peer, peer))); fs.chmod(path, 384);
let state = consume(path, initial(), peer, 1000);
check(state.phase == 'keyed' && state.key == key);
check(!fs.lstat(path));
fs.writefile(path, sprintf('%J', command(text, peer, peer))); fs.chmod(path, 420);
rejected = false;
try { consume(path, initial(), peer, 1000); } catch(e) { rejected = true; }
check(rejected); fs.unlink(path);
print({ adoption_checks_passed: n });
