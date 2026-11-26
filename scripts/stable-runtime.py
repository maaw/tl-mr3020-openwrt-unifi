#!/usr/bin/env python3
"""Stage private newer userspace; never replace the old system loader/libraries."""
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

source = Path('/build/mr3020-lab/root')
project = Path('/project')
output = Path('/build/stable19-runtime')
if output.exists():
    shutil.rmtree(output)
base = output / 'usr/lib/mr3020-runtime'
for path in ['bin', 'lib', 'ucode']:
    (base / path).mkdir(parents=True)

libraries = {}
def copy_elf(src, dst):
    shutil.copy2(src, dst, follow_symlinks=True)
    dynamic = subprocess.check_output(['readelf', '-d', str(src)], text=True)
    for name in re.findall(r'\(NEEDED\).*?\[(.*?)\]', dynamic):
        if name in libraries:
            continue
        found = next((source / path / name for path in ['lib', 'usr/lib']
                      if (source / path / name).exists()), None)
        if found is None:
            raise RuntimeError('Missing runtime library: ' + name)
        libraries[name] = hashlib.sha256(found.read_bytes()).hexdigest()
        copy_elf(found, base / 'lib' / name)

copy_elf(source / 'usr/bin/ucode', base / 'bin/ucode')
copy_elf(Path('/build/dropbear-current/dropbear'), base / 'bin/dropbear')
(base / 'bin/dropbearkey').symlink_to('dropbear')
(base / 'bin/scp').symlink_to('dropbear')
(base / 'lib/ld-musl-mips-sf.so.1').symlink_to('libc.so')
for name in ['fs', 'socket', 'uci', 'ubus']:
    copy_elf(source / ('usr/lib/ucode/' + name + '.so'), base / ('ucode/' + name + '.so'))
copy_elf(Path('/build/ucode-unifi/inform.so'), base / 'ucode/inform.so')

for path, name in [('usr/bin/ucode', 'ucode'), ('usr/sbin/dropbear', 'dropbear'), ('usr/bin/dropbearkey', 'dropbearkey'), ('usr/bin/scp', 'scp')]:
    target = output / path
    target.parent.mkdir(parents=True, exist_ok=True)
    if name != 'ucode':
        target.symlink_to('../lib/mr3020-runtime/bin/' + name)
        continue
    options = ' -L "$base/ucode"'
    launcher = base / ('bin/' + name + '-launch')
    launcher.write_text('#!/bin/sh\nbase=/usr/lib/mr3020-runtime\nexec "$base/lib/ld-musl-mips-sf.so.1" --library-path "$base/lib" "$base/bin/' + name + '"' + options + ' "$@"\n')
    launcher.chmod(0o755)
    # Copying an ordinary file onto the old dropbearkey symlink could instead
    # overwrite dropbear. Overlay explicit symlinks for all three launchers.
    target.symlink_to('../lib/mr3020-runtime/bin/' + name + '-launch')

agent = output / 'usr/lib/mr3020'
agent.mkdir()
for name in ['transport', 'discovery-wire', 'session', 'identity', 'persist', 'planner',
             'runner', 'adoption', 'apply', 'adopt-command', 'start', 'account', 'status', 'radio-status', 'bus']:
    shutil.copy2(project / ('agent/' + name + '.uc'), agent / (name + '.uc'))
shutil.copy2(project / 'config/adopt-shell', agent / 'adopt-shell')
(agent / 'adopt-shell').chmod(0o755)
for directory in ['etc/init.d', 'etc/rc.d', 'etc/uci-defaults', 'etc/config', 'lib/upgrade/keep.d']:
    (output / directory).mkdir(parents=True, exist_ok=True)
shutil.copy2(project / 'config/mr3020.init', output / 'etc/init.d/mr3020')
(output / 'etc/init.d/mr3020').chmod(0o755)
(output / 'etc/rc.d/S95mr3020').symlink_to('../init.d/mr3020')
shutil.copy2(project / 'config/99-mr3020-stable', output / 'etc/uci-defaults/99-mr3020-stable')
(output / 'etc/uci-defaults/99-mr3020-stable').chmod(0o755)
(output / 'etc/mr3020.json').write_text(json.dumps({
    'enabled': False,
    'controller': '',
    'allow_adoption': False,
    'model': 'U7LT',
    'virtual_network_override': True,
}) + '\n')
(output / 'lib/upgrade/keep.d/mr3020').write_text(
    '/etc/mr3020.json\n/etc/mr3020-state/state.json\n/etc/shadow\n/root/.ssh/authorized_keys\n'
)
(output / 'etc/config/network').write_text('''config interface 'loopback'
 option ifname 'lo'
 option proto 'static'
 option ipaddr '127.0.0.1'
 option netmask '255.0.0.0'
config interface 'lan'
 option type 'bridge'
 option ifname 'eth0'
 option proto 'dhcp'
 option delegate '0'
config interface 'rescue'
 option ifname 'br-lan'
 option proto 'static'
 option ipaddr '169.254.30.20'
 option netmask '255.255.0.0'
 option delegate '0'
''')
(output / 'etc/config/dropbear').write_text('''config dropbear 'main'
 option PasswordAuth 'on'
 option RootPasswordAuth 'on'
 option LocalPortForward 'off'
 option RemotePortForward 'off'
 option Port '22'
 list keyfile '/etc/dropbear/dropbear_ed25519_host_key'
''')
# Finish account setup in the assembled old root, keeping its original root line.
(base / 'manifest.json').write_text(json.dumps({'source': 'OpenWrt 25.12.6 userspace runtime', 'dropbear': '2026.94', 'private_libraries': libraries}, indent=2) + '\n')
print(json.dumps({'staged': str(output), 'private_library_count': len(libraries), 'replaces_system_libraries': False}))
