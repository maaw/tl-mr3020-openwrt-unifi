import os, subprocess, tempfile
from pathlib import Path
root=Path('/build/openwrt/build_dir/target-mips_24kc_musl/root-ath79')
with tempfile.TemporaryDirectory(prefix='mr3020-recovery-',dir='/build') as d:
    p=Path(d); (p/'config').mkdir(); (p/'bin').mkdir()
    (p/'config/network').write_text("config interface 'lan'\n option device 'br-lan'\n option proto 'static'\n option ipaddr '192.168.1.1/24'\nconfig device\n option name 'br-lan'\n option type 'bridge'\n list ports 'eth0'\n")
    (p/'config/dropbear').write_text("config dropbear 'main'\n option PasswordAuth 'on'\n option RootPasswordAuth 'on'\n")
    (p/'config/system').write_text("config system\n option hostname 'OpenWrt'\n")
    cmd=['qemu-mips','-cpu','24Kc','-L',str(root),str(root/'sbin/uci'),'-c',str(p/'config')]
    import shlex
    shim=p/'bin/uci'; shim.write_text('#!/bin/sh\nexec '+shlex.join(cmd)+' "$@"\n'); shim.chmod(0o755)
    env=dict(os.environ,PATH=str(p/'bin')+':'+os.environ['PATH'])
    def get(k): return subprocess.check_output(cmd+['get',k],text=True).strip()
    for _ in range(2):
        subprocess.run(['sh','/project/config/99-mr3020-lab'],env=env,check=True)
        assert get('network.lan.proto')=='dhcp'
        assert get('network.lan.device')=='br-lan'
        assert get('network.rescue.device')=='br-lan'
        assert get('network.rescue.proto')=='static'
        assert get('network.rescue.ipaddr')=='169.254.30.20'
        assert get('network.rescue.netmask')=='255.255.0.0'
        assert get('dropbear.main.PasswordAuth')=='off'
        assert get('dropbear.main.RootPasswordAuth')=='off'
        assert get('system.@system[0].hostname')=='mr3020-lab'
    print('18 recovery configuration assertions passed using the MIPS UCI binary; initialization is idempotent. Hardware networking remains untested.')
