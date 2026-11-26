// SPDX-License-Identifier: GPL-2.0-or-later
// Discovery/inform agent. Configuration requires an explicit local apply mode.
import * as net from 'socket';
import * as fs from 'fs';
import * as codec from 'inform';
import { post, ipv4 } from 'transport';
import { build, reply } from 'discovery-wire';
import { initial, step } from 'session';
import { pending } from 'identity';
import { plan } from 'planner';
import * as persist from 'persist';
import { consume } from 'adoption';
import * as configuration from 'apply';
import * as ubus from 'bus';
import { lock } from 'account';
import { collect, lldp_advertisement, lldp_announce, lldp_read, lldp_socket, system_usage } from 'status';
import { managed_radio_ready } from 'radio-status';
function log(data) { print(data, '\n'); fs.stdout.flush(); }

if (type(profile) != 'object' || profile.enabled !== true || !ipv4(profile.ip) ||
    !ipv4(profile.controller) || !match(profile.mac || '', /^[0-9a-f]{12}$/)) die('explicit valid test profile required');
let count = profile.daemon === true ? 0 : (profile.rounds || 3);
if (type(count) != 'int' || count < 0 || count > 120 || (count == 0 && profile.daemon !== true)) die('invalid test rounds');
profile.port = profile.port || 8080;
let udp = net.create(net.AF_INET, net.SOCK_DGRAM);
if (!udp || !udp.setopt(net.SOL_SOCKET, net.SO_REUSEADDR, true) ||
    !udp.bind({ family: net.AF_INET, address: '0.0.0.0', port: profile.discovery_port || 10001 })) die('discovery bind failed');
udp.setopt(net.IPPROTO_IP, net.IP_ADD_MEMBERSHIP, { multiaddr: '233.89.188.1', address: '0.0.0.0', ifindex: 0 });
let state = profile.state_dir ? persist.load(profile.state_dir, profile.state_uid) : initial(), last_reply = 0;
function activate() {
    if (profile.apply_mode == 'emulated') return true;
    let db = ubus.connect();
    if (!db) return false;
    db.call('network', 'reload', {});
    let error = ubus.error();
    db.disconnect();
    return error == null && system('/sbin/wifi reload') == 0;
}
function healthy(r, ssids) {
    if (profile.apply_mode == 'emulated') return true;
    // On 19.07 the radio, secondary BSS and VLAN bridge can take over 20
    // seconds to settle after an automatic channel scan and wireless reload.
    for (let attempt = 0; attempt < 180; attempt++) {
        let db = ubus.connect();
        if (!db) return false;
        let lan = db.call('network.interface.lan', 'status', {}), rescue = db.call('network.interface.rescue', 'status', {});
        let wireless = db.call('network.wireless', 'status', {});
        let mgmt = lan?.up && lan?.['ipv4-address']?.[0]?.address == profile.ip &&
            rescue?.up && rescue?.['ipv4-address']?.[0]?.address == '169.254.30.20';
        let radio_ok = managed_radio_ready(db, r, ssids, wireless);
        db.disconnect();
        if (mgmt && radio_ok && (r.disabled || !(profile.client_vlans || profile.virtual_network_override) || configuration.attach_client_vlans(profile.config_dir))) {
            let link = net.connect(profile.controller, 8080, { family: net.AF_INET, socktype: net.SOCK_STREAM }, 1000);
            if (link != null) { link.close(); return true; }
        }
        sleep(250);
    }
    return false;
}
if (profile.config_dir && profile.state_dir)
    configuration.recover(profile.config_dir, profile.state_dir + '/rollback.json', activate);
