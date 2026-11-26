// SPDX-License-Identifier: GPL-2.0-or-later
// Synthetic unadopted test identity; this does not perform adoption.
let mac = hexdec('023020000001');
let iphex = '';
for (let part in split(host_ip, '.')) iphex += sprintf('%02x', +part);
function tlv(type, data) {
    return hexdec(sprintf('%02x%04x', type, length(data))) + data;
}
let fields = tlv(2, mac + hexdec(iphex)) + tlv(1, mac)
    + tlv(10, hexdec('0000003c')) + tlv(11, 'mr3020-ucode-test')
    + tlv(12, 'U7PG2') + tlv(3, 'BZ.qca956x_6.8.2+15592.260126.1358')
    + tlv(22, '6.8.2.15592') + tlv(21, 'U7PG2')
    + tlv(19, mac) + tlv(23, hexdec('01'));
print(hexdec(sprintf('0206%04x', length(fields))) + fields);
