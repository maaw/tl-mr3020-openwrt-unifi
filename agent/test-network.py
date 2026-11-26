#!/usr/bin/env python3
import json, socketserver, subprocess, threading, os
from pathlib import Path
ROOT=Path(os.environ.get('MR3020_TEST_ROOT','/build/openwrt/build_dir/target-mips_24kc_musl/root-ath79'))
class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(3)
        request=b''
        while b'\r\n\r\n' not in request: request+=self.request.recv(4096)
        head,body=request.split(b'\r\n\r\n',1)
        while len(body)<9: body+=self.request.recv(4096)
        assert body==b'test-body'
        self.request.sendall(self.server.response)
cases=[
    (b'HTTP/1.1 404 \r\nContent-Length: 0\r\n\r\n',404,'',True),
    (b'HTTP/1.0 200 OK\r\nContent-Length: 3\r\n\r\n\x00\xffx',200,'00ff78',True),
    (b'HTTP/1.0 200 OK\r\n\r\nabc',200,'616263',True),
    (b'HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabc',200,'',False),
    (b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nabc',200,'',False),
    (b'HTTP/1.1 200 OK\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n',200,'',False),
    (b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n',200,'',False),
    (b'HTTP/1.1 200 OK\r\nContent-Length: 70000\r\n\r\n',200,'',False),
    (b'HTTP/1.1 200 OK\r\nX: '+b'x'*4200+b'\r\n\r\n',200,'',False),
]
passed=0
for raw,status,expected,success in cases:
    with socketserver.TCPServer(('127.0.0.1',0),Handler) as server:
        server.response=raw
        thread=threading.Thread(target=server.handle_request); thread.start()
        args=['qemu-mips','-cpu','24Kc','-L',str(ROOT),str(ROOT/'usr/bin/ucode'),'-L','/build/ucode-unifi','-L','/project/agent',
              '-D',f'test_port={server.server_address[1]}','-D',f'expected_status={status}','-D',f'expected_hex={json.dumps(expected)}','/project/agent/test-network.uc']
        result=subprocess.run(args,capture_output=True,text=True,timeout=12)
        thread.join(timeout=4)
        if (result.returncode==0)!=success:
            raise AssertionError((raw[:70],result.stdout,result.stderr))
        passed+=1
print(json.dumps({'http_cases_passed':passed,'discovery_checks_per_case':6,'hardware_tested':False}))
