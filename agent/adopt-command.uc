// SPDX-License-Identifier: GPL-2.0-or-later
// Invoked only by the separate non-root, forced-command Dropbear listener.
import * as fs from 'fs';
import { command } from 'adoption';
let profile = json(fs.readfile('/etc/mr3020.json'));
if (profile.enabled !== true || profile.allow_adoption !== true) exit(1);
let peer = split(getenv('SSH_CONNECTION') || '', ' ')[0];
let request;
try { request = command(getenv('SSH_ORIGINAL_COMMAND') || '', peer, profile.controller); }
catch(e) { exit(1); }
let f = fs.open('/var/run/mr3020-adopt/request.json', 'wx', 384);
if (!f) exit(1);
f.write(sprintf('%J', request)); f.close();
