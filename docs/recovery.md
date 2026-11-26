# Installation and access independent of UniFi

## Before flashing

The selected factory candidate is the **OpenWrt 19.07.10 ar71xx/tiny** build
for **TL-MR3020 v1**. Back up the TP-Link configuration and verify the
candidate SHA256 from the build report. The TP-Link stock upgrade page takes
the factory-format image. Keep the other device revisions, sysupgrade
images and earlier modern-kernel experiment out of this upload.

The candidate keeps the MR3020 v1 bootloader partition untouched by omitting
a bootloader payload. Boot and RF calibration on this unit are still untested.
Have physical access and a serial recovery path available for the first flash.
If the stock web UI rejects the file, stop there. The recovery address below
requires a working kernel and Ethernet.

The build retains `opkg` and starts with Wi-Fi disabled until UniFi provisions
it. The wired bridge starts independently and provides both normal DHCP and
a fixed recovery address. Stock Wi-Fi settings need to be recreated in UniFi.

## Updating an installed 19.07.10 image

Use the matching `*-sysupgrade.bin` with OpenWrt's SSH command-line upgrade.
From another wired connection or AP, copy it into `/tmp` with `scp -O`.
Verify the published SHA-256 on the router and confirm the board name
(`cat /tmp/sysinfo/board_name` should report `tl-mr3020`).

For the first upgrade from an earlier image, make sure these lines are in
`/etc/sysupgrade.conf`. Images built with the new keep list already
include them through `/lib/upgrade/keep.d/mr3020`.

```text
/etc/mr3020.json
/etc/mr3020-state/state.json
/etc/shadow
```

Run `sysupgrade -l` and confirm that it lists those three files, the ordinary
OpenWrt network and wireless configuration, and the Dropbear host key. Save
an off-device backup with `sysupgrade -b` and keep it private, because it
contains credentials and keys. Wait until the AP is fully provisioned and
the agent's rollback journal is absent.

Run `sysupgrade -T /tmp/<image>.bin` before writing. Once it succeeds, apply
with `sysupgrade /tmp/<image>.bin` using the default settings preservation.
After reboot, verify the wired SSH login, the existing UniFi device record
and the client VLANs. A physical sysupgrade of the roof MR3020 preserved the
root password, SSH host key, wired management, and UniFi adoption. It exposed
a first-boot reset of the restored radio settings and a too-short provisioning
wait. The updated image skips first-boot defaults when adoption state has
been restored and gives the radio and VLAN bridge longer to become ready.

## Normal access

The wired management bridge requests DHCP and uses hostname `mr3020`. Look up its lease in the router and connect with:

```sh
ssh root@DEVICE_IP
```

The 19.07.10 image starts with the standard OpenWrt `root` account and no
password. There is no baked-in authorized SSH key. On your first SSH session
run `passwd`, choose a password, and verify a second login before closing the
first. Any machine that can reach SSH can log in during the initial blank
password window. Keep that window short. Access works before UniFi adoption.

To enable key login on an installed device, add your public key to
`/root/.ssh/authorized_keys`. Keep the directory at mode `700` and the file
at `600`. Images with the updated keep list preserve that file on sysupgrade.
For an older image, add the path to `/etc/sysupgrade.conf` before upgrading.


## Fixed recovery address

The same wired bridge also has **169.254.30.20/16**, with no recovery gateway. This avoids relying on the home DHCP pool, DNS or UniFi.

1. Connect the Mac to the MR3020's Ethernet port, directly if necessary. Temporarily disconnect that segment from other networks if you need to isolate the test.
2. Set the Mac's Ethernet IPv4 address to **169.254.30.21**, mask **255.255.0.0**, no router/gateway.
3. Connect using the current root password, or with no password immediately after a reset:

```sh
ssh root@169.254.30.20
```

4. Return the Mac's Ethernet configuration to DHCP afterward.

This requires the device to have booted and the wired interface/SSH to work. It does not recover a failed flash, broken kernel or forgotten configured password. The agent must leave the management and recovery interfaces and SSH configuration untouched.

## Physical reset after a successful boot

The included upstream reset handler is configured to factory-reset writable settings when reset is held at least five seconds and released after the overlay has mounted. Resetting should restore the image’s blank root password and first-boot DHCP/recovery settings. It keeps the OpenWrt image installed. This behavior was inspected in source and is **not yet confirmed on the physical device**. It erases later writable configuration.

## Evidence boundaries

The target MIPS UCI binary passed 18 assertions: DHCP, static recovery IP, bridge binding, hostname and disabled password authentication survived two runs of the initializer. Boot, link-local recovery and reset-button behavior still need a hardware test.

## Agent startup and adoption

Set the controller address and enable the agent after first boot, following the README. It waits for management DHCP and uses the physical Ethernet MAC. Recovery SSH starts independently of UniFi discovery. During an explicitly enabled initial adoption window, a separate restricted `ubnt` receiver accepts only the expected adoption command from the configured UDR7; it is locked and its separate listener removed after the handoff. It cannot provide a normal shell or TCP forwarding.

Configuration application preserves the management and recovery interfaces and keeps a rollback journal before network changes. VM reload/health checks have been exercised, but loss of power during a flash, kernel failure and physical reset behavior remain untested. These are development behaviors; the older-base integration must repeat the checks.
