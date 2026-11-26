// SPDX-License-Identifier: GPL-2.0-or-later
import { ipv4 } from 'transport';
import { device_model } from 'identity';
function tlv(id, data) { return hexdec(sprintf('%02x%04x', id, length(data))) + data; }
export function build(profile, header) {
    if (!match(profile.mac || '', /^[0-9a-f]{12}$/) || !ipv4(profile.ip) ||
        !match(profile.hostname || '', /^[a-zA-Z0-9-]{1,63}$/)) die('invalid discovery profile');
    let mac = hexdec(profile.mac), ip = '';
    let model = device_model(profile).code;
    for (let n in split(profile.ip, '.')) ip += sprintf('%02x', +n);
    let fields = tlv(2, mac + hexdec(ip)) + tlv(1, mac)
        + tlv(10, hexdec(sprintf('%08x', profile.uptime || 0)))
        + tlv(11, profile.hostname) + tlv(12, model)
        + tlv(3, 'BZ.qca956x_6.8.2+15592.260126.1358')
        + tlv(22, '6.8.2.15592') + tlv(21, model)
        + tlv(23, hexdec(profile.adopted ? '00' : '01'))
        + tlv(24, hexdec('00')) + tlv(25, hexdec('01')) + tlv(26, hexdec('00'))
        + tlv(19, mac) + tlv(18, hexdec(sprintf('%08x', profile.counter || 0)))
        + tlv(27, '6.8.2.15592');
    return hexdec(header || '0206') + hexdec(sprintf('%04x', length(fields))) + fields;
};
export function reply(probe, profile) {
    let h = hexenc(probe);
    if (h == '01000000') return build(profile, '0100');
    if (h == '02080000') return build(profile, '0209');
    if (h == '01040006' + profile.mac) return build(profile, '0104');
    return null;
};
