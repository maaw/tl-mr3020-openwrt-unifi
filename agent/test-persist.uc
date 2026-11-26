import * as fs from 'fs';
import { load, save } from 'persist';
import { initial } from 'session';
let n = 0;
function check(v) { if (!v) die('state storage assertion failed'); n++; }
let first = load(state_dir, 1000);
check(first.phase == 'pending');
let state = { ...initial(), key: '00112233445566778899aabbccddeeff', phase: 'keyed', gcm: true };
save(state_dir, state, 1000);
check(load(state_dir, 1000).key == state.key);
check(load(state_dir, 1000).gcm);
check(fs.lstat(state_dir + '/state.json').mode == 384);
check(fs.lstat(state_dir).mode == 448);
check(!fs.lstat(state_dir + '/state.new'));
save(state_dir, state, 1000);
check(load(state_dir, 1000).phase == 'keyed');
fs.chmod(state_dir + '/state.json', 420);
let rejected = false;
try { load(state_dir, 1000); } catch (e) { rejected = true; }
check(rejected);
fs.chmod(state_dir + '/state.json', 384);
fs.writefile(state_dir + '/state.json', 'invalid JSON');
rejected = false;
try { load(state_dir, 1000); } catch (e) { rejected = true; }
check(rejected);
fs.unlink(state_dir + '/state.json');
fs.symlink('/tmp', state_dir + '/state.json');
rejected = false;
try { load(state_dir, 1000); } catch (e) { rejected = true; }
check(rejected);
fs.unlink(state_dir + '/state.json');
print({ persistence_checks_passed: n });
