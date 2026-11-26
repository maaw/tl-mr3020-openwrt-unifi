// SPDX-License-Identifier: GPL-2.0-or-later
import * as net from 'socket';

export function ipv4(ip) {
    if (type(ip) != 'string') return false;
    let p = split(ip, '.');
    if (length(p) != 4) return false;
    for (let n in p)
        if (!match(n, /^(0|[1-9][0-9]{0,2})$/) || +n > 255) return false;
    return true;
};

// Finite request/response bounds; accepts literal IPv4 addresses only.
export function post(ip, port, body) {
    if (!ipv4(ip) || port < 1 || port > 65535 || type(body) != 'string' || length(body) > 66560)
        die('invalid HTTP request');
    let s = net.connect(ip, port, { family: net.AF_INET, socktype: net.SOCK_STREAM }, 2000);
    if (s == null) die('controller connect failed');
    try {
        if (!s.setopt(net.SOL_SOCKET, net.SO_RCVTIMEO, { sec: 2, usec: 0 }) ||
            !s.setopt(net.SOL_SOCKET, net.SO_SNDTIMEO, { sec: 2, usec: 0 })) die('socket timeout setup failed');
        let request = sprintf('POST /inform HTTP/1.0\r\nHost: %s:%d\r\nContent-Type: application/x-binary\r\nContent-Length: %d\r\nConnection: close\r\n\r\n', ip, port, length(body)) + body;
        let end = time() + 5, offset = 0;
        while (offset < length(request)) {
            if (time() > end) die('HTTP write deadline exceeded');
            let n = s.send(substr(request, offset));
            if (n == null || n <= 0) die('HTTP write failed');
            offset += n;
        }
        let response = '', boundary = -1, expected = null;
        while (true) {
            if (time() > end) die('HTTP read deadline exceeded');
            let chunk = s.recv(4096);
            if (chunk == null) die('HTTP read failed');
            if (!length(chunk)) break;
            response += chunk;
            if (length(response) > 70656) die('HTTP response exceeds limit');
            if (boundary < 0) {
                boundary = index(response, '\r\n\r\n');
                if (boundary < 0 && length(response) > 4096) die('HTTP headers exceed limit');
                if (boundary >= 0) {
                    if (boundary > 4096) die('HTTP headers exceed limit');
                    let seen = {};
                    for (let line in slice(split(substr(response, 0, boundary), '\r\n'), 1)) {
                        let colon = index(line, ':');
                        if (colon < 1) die('invalid HTTP header');
                        let key = lc(trim(substr(line, 0, colon))), value = trim(substr(line, colon + 1));
                        if (exists(seen, key)) die('duplicate HTTP header');
                        seen[key] = true;
                        if (key == 'transfer-encoding') die('unsupported HTTP transfer encoding');
                        if (key == 'content-length') {
                            if (!match(value, /^(0|[1-9][0-9]*)$/) || +value > 66560) die('invalid HTTP length');
                            expected = +value;
                        }
                    }
                }
            }
            if (boundary >= 0 && expected != null && length(response) >= boundary + 4 + expected) break;
        }
        if (boundary < 0) die('incomplete HTTP response');
        let status = match(response, /^HTTP\/1\.[01] ([0-9]{3})[ \r]/);
        if (!status) die('invalid HTTP status');
        let data = substr(response, boundary + 4);
        if (expected != null && length(data) != expected) die('HTTP body length mismatch');
        s.close();
        return { status: +status[1], body: data };
    } catch (e) { s.close(); die(e); }
};
