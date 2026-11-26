# Older-kernel integration

This build retains the OpenWrt 19.07.10 kernel, drivers and core networking
while adding Dropbear and the custom UniFi agent. One physical MR3020 v1
booted after a factory flash and after a sysupgrade. Later agent changes were
deployed and verified on that unit over SSH.

## Reference and provenance

The [thaneb MR3020 v1.x project](https://github.com/thaneb/TL-MR3020-OpenWRT-Extroot-Ready)
provides useful evidence of a small community OpenWrt 19.07 build. Its recipe at
commit `91d487ad90b134abc73d83d7e7a3c95e984cef9d` uses ar71xx/tiny, removes LuCI
and IPv6, and includes USB/extroot tools. We inspected its configuration and
helper scripts; we did not execute its scripts or use its third-party firmware.
Our USB-free experiment does not include extroot or those public Wi-Fi defaults.

The baseline instead uses the official
[19.07.10 ar71xx/tiny ImageBuilder](https://downloads.openwrt.org/releases/19.07.10/targets/ar71xx/tiny/):

- Archive: `openwrt-imagebuilder-19.07.10-ar71xx-tiny.Linux-x86_64.tar.xz`
- Archive SHA256: `875ac28700b4b7c7f9c700268794bcc1e00f3937823088d4274fe09925b10045`
- Prebuilt `vmlinux` SHA256: `0af2fd575189468cf13f9adb8801b8fd93874f2ca8cd1b900b8583cfedcc062c`
- Profile: `tl-mr3020-v1`; Linux 4.14.275; official matched ath9k/mac80211 modules.

The official directory does not publish an MR3020 factory image for this release.
The ImageBuilder still contains its device profile and the prebuilt kernel.
Reassembling that profile is not the same as having an officially published,
physically tested MR3020 factory binary. The community recipe supports feasibility;
it does not validate our image, its added userspace or every v1 unit.

## Userspace separation

`stable-dropbear.sh` builds upstream Dropbear 2026.94, pinned by its published
SHA256 `e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81`.
The [upstream release](https://github.com/mkj/dropbear/releases/tag/DROPBEAR_2026.94)
links the download mirror used by the script's source archive. No Dropbear source
patches are applied.

`stable-runtime.py` stages ucode, its required modules and current libraries under
`/usr/lib/mr3020-runtime`. The original `/lib/libc.so`, loader, netifd, procd,
ubusd, hostapd executable and kernel modules remain byte-for-byte identical
to the baseline. A small extension to `/lib/netifd/hostapd.sh` wires the
per-client VLAN list into legacy hostapd. Dropbear's ELF
interpreter and library path point to the private runtime, allowing its normal
self re-execution to keep working.

The old Dropbear init script enforces local/remote forwarding restrictions and
generates a single Ed25519 recovery host key asynchronously at boot. Ethernet
and DHCP can come up while this key is generated. Adoption uses its own host key to avoid a generation
race with recovery SSH. The root listener allows an empty password while the
root password field is empty. Set it with `passwd` after first login. No public
key is embedded. The separate temporary adoption listener is locked
and removed after handoff, as described in [recovery](recovery.md).

The older release uses `ifname`/bridge UCI sections, `hwmode=11g` and a different
ubus socket path. The agent handles those interfaces without updating netifd or
ubusd. Its hostapd health check falls back to the local `STATUS` control command.
`hostapd-basic` from the same old release supplies WPA2 and PMF support; mini from
that release lacks PMF. No DHCP/DNS/RA server or router firewall is included. IPv4/IPv6 forwarding is
explicitly disabled so the AP cannot route between the tagged IoT bridge and
management; inter-network routing remains on the UDR7.
The `opkg` CLI is retained; its presence is not a migration path to newer release
feeds. General package upgrades must not replace the pinned kernel/network stack
or the private SSH integration.

## Reproducing the experiment

The newer OpenWrt build provides the cross-compiler and private userspace
used by the agent. The final image uses the older 19.07.10 kernel and drivers.
Run the commands from the repository root. Use separate case-sensitive Docker
volumes for the two builders.

Download the pinned ImageBuilder archive and Dropbear archive into an inputs
directory and verify their checksums above. Set `MR3020_INPUTS` to the absolute
path of that directory.

```sh
docker build -t mr3020-toolchain .
docker run -d --name mr3020-toolchain \
  --mount type=volume,src=mr3020-toolchain,dst=/build \
  --mount type=bind,src="$PWD",dst=/project,readonly \
  --mount type=bind,src="$PWD/agent",dst=/inputs/ucode-unifi,readonly \
  --mount type=bind,src="$MR3020_INPUTS",dst=/inputs/stable-base,readonly \
  mr3020-toolchain sleep infinity
docker exec mr3020-toolchain bash /project/scripts/prepare.sh
docker exec mr3020-toolchain bash /project/agent/build.sh
docker exec mr3020-toolchain python3 /project/scripts/factory-image.py
docker exec mr3020-toolchain bash /project/scripts/stable-dropbear.sh
docker exec mr3020-toolchain python3 /project/scripts/stable-runtime.py
docker exec mr3020-toolchain tar czf - -C /build/stable19-runtime . > "$MR3020_INPUTS/runtime.tar.gz"
```

The intermediate factory image supplies the extracted runtime for the next
step. Use the final 19.07.10 images on the physical AP.

```sh
docker build --platform linux/amd64 -t mr3020-imagebuilder scripts/stable19
docker run -d --platform linux/amd64 --name mr3020-imagebuilder \
  --mount type=volume,src=mr3020-imagebuilder,dst=/build \
  --mount type=bind,src="$PWD",dst=/project,readonly \
  --mount type=bind,src="$MR3020_INPUTS",dst=/inputs,readonly \
  mr3020-imagebuilder sleep infinity
docker exec mr3020-imagebuilder sh -c '
  set -eu
  mkdir -p /build/ar71xx
  tar xf /inputs/imagebuilder-19.07.10-ar71xx-tiny.tar.xz --strip-components=1 -C /build/ar71xx
  cd /build/ar71xx
  make image PROFILE=tl-mr3020-v1 PACKAGES="$(cat /project/config/stable19-packages.txt)"
  mkdir -p /build/baseline
  cp bin/targets/ar71xx/tiny/*tl-mr3020-v1-squashfs-factory.bin /build/baseline/
  python3 /project/scripts/stable-image.py
'
docker cp mr3020-imagebuilder:/build/stable19-result ./dist
```

Name the downloaded ImageBuilder archive
`imagebuilder-19.07.10-ar71xx-tiny.tar.xz` to match the commands. The final
builder checks the TP-Link header, kernel and core networking against the
baseline and verifies the allowance for writable settings. See the [recovery
guide](recovery.md) before flashing.

## Evidence boundaries

A separate 32 MiB Malta VM can run the old release's userspace with the official
Malta 4.14.275 kernel and matching simulator-only Ethernet/Wi-Fi modules. It is
useful for SSH, old ubus/UCI compatibility, startup, configuration and memory
checks. The factory image itself retains the MR3020 kernel and ath9k modules.
The VM's disk and simulated hardware do not reproduce flash/JFFS2, AR9331
Ethernet, RF calibration, bootloader behavior or physical reset recovery.

## Local validation so far

The complete image fits with `opkg` retained and 448 KiB reserved for writable
settings. The TP-Link hardware ID is `0x30200001`, there is no bootloader payload,
and the board kernel payload is identical to the official-component baseline.
The final core-file manifest is saved alongside the build result.

On a 32 MiB Malta VM using Linux 4.14.275, the added runtime talks to the old
ubusd; the earlier key-based prototype verified Dropbear and SCP; two
simulated WPA2 AP interfaces run on channel 6; VLAN 2 is created; and a failed
health check rolls back to that working configuration. The second BSS is checked
against its own entry in old hostapd's shared status table.

A separate local controller stub exercised real SSH password authentication to
the restricted adoption account. An arbitrary `id` command was rejected; the
exact supported adoption command was accepted; the key persisted; the account
locked; the adoption listener was removed; and the agent stayed running. This
local check complements the UDR7 adoption test below.

With two simulated BSSs, the agent and an active recovery SSH session, the guest
reported about 14 MiB available memory. This is one observed state, not a peak
measurement or an AR9331 memory guarantee. One VM boot took roughly two minutes
to initialize its random pool; the asynchronous SSH startup keeps this wait
from blocking network startup. Physical boot, JFFS2, Ethernet and RF remain
untested. Verify the selected IoT VLAN before preparing a flash candidate.

After a VM power cycle, management DHCP, fixed recovery, both simulated BSSs,
and the agent returned automatically. The adopted test account remained locked
and its listener stayed absent. SSH/agent/startup files were hashed in
the running VM and matched the assembled image. The 32 MiB result remains a
Malta userspace test, not a physical MR3020 boot or a flash-filesystem test.

IPv4 and IPv6 forwarding also read back as disabled in the guest after loading
the AP configuration. Ethernet bridging remains enabled; routing belongs to the
UDR7.

## UDR7 test with AC Pro

The 32 MiB LAN-bridged VM adopted through the real UDR7 SSH handoff. The
temporary account locked, the adoption listener exited, and UniFi showed the
test device Online. The first provisioning attempt rolled back: discovery
packets shortened the health-check wait while legacy hostapd selected a channel.
A timed retry allowed both SSIDs to come up; the agent persisted and acknowledged
the configuration. UniFi displayed uptime, channel 1 and 20 MHz, and the guest
reported its simulated 10 Mbps Ethernet uplink. Both provisioned SSIDs were
untagged. VLAN 2 still needs a live provisioning and traffic check.

New older-base images ship with `model: U7LT` in `/etc/mr3020.json` and adopt
as AC Lite. Existing installations that omit `model` keep their AC Pro
identity. Both profiles report one radio and one Ethernet port in discovery
and informs. The agent does not implement Port Manager controls or AirView.

## Separate UDR7 test with AC Lite

A fresh 32 MiB VM with its own Ethernet MAC independently adopted as AC Lite
and appeared Online. The controller's initial Wi-Fi settings and a later
channel change from Auto to 6 applied and were acknowledged. Two SSIDs
were active on one simulated 2.4 GHz radio, and recovery SSH and its fixed
address remained available. The updated agent files in the VM match the
rebuilt image. Both SSIDs were delivered untagged in this test.

## Virtual Network Override compatibility

The original AC Pro and AC Lite profiles lacked UniFi's site-wide MAC-based
VLAN capability. An adopted record without this capability could make
Virtual Network Override unavailable even when the VM was offline.

The current 19.07.10 candidate opts in with
`"virtual_network_override": true` in `/etc/mr3020.json`. The agent advertises the signed firmware
capability only if the legacy hostapd generator supports the per-client
mapping. It reports associated Wi-Fi clients and applies the controller's
`aaa.<n>.accept_mac.*` assignments to managed native, non-isolated WPA2
SSIDs. VLAN 1 uses the existing native bridge. Local and controller
assignments for the same SSID are rejected when both are present.
[openUF protocol reference](https://github.com/yesrab/openUF/blob/21505ccca65862301915c084b91b7e8078691d45/REFERENCE.md).

In the live UDR7 test, the AC Lite VM applied an override and its removal
after both updates were saved through the controller. On VLAN 2, the test
station's DHCP requests left the guest Ethernet interface with 802.1Q tags.
No reply reached the guest. Default DHCP worked before the override.
The isolated OpenWrt test received both tagged and untagged DHCP leases.
The bridged VM could not complete that test. A later test on the physical MR3020 verified per-client VLAN 2 DHCP and traffic through the wired uplink.

### Per-client VLANs with a local mapping

The 19.07.10 agent can provision a local MAC-to-VLAN mapping on an untagged,
non-isolated WPA2 SSID. Add `client_vlans` to `/etc/mr3020.json`, with
the exact SSID as the key and lowercase MAC addresses mapped to integer VLAN
IDs from 2 through 4094. For example:

```json
{
  "client_vlans": {
    "MR3020 VLAN Lab": {
      "02:30:20:00:11:02": 2
    }
  }
}
```

Merge this into the existing profile, restart the agent and reprovision the AP
to apply additions or removals. Unlisted clients use the SSID's native
network. The uplink must carry the selected VLAN tags and reach a DHCP server
for each assigned VLAN. The stable ImageBuilder overlay extends the legacy
hostapd configuration generator. It retains the legacy hostapd binary.

The isolated fixture can also provision this explicit local mapping with
simulated controller Wi-Fi settings.

## Factory candidate verification

The build report records the candidate checksum, the stock-format hardware
ID and the packaged core-file hashes. It compares the extracted candidate's
files with a separately extracted official-component baseline. The TP-Link
header checksum passed and the bootloader offset and length are both zero.
The file is 3,932,160 bytes and the calculation leaves 448 KiB at erase-block
boundaries for writable settings. This is a flash-layout allowance. Actual
JFFS2 free space still needs measurement on the device.

An isolated 32 MiB Malta VM started from the candidate's extracted filesystem
with the matching simulator kernel and modules. With no UniFi controller on
its network, it exposed the wired recovery address. The password-login
candidate accepts root with no password at first boot. After `passwd`, SSH
requires the chosen password. The VM fixture supplied host entropy
for first-boot key generation when needed. The candidate generates its own
host keys on-device.

The agent applied explicit SSID disable/re-enable and whole-radio disable/re-enable.
Recovery stayed configured during the transitions. Two clients on the same
WPA2 SSID then obtained separate DHCP leases, with untagged and VLAN 2 frames
verified on the guest uplink. CPU, RAM and uptime were encoded into the
inform payload. CPU starts with a sample and reports the interval thereafter.

The physical AR9331 boot and VLAN 2 DHCP through the wired uplink were
verified on the installed MR3020 v1. Bootloader recovery remains untested.
Have physical recovery available for a first flash. See [recovery](recovery.md).

## Lock to AP

The agent can apply UniFi's per-SSID `macacl.*` deny lists through hostapd.
A denied client's MAC is left out of that SSID's VLAN accept list, because
legacy hostapd checks the accept list first. The isolated 19.07.10 VM refused
association for a client whose MAC was also mapped to VLAN 2. After removing
the deny rule, the same client joined and obtained a tagged VLAN 2 DHCP lease.
The other test MAC obtained an untagged lease.

Set `"lock_to_ap": true` in `/etc/mr3020.json` and restart the agent with
`/etc/init.d/mr3020 restart` to advertise the capability after upgrading.
The UDR7's UniFi Network 11 controller accepted a lock for a simulated client
through its client settings API. The emulated AP applied the rule and rejected
the client's next authentication attempt. Configuration changes use the normal
Wi-Fi reload and can briefly disconnect other clients on that AP.

## Transmit power reporting

The agent reports the transmit power that the driver returns for the active
radio through `iw`. The roof MR3020 and UniFi both reported 18 dBm on channel
13 at 20 MHz after the upgrade.
Set transmit power locally in OpenWrt if needed. The UniFi agent currently
reports the driver's setting and does not translate UniFi power presets.

The agent also reports packet and byte counts, transmit retries, and transmit
drops from the wireless driver. Receive retry and drop totals are unavailable.
The Experience score is a signal-based estimate averaged across clients with
signal measurements. The Ethernet parent is reported when the AP hears a
valid LLDP advertisement on its uplink. The AP also advertises its own
Ethernet identity so the upstream device can identify the port it learned
the AP on.
