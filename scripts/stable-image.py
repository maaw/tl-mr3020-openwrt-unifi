#!/usr/bin/env python3
"""Build from the official 19.07.10 ar71xx ImageBuilder. Never flashes hardware.

Requires a completed minimal baseline and the archive from stable-runtime.py.
Run inside the older-release builder, with the repository at /project.
"""
import hashlib
import json
import shutil
import struct
import subprocess
import tarfile
from pathlib import Path

ib = Path('/build/ar71xx')
kernel = ib / 'build_dir/target-mips_24kc_musl/linux-ar71xx_tiny/vmlinux'
assert hashlib.sha256(kernel.read_bytes()).hexdigest() == '0af2fd575189468cf13f9adb8801b8fd93874f2ca8cd1b900b8583cfedcc062c'
baseline_image = Path('/build/baseline/openwrt-19.07.10-ar71xx-tiny-tl-mr3020-v1-squashfs-factory.bin')
baseline = baseline_image.read_bytes()
host_bin = ib / 'staging_dir/host/bin'
def kernel_bytes(data):
    offset, size = struct.unpack_from('>2I', data, 128)
    return data[offset:offset + size]

def extract(image, destination):
    if destination.exists():
        shutil.rmtree(destination)
    offset, = struct.unpack_from('>I', image.read_bytes(), 136)
    subprocess.run([str(host_bin / 'unsquashfs4'), '-no-progress',
                    '-o', str(offset), '-d', str(destination), str(image),
                    'bin', 'etc', 'lib', 'root', 'sbin', 'usr'],
                   stdout=subprocess.DEVNULL, check=True)

root = Path('/build/stable19-baseline-root')
extract(baseline_image, root)
paths = ['sbin/netifd', 'sbin/procd', 'sbin/ubusd', 'usr/sbin/hostapd', 'lib/libc.so',
         'bin/busybox', 'bin/opkg', 'sbin/wifi', 'etc/init.d/network']
paths += [str(p.relative_to(root)) for p in (root / 'lib/modules').rglob('*') if p.is_file()]
paths += [str(p.relative_to(root)) for p in (root / 'lib/netifd').rglob('*') if p.is_file() and p.name != 'hostapd.sh']
original = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in paths}
files = Path('/build/stable19-files')
if files.exists():
    shutil.rmtree(files)
files.mkdir()
with tarfile.open('/inputs/runtime.tar.gz') as archive:
    for entry in archive.getmembers():
        if entry.name.startswith('/') or '..' in Path(entry.name).parts:
            raise RuntimeError('Unsafe overlay member')
    archive.extractall(files)
hostapd_script = 'lib/netifd/hostapd.sh'
patched_hostapd = files / hostapd_script
patched_hostapd.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(['sh', '/project/scripts/legacy-hostapd-vlans.sh',
                str(root / hostapd_script), str(patched_hostapd)], check=True)
for path, line in {
    'etc/passwd': 'ubnt:x:453:453:UniFi adoption only:/var/run/mr3020-adopt:/usr/lib/mr3020/adopt-shell',
    'etc/group': 'mr3020:x:453:',
    'etc/shadow': 'ubnt:!:0:0:99999:7:::',
    'etc/shells': '/usr/lib/mr3020/adopt-shell',
}.items():
    content = (root / path).read_text()
    # Rebuilding must not duplicate the restricted account or its shell.
    name = line.split(':', 1)[0]
    lines = [value for value in content.splitlines() if (value.split(':', 1)[0] != name if ':' in line else value != line)]
    (files / path).write_text('\n'.join(lines + [line]) + '\n')
    (files / path).chmod(0o600 if path == 'etc/shadow' else 0o644)

# The legacy init script predates these UCI controls; retain its startup flow
# while making the explicit forwarding restrictions effective with new SSH.
init = (root / 'etc/init.d/dropbear').read_text()
if "'LocalPortForward:bool:0'" not in init:
    init = init.replace("'GatewayPorts:bool:0' \\\n", "'GatewayPorts:bool:0' \\\n\t\t'LocalPortForward:bool:0' \\\n\t\t'RemotePortForward:bool:0' \\\n")
    init = init.replace('[ "${GatewayPorts}" -eq 1 ] && procd_append_param command -a',
                        '[ "${GatewayPorts}" -eq 1 ] && procd_append_param command -a\n\t[ "${LocalPortForward}" -eq 0 ] && procd_append_param command -j\n\t[ "${RemotePortForward}" -eq 0 ] && procd_append_param command -k')
assert "'LocalPortForward:bool:0'" in init
# This upstream Dropbear build requires -B for the blank-root first login.
# Consult the writable shadow file so a configured password remains required.
password_flag = '[ "${RootPasswordAuth}" -eq 0 ] && procd_append_param command -g'
assert init.count(password_flag) == 1
init = init.replace(password_flag, password_flag + '''
	if [ "${PasswordAuth}" -eq 1 ] && [ "${RootPasswordAuth}" -eq 1 ] &&
	   grep -q '^root::' /etc/shadow; then
		procd_append_param command -B
	fi''')

