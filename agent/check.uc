import * as inform from 'inform';
let mac=hexdec(input.mac), key=hexdec(input.key);
let decoded=inform.decode(mac,key,hexdec(input.packet));
let encoded=inform.encode(mac,key,input.plain,input.gcm,hexdec(input.iv));
print({ decoded, encoded: encoded == null ? null : hexenc(encoded) });
