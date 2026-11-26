#!/usr/bin/env python3
"""Independent cross-implementation tests of the MIPS TNBU codec."""
import json, os, struct, subprocess, zlib
from pathlib import Path
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
ROOT=Path(os.environ.get('MR3020_TEST_ROOT','/build/openwrt/build_dir/target-mips_24kc_musl/root-ath79'))
BASE=Path('/build/ucode-unifi')
KEY=bytes.fromhex('00112233445566778899aabbccddeeff')
MAC=bytes.fromhex('020000000001')
IV=bytes(range(16))
count=0
def packet(plain,gcm,compressed=True):
    data=zlib.compress(plain) if compressed else plain
    n=len(data)+16 if gcm else (len(data)//16+1)*16
    h=b'TNBU'+struct.pack('>I6sH16sII',0,MAC,1+(2 if compressed else 0)+(8 if gcm else 0),IV,1,n)
    if gcm: return h+AESGCM(KEY).encrypt(IV,data,h)
    pad=16-len(data)%16
    enc=Cipher(algorithms.AES(KEY),modes.CBC(IV)).encryptor()
    return h+enc.update(data+bytes([pad])*pad)+enc.finalize()
def run(frame,plain='{"test":true}',gcm=True,key=KEY,mac=MAC):
    fixture=dict(mac=mac.hex(),key=key.hex(),iv=IV.hex(),packet=frame.hex(),plain=plain,gcm=gcm)
    p=BASE/'fixture.json'; p.write_text(json.dumps(fixture)); p.chmod(0o600)
    cmd=['qemu-mips','-cpu','24Kc','-L',str(ROOT),str(ROOT/'usr/bin/ucode'),'-L',str(BASE),'-F',f'input={p}',str(Path(__file__).with_name('check.uc'))]
    return json.loads(subprocess.check_output(cmd))
def assert_case(value):
    global count
    assert value
    count+=1
for gcm in (False,True):
    for compressed in (False,True):
        for size in (0,1,15,16,17,1024,65536):
            plain='x'*size
            got=run(packet(plain.encode(),gcm,compressed),plain,gcm)
            assert_case(got['decoded']==plain)
            encoded=bytes.fromhex(got['encoded']); h=encoded[:40]
            if gcm: data=AESGCM(KEY).decrypt(h[16:32],encoded[40:],h)
            else:
                dec=Cipher(algorithms.AES(KEY),modes.CBC(h[16:32])).decryptor()
                data=dec.update(encoded[40:])+dec.finalize(); data=data[:-data[-1]]
            assert_case(zlib.decompress(data).decode()==plain)
good=packet(b'{"test":true}',True)
for pos in (0,8,14,16,32,36,40,len(good)-1):
    bad=bytearray(good); bad[pos]^=1
    assert_case(run(bytes(bad))['decoded'] is None)
for bad in (b'',good[:39],good[:-1],good+b'x',packet(b'x'*65537,True),packet(b'x'*1048576,True)):
    assert_case(run(bad)['decoded'] is None)
assert_case(run(good,key=b'0'*16)['decoded'] is None)
assert_case(run(good,mac=b'0'*6)['decoded'] is None)
assert_case(run(good,plain='x'*65537)['encoded'] is None)
assert_case(run(good,key=b'bad')['encoded'] is None)
print(json.dumps({'passed':count,'runtime':'MIPS 24Kc under QEMU','hardware_tested':False}))