let boot = time(), previous_cpu = null, neighbor = null;
let lldp = profile.apply_mode == 'hardware' ? lldp_socket() : null;
let advertisement = lldp ? lldp_advertisement(profile.mac, profile.hostname) : null;
let last_lldp = -30;
for (let round = 0; count == 0 || round < count; round++) {
    if (profile.allow_adoption === true && profile.adoption_file) {
        let next = consume(profile.adoption_file, state, profile.controller, profile.adoption_uid || 0);
        if (next.key != state.key) {
            if (!profile.state_dir) die('persistent storage required for adoption');
            persist.save(profile.state_dir, next, profile.state_uid);
            state = next;
            if (profile.apply_mode == 'hardware') {
                lock('/etc/shadow', true);
                let db = ubus.connect();
                db?.call('service', 'delete', { name: 'mr3020', instance: 'adoption' });
                db?.disconnect();
            }
            log({ event: 'ssh-adoption-key-received' });
        }
    }
    profile.counter = round;
    profile.adopted = state.phase != 'pending';
    profile.uptime = profile.apply_mode == 'hardware' ? +split(fs.readfile('/proc/uptime'), '.')[0] : time() - boot;
    if (profile.apply_mode == 'hardware') {
        if ((profile.client_vlans || profile.virtual_network_override) && profile.config_dir) configuration.attach_client_vlans(profile.config_dir);
        profile.live = collect(state, profile.virtual_network_override === true);
        neighbor = lldp_read(lldp, neighbor, profile.uptime);
        if (!profile.live.up) neighbor = null;
        if (lldp && profile.live.up && profile.uptime - last_lldp >= 30) {
            lldp_announce(lldp, advertisement);
            last_lldp = profile.uptime;
        }
        profile.live.lldp = neighbor?.neighbor;
        let usage = system_usage(previous_cpu, profile.uptime);
        previous_cpu = usage.sample;
        profile.live.system_stats = usage.report;
        if (ipv4(profile.live.ip)) profile.ip = profile.live.ip;
    }
    udp.send(build(profile), 0, { address: profile.controller, port: profile.discovery_target_port || 10001 });
    let encoded = codec.encode(hexdec(profile.mac), hexdec(state.key), sprintf('%J', pending(profile, state)), state.gcm);
    if (encoded == null) die('inform encode failed');
    let result;
    try { result = post(profile.controller, profile.port, encoded); }
    catch (e) { log({ round, event: 'transport-failed' }); net.poll(1000, udp); continue; }
    if (result.status == 200 && length(result.body)) {
        let plain = codec.decode(hexdec(profile.mac), hexdec(state.key), result.body);
        if (plain == null) die('controller frame rejected');
        let outcome = step(state, json(plain), profile.allow_adoption === true);
        if (profile.state_dir && (outcome.state.key != state.key || outcome.state.gcm != state.gcm))
            persist.save(profile.state_dir, outcome.state, profile.state_uid);
        state = outcome.state;
        let ssids = null, applied = false;
        if (outcome.pending_cfg != null) {
            try { ssids = length(plan(outcome.pending_cfg, profile.virtual_network_override)); }
            catch (e) { log({ event: 'configuration-unsupported-not-applied' }); }
            if (ssids != null && (profile.apply_mode == 'emulated' || profile.apply_mode == 'hardware') && profile.config_dir && profile.state_dir) {
                try {
                    let report = configuration.apply(outcome.pending_cfg, profile.config_dir,
                        profile.state_dir + '/rollback.json', activate, healthy, profile.client_vlans, profile.virtual_network_override);
                    let configured = { ...state, report, cfgversion: outcome.pending_version };
                    persist.save(profile.state_dir, configured, profile.state_uid);
                    state = configured;
                    applied = true;
                } catch(e) { log({ event: 'configuration-application-failed', reason: e.message }); }
            }
        }
        if (outcome.pending_cfg != null && profile.capture_dir) {
            // Explicit lab capture only: includes Wi-Fi secrets; private directory required.
            let d = fs.lstat(profile.capture_dir);
            if (!d || d.type != 'directory' || (d.mode & 63) != 0) die('unsafe capture directory');
            let f = fs.open(profile.capture_dir + '/config-' + round + '.json', 'wx', 384);
            if (!f) die('cannot create private configuration capture');
            f.write(sprintf('%J', { system_cfg: outcome.pending_cfg, mgmt_cfg: json(plain).mgmt_cfg, cfgversion: json(plain).cfgversion })); f.close();
        }
        if (!profile.daemon || outcome.event != 'noop') log({ round, status: result.status, event: applied ? 'configuration-applied' : outcome.event, planned_ssids: ssids, applied, mode: profile.apply_mode || 'plan-only' });
    } else if (!profile.daemon || round % 10 == 0) log({ round, status: result.status, response_bytes: length(result.body), phase: state.phase });
    if (round + 1 == count) break;
    let until = time() + (profile.test_interval || state.interval);
    while (time() < until) {
        let events = net.poll(250, udp);
        if (events == null || !events[0][1]) continue;
        let peer = {}, probe = udp.recv(1024, net.MSG_DONTWAIT, peer);
        if (probe == null || peer.address != profile.controller || time() <= last_reply) continue;
        let response = reply(probe, profile);
        if (response != null) {
            udp.send(response, 0, peer);
            last_reply = time();
            if (!profile.daemon) log({ event: 'discovery-probe-answered' });
        }
    }
}
udp.close();
lldp?.close();
