// SPDX-License-Identifier: GPL-2.0-or-later
import * as ubus from 'ubus';
export function connect() {
    // libubus moved its default socket directory after OpenWrt 19.07.
    return ubus.connect() || ubus.connect('/var/run/ubus.sock');
};
export function error() { return ubus.error(); };
