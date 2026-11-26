#!/usr/bin/env python3
"""Run the MIPS agent against a disposable independent controller stub."""
import json, socket, socketserver, struct, subprocess, threading, zlib, os
from pathlib import Path
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
FACTORY=bytes.fromhex('ba86f2bbe107c7c57eb5f2690775c712')
NEW=bytes.fromhex('00112233445566778899aabbccddeeff')
MAC=bytes.fromhex('023020000001')
errors=[]; received=[]; discovery=[]
def decode(data,key):
    assert data[:4]==b'TNBU' and data[8:14]==MAC
    flags=struct.unpack('>H',data[14:16])[0]
    assert struct.unpack('>I',data[36:40])[0]==len(data)-40
    if flags&8: clear=AESGCM(key).decrypt(data[16:32],data[40:],data[:40])
    else:
        dec=Cipher(algorithms.AES(key),modes.CBC(data[16:32])).decryptor()
        clear=dec.update(data[40:])+dec.finalize(); clear=clear[:-clear[-1]]
    return json.loads(zlib.decompress(clear) if flags&2 else clear)
def encode(data,key,gcm):
    clear=json.dumps(data).encode(); iv=os.urandom(16)
    size=len(clear)+16 if gcm else (len(clear)//16+1)*16
    h=b'TNBU'+struct.pack('>I6sH16sII',0,MAC,9 if gcm else 1,iv,1,size)
    if gcm: return h+AESGCM(key).encrypt(iv,clear,h)
    pad=16-len(clear)%16
    enc=Cipher(algorithms.AES(key),modes.CBC(iv)).encryptor()
    return h+enc.update(clear+bytes([pad])*pad)+enc.finalize()
system='wireless.1.ssid=IoT\nwireless.1.parent=wifi0\nwireless.1.devname=wifi0ap0\naaa.1.wpa=2\naaa.1.wpa.psk=test-password\naaa.1.wpa.key.1.mgmt=WPA-PSK\nbridge.2.devname=br0.2\nbridge.2.port.1.devname=wifi0ap0\n'
class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            self.request.settimeout(3); raw=b''
            while b'\r\n\r\n' not in raw: raw+=self.request.recv(4096)
            header,body=raw.split(b'\r\n\r\n',1)
            n=int(next(x.split(b':',1)[1] for x in header.split(b'\r\n') if x.lower().startswith(b'content-length:')))
            while len(body)<n: body+=self.request.recv(4096)
            i=len(received); key=FACTORY if i==0 else NEW
            payload=decode(body,key); received.append(payload)
            assert payload['mac']=='02:30:20:00:00:01'
            assert payload['cfgversion']=='0'  # No false acknowledgement of un-applied settings.
            if i==0:
                assert payload['default'] is True
                reply={'_type':'setparam','mgmt_cfg':'authkey='+NEW.hex()+'\nuse_aes_gcm=true'}
            elif i==1:
                assert payload['default'] is False
                reply={'_type':'setparam','system_cfg':system,'cfgversion':'123'}
            else: reply={'_type':'noop','interval':10}
            out=encode(reply,key,i>0)
            self.request.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: '+str(len(out)).encode()+b'\r\n\r\n'+out)
        except Exception as e: errors.append(repr(e))
udp=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); udp.bind(('127.0.0.1',0)); udp.settimeout(8)
probe_socket=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); probe_socket.bind(('127.0.0.1',0)); listen_port=probe_socket.getsockname()[1]; probe_socket.close()
def udp_work():
    try:
        packet,addr=udp.recvfrom(1024); assert packet[:2]==b'\x02\x06'; discovery.append('announce')
        udp.sendto(b'\x02\x08\x00\x00',addr)
        answer,_=udp.recvfrom(1024); assert answer[:2]==b'\x02\x09'; discovery.append('probe-reply')
    except Exception as e: errors.append(repr(e))
with socketserver.TCPServer(('127.0.0.1',0),Handler) as server:
    t=threading.Thread(target=server.serve_forever); t.start()
    u=threading.Thread(target=udp_work); u.start()
    p={'enabled':True,'mac':MAC.hex(),'ip':'127.0.0.1','controller':'127.0.0.1','hostname':'mr3020-test',
       'port':server.server_address[1],'rounds':3,'test_interval':2,'allow_adoption':True,
       'discovery_port':listen_port,'discovery_target_port':udp.getsockname()[1]}
    root=Path(os.environ.get('MR3020_TEST_ROOT','/build/openwrt/build_dir/target-mips_24kc_musl/root-ath79'))
    cmd=['qemu-mips','-cpu','24Kc','-L',str(root),str(root/'usr/bin/ucode'),'-L',str(root/'usr/lib/ucode'),'-L','/build/ucode-unifi','-L','/project/agent','-D','profile='+json.dumps(p),'/project/agent/runner.uc']
    try: result=subprocess.run(cmd,capture_output=True,text=True,timeout=20)
    finally: server.shutdown(); t.join(); u.join(timeout=9); udp.close()
assert result.returncode==0,(result.stdout,result.stderr)
assert not errors, errors
assert len(received)==3 and discovery==['announce','probe-reply'],(len(received),discovery,result.stdout)
assert 'configuration-received-not-applied' in result.stdout
assert '"planned_ssids": 1' in result.stdout,result.stdout
assert NEW.hex() not in result.stdout and 'test-password' not in result.stdout
print(json.dumps({'mips_inform_rounds':len(received),'udp':discovery,'cbc_to_gcm_handoff':True,'wpa2_vlan_planned':True,'configuration_applied':False,'real_controller_tested':False}))