# Recovery clients use modern OpenSSH. Generate one host key on the device
# so recovery need not wait behind ECDSA and RSA generation on first boot.
old_key_types = 'for ktype in ecdsa rsa; do'
assert init.count(old_key_types) == 1
init = init.replace(old_key_types, 'for ktype in ed25519; do')

# First-boot key generation can wait for entropy. It must not hold up the
# subsequent network service, whose traffic also contributes entropy.
old_boot = 'boot()\n{\n\tBOOT=1\n\tstart "$@"\n}'
new_boot = 'boot()\n{\n\tBOOT=1\n\tstart "$@" </dev/null >/dev/null 2>&1 &\n}'
init = init.replace(old_boot, new_boot)
assert new_boot in init
(files / 'etc/init.d/dropbear').write_text(init)
(files / 'etc/init.d/dropbear').chmod(0o755)
# The old loader reads sysctl.conf after sysctl.d, so override router defaults
# at the end of that file. Tagged SSIDs must not route around UDR7 VLAN rules.
marker = '# MR3020 layer-2 AP'
sysctl = (root / 'etc/sysctl.conf').read_text().split(marker)[0].rstrip()
(files / 'etc/sysctl.conf').write_text(sysctl + '\n\n' + Path('/project/config/ap-sysctl.conf').read_text())

packages = Path('/project/config/stable19-packages.txt').read_text().strip()
result = Path('/build/stable19-result')
result.mkdir(exist_ok=True)
with (result / 'build.log').open('w') as log:
    subprocess.run(['make', 'image', 'PROFILE=tl-mr3020-v1', 'PACKAGES=' + packages, 'FILES=' + str(files)],
                   cwd=ib, stdout=log, stderr=subprocess.STDOUT, check=True)
image = ib / 'bin/targets/ar71xx/tiny/openwrt-19.07.10-ar71xx-tiny-tl-mr3020-v1-squashfs-factory.bin'
data = image.read_bytes()
assert struct.unpack_from('>I', data, 64)[0] == 0x30200001
assert kernel_bytes(data) == kernel_bytes(baseline), 'The board kernel changed'
assert struct.unpack_from('>2I', data, 144) == (0, 0), 'Unexpected bootloader payload'
offset, size = struct.unpack_from('>2I', data, 136)
end = offset + size
assert end <= 0x380000, 'Less than 256 KiB writable-space allowance'
subprocess.run([str(host_bin / 'mktplinkfw'), '-i', str(image)], check=True)
shipped = Path('/build/stable19-shipped-root')
extract(image, shipped)
for path, digest in original.items():
    assert hashlib.sha256((shipped / path).read_bytes()).hexdigest() == digest, 'Shipped core component changed: ' + path
assert (shipped / hostapd_script).read_bytes() == patched_hostapd.read_bytes()
assert not list(shipped.rglob('authorized_keys')), 'Unexpected baked-in SSH key'
assert any(line.startswith('root::') for line in (shipped / 'etc/shadow').read_text().splitlines())
assert any(line.startswith('ubnt:!:') for line in (shipped / 'etc/shadow').read_text().splitlines())
out = result / 'mr3020-v1-stable19-experiment-factory.bin'
shutil.copy2(image, out)
upgrade = image.with_name(image.name.replace('-factory.bin', '-sysupgrade.bin'))
upgrade_data = upgrade.read_bytes()
assert struct.unpack_from('>2I', upgrade_data, 64) == (0x30200001, 1)
assert struct.unpack_from('>2I', upgrade_data, 144) == (0, 0)
assert struct.unpack_from('>4I', upgrade_data, 128) == struct.unpack_from('>4I', data, 128)
assert data[512:end] == upgrade_data[512:end], 'Factory and upgrade payloads differ'
assert end <= len(upgrade_data) <= len(data), 'Invalid sysupgrade length'
inspection = subprocess.check_output([str(host_bin / 'mktplinkfw'), '-i', str(upgrade)], text=True)
assert '(ok)' in next(line for line in inspection.splitlines() if 'MD5Sum1' in line)
upgrade_out = result / 'mr3020-v1-stable19-experiment-sysupgrade.bin'
shutil.copy2(upgrade, upgrade_out)
report = {
    'sysupgrade': {'file': upgrade_out.name, 'sha256': hashlib.sha256(upgrade_data).hexdigest(),
                   'file_bytes': len(upgrade_data), 'factory_payload_identical': True},
    'file': out.name, 'sha256': hashlib.sha256(data).hexdigest(), 'file_bytes': len(data),
    'payload_end': end, 'writable_allowance_bytes': 0x3c0000 - ((end + 65535) // 65536) * 65536,
    'kernel_identical_to_official_component_baseline': True,
    'kernel_payload_sha256': hashlib.sha256(kernel_bytes(data)).hexdigest(),
    'unchanged_core_files': original, 'physical_boot_tested': False, 'flash_ready': False,
}
(result / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({key: value for key, value in report.items() if key != 'unchanged_core_files'}))
