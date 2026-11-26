// SPDX-License-Identifier: GPL-2.0-or-later
export const FACTORY_KEY = 'ba86f2bbe107c7c57eb5f2690775c712';
export function initial() { return { key: FACTORY_KEY, gcm: false, cfgversion: '0', phase: 'pending', interval: 10 }; };
export function step(state, response, allow_adoption) {
    if (type(response) != 'object') die('invalid controller reply');
    let next = { ...state }, event = 'ignored', pending_cfg = null, pending_version = null;
    if (response.interval != null) {
        if (type(response.interval) != 'int' || response.interval < 1 || response.interval > 3600) die('invalid inform interval');
        next.interval = response.interval;
    }
    if (response._type == 'noop') return { state: next, event: 'noop' };
    if (response._type != 'setparam') return { state: next, event };
    let cfg = {};
    if (response.mgmt_cfg != null) {
        if (type(response.mgmt_cfg) != 'string' || length(response.mgmt_cfg) > 16384) die('invalid management config');
        for (let line in split(response.mgmt_cfg, '\n')) {
            if (!length(line)) continue;
            let equal = index(line, '=');
            if (equal < 1) die('malformed management config');
            let key = trim(substr(line, 0, equal));
            if (exists(cfg, key)) die('duplicate management config key');
            cfg[key] = trim(substr(line, equal + 1));
        }
    }
    // No controller migration, shell commands, firmware updates or SSH changes.
    if (cfg.authkey != null) {
        if (!match(cfg.authkey, /^[0-9a-fA-F]{32}$/)) die('invalid adoption key');
        if (cfg.authkey != FACTORY_KEY && state.key == FACTORY_KEY) {
            if (!allow_adoption) return { state, event: 'adoption-disabled' };
            next.key = lc(cfg.authkey);
            next.phase = 'keyed';
            event = 'key-received';
        } else if (lc(cfg.authkey) != state.key) die('refusing unsolicited key replacement');
    }
    if (cfg.use_aes_gcm == 'true') next.gcm = true;
    if (response.system_cfg != null) {
        if (type(response.system_cfg) != 'string' || length(response.system_cfg) > 65536) die('invalid system config');
        pending_cfg = response.system_cfg;
        pending_version = response.cfgversion || cfg.cfgversion;
        if (!match(pending_version || '', /^[0-9a-fA-F]{1,64}$/)) die('invalid configuration version');
        event = 'configuration-received-not-applied';
    }
    // Never acknowledge cfgversion until a separate apply+health-check succeeds.
    return { state: next, event, pending_cfg, pending_version };
};
