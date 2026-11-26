#!/usr/bin/env python3
"""Repack the pinned, built minimal image. Never writes a physical device."""
import hashlib, json, os, shutil, struct, subprocess
from pathlib import Path
ow=Path('/build/openwrt')
lab=Path('/build/mr3020-lab'); lab.mkdir(exist_ok=True)
key=Path('/project/private/authorized_keys')
if key.is_file() and not key.read_text().strip().startswith('ssh-ed25519 '):
    raise SystemExit('Supply your SSH public key in private/authorized_keys (never a private key).')
source=ow/'bin/targets/ath79/tiny/openwrt-ath79-tiny-tplink_tl-mr3020-v1-squashfs-factory.bin'
data=source.read_bytes()
assert struct.unpack_from('>I',data,64)[0]==0x30200001, 'Wrong board ID'
kernel_offset,kernel_size,root_offset,root_size=struct.unpack_from('>4I',data,128)
assert kernel_offset==512 and root_offset+root_size<=len(data)
(lab/'kernel.bin').write_bytes(data[kernel_offset:kernel_offset+kernel_size])
root=lab/'root'
if root.exists(): shutil.rmtree(root)
run=lambda args: subprocess.run([str(a) for a in args],check=True,cwd=ow)
# Extract without creating the device node as an unprivileged builder.
# The image builder restores /dev/console via a pseudo-file below.
run([ow/'staging_dir/host/bin/unsquashfs4','-no-progress','-excludes','-o',root_offset,'-d',root,source,'dev/console'])
for p in [root/'lib/apk',root/'etc/apk']:
    if p.exists(): shutil.rmtree(p)
for d in ['etc/dropbear','usr/lib/ucode','usr/lib/mr3020','usr/share/mr3020-prototype']:
    (root/d).mkdir(parents=True,exist_ok=True)
if key.is_file():
    shutil.copyfile(key, root/'etc/dropbear/authorized_keys')
    (root/'etc/dropbear/authorized_keys').chmod(0o600)
shutil.copyfile('/project/config/99-mr3020-lab',root/'etc/uci-defaults/99-mr3020-lab')
(root/'etc/uci-defaults/99-mr3020-lab').chmod(0o755)
with (root/'etc/sysctl.conf').open('a') as f:
    f.write('\n' + Path('/project/config/ap-sysctl.conf').read_text())
shutil.copyfile('/build/ucode-unifi/inform.so',root/'usr/lib/ucode/inform.so')
shutil.copyfile('/project/agent/planner.uc',root/'usr/lib/ucode/planner.uc')
socket_module=next((ow/'build_dir/target-mips_24kc_musl').glob('ucode-*/ipkg-mips_24kc/ucode-mod-socket/usr/lib/ucode/socket.so'),None)
if socket_module is None: raise SystemExit('Build the ucode socket module first')
shutil.copyfile(socket_module,root/'usr/lib/ucode/socket.so')
for name in ['transport.uc','discovery-wire.uc','session.uc','identity.uc','persist.uc','planner.uc','runner.uc','adoption.uc','apply.uc','adopt-command.uc','start.uc','account.uc','status.uc','radio-status.uc','bus.uc']:
    shutil.copyfile('/project/agent/'+name,root/'usr/lib/mr3020'/name)
# No synthetic identity/scripts in the flashable image.
for path in [root/'usr/share/mr3020-prototype',root/'usr/lib/ucode/planner.uc']:
    if path.is_dir(): shutil.rmtree(path)
    elif path.exists(): path.unlink()
shutil.copyfile('/project/config/mr3020.init',root/'etc/init.d/mr3020')
(root/'etc/init.d/mr3020').chmod(0o755)
(root/'etc/mr3020.json').write_text(json.dumps({'enabled':False,'controller':'','allow_adoption':False})+'\n')
(root/'etc/rc.d/S95mr3020').symlink_to('../init.d/mr3020')
shutil.copyfile('/project/config/adopt-shell',root/'usr/lib/mr3020/adopt-shell')
(root/'usr/lib/mr3020/adopt-shell').chmod(0o755)
with (root/'etc/shells').open('a') as f: f.write('/usr/lib/mr3020/adopt-shell\n')
# Protocol-only account. Port 22 remains key-only; port 2222 forces the validated
# adoption receiver and disables forwarding and root logins.
with (root/'etc/passwd').open('a') as f: f.write('ubnt:x:453:453:UniFi adoption only:/var/run/mr3020-adopt:/usr/lib/mr3020/adopt-shell\n')
with (root/'etc/group').open('a') as f: f.write('mr3020:x:453:\n')
with (root/'etc/shadow').open('a') as f: f.write('ubnt:!:0:0:99999:7:::\n')
fs=lab/'root.squashfs'
run([ow/'staging_dir/host/bin/mksquashfs4',root,fs,'-nopad','-noappend','-root-owned','-comp','xz','-Xpreset','9','-Xe','-Xlc','0','-Xlp','2','-Xpb','2','-b','512k','-p','/dev/console c 600 0 0 5 1','-no-xattrs','-processors','4'])
out=lab/'mr3020-v1-lab-factory.bin'
tool=ow/'staging_dir/host/bin/mktplinkfw'
run([tool,'-H','0x30200001','-W','0x1','-F','4Mlzma','-N','OpenWrt','-V','25.12.6-lab','-m','1','-k',lab/'kernel.bin','-r',fs,'-o',out,'-j','-X','0x40000','-a','0x4'])
run([tool,'-i',out])
print(json.dumps({'file':str(out),'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'boot_tested':False,'unifi_agent_complete':False}))
