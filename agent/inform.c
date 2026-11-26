/* SPDX-License-Identifier: GPL-2.0-or-later
 * Experimental bounded TNBU codec. Protocol reference:
 * https://github.com/antoniocosta/unifi-openwrt/blob/main/docs/internals.md
 * Uses upstream Mbed TLS for cryptography; no network/configuration actions.
 */
#include <ucode/module.h>
#include <mbedtls/aes.h>
#include <mbedtls/gcm.h>
#include <mbedtls/platform_util.h>
#include <sys/random.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
#include <unistd.h>
#define LIMIT 65536
static void put32(unsigned char *p, unsigned n) { p[0]=n>>24; p[1]=n>>16; p[2]=n>>8; p[3]=n; }
static unsigned get32(const unsigned char *p) { return (unsigned)p[0]<<24 | (unsigned)p[1]<<16 | (unsigned)p[2]<<8 | p[3]; }
static int valid(uc_value_t *v, size_t n) { return ucv_type(v)==UC_STRING && ucv_string_length(v)==n; }
static int random_iv(unsigned char *p) {
    size_t n=0;
    while(n<16) { ssize_t r=getrandom(p+n,16-n,0); if(r<0 && errno==EINTR) continue; if(r<=0) return -1; n+=r; }
    return 0;
}
static int cipher(int enc, int gcm, const unsigned char *key, unsigned char *h, unsigned char *in, size_t n, unsigned char *out) {
    int r;
    if(gcm) {
        mbedtls_gcm_context c; mbedtls_gcm_init(&c);
        r=mbedtls_gcm_setkey(&c,MBEDTLS_CIPHER_ID_AES,key,128);
        if(!r && enc) r=mbedtls_gcm_crypt_and_tag(&c,MBEDTLS_GCM_ENCRYPT,n,h+16,16,h,40,in,out,16,out+n);
        if(!r && !enc) r=mbedtls_gcm_auth_decrypt(&c,n,h+16,16,h,40,in+n,16,in,out);
        mbedtls_gcm_free(&c);
    } else {
        unsigned char iv[16]; memcpy(iv,h+16,16);
        mbedtls_aes_context c; mbedtls_aes_init(&c);
        r=enc ? mbedtls_aes_setkey_enc(&c,key,128) : mbedtls_aes_setkey_dec(&c,key,128);
        if(!r) r=mbedtls_aes_crypt_cbc(&c,enc?MBEDTLS_AES_ENCRYPT:MBEDTLS_AES_DECRYPT,n,iv,in,out);
        mbedtls_aes_free(&c);
    }
    return r;
}
static uc_value_t *encode(uc_vm_t *vm, size_t nargs) {
    uc_value_t *mac=uc_fn_arg(0), *key=uc_fn_arg(1), *plain=uc_fn_arg(2), *mode=uc_fn_arg(3), *iv=uc_fn_arg(4);
    if(!valid(mac,6)||!valid(key,16)||ucv_type(plain)!=UC_STRING||ucv_string_length(plain)>LIMIT) return NULL;
    int gcm=ucv_is_truish(mode); uLongf n=compressBound(ucv_string_length(plain));
    unsigned char *z=malloc(n+16), *frame=NULL; uc_value_t *ret=NULL;
    if(!z) return NULL;
    if(compress2(z,&n,(unsigned char *)ucv_string_get(plain),ucv_string_length(plain),Z_DEFAULT_COMPRESSION)!=Z_OK) goto done;
    size_t pad=gcm?0:16-(n%16), payload=n+(gcm?16:pad);
    frame=calloc(1,40+payload); if(!frame) goto done;
    memcpy(frame,"TNBU",4); memcpy(frame+8,ucv_string_get(mac),6); frame[15]=gcm?11:3;
    if(ucv_type(iv)!=UC_NULL) { if(!valid(iv,16)) goto done; memcpy(frame+16,ucv_string_get(iv),16); }
    else if(random_iv(frame+16)) goto done;
    put32(frame+32,1); put32(frame+36,payload);
    if(!gcm) memset(z+n,pad,pad);
    if(cipher(1,gcm,(unsigned char *)ucv_string_get(key),frame,z,n+pad,frame+40)) goto done;
    ret=ucv_string_new_length((char *)frame,40+payload);
done:
    mbedtls_platform_zeroize(z,n+16); free(z); free(frame); return ret;
}
static uc_value_t *decode(uc_vm_t *vm, size_t nargs) {
    uc_value_t *mac=uc_fn_arg(0), *key=uc_fn_arg(1), *packet=uc_fn_arg(2);
    if(!valid(mac,6)||!valid(key,16)||ucv_type(packet)!=UC_STRING) return NULL;
    size_t size=ucv_string_length(packet); unsigned char *h=(unsigned char *)ucv_string_get(packet);
    if(size<40||size>LIMIT+1024||memcmp(h,"TNBU",4)||memcmp(h+8,ucv_string_get(mac),6)||get32(h+32)!=1) return NULL;
    unsigned flags=(unsigned)h[14]<<8|h[15]; size_t len=get32(h+36);
    if((flags!=1&&flags!=3&&flags!=9&&flags!=11)||len!=size-40) return NULL;
    int gcm=!!(flags&8); if((gcm&&len<16)||(!gcm&&(!len||len%16))) return NULL;
    size_t n=len-(gcm?16:0), allocated=n; unsigned char *buf=malloc(n?n:1), *out=NULL; uc_value_t *ret=NULL;
    if(!buf) return NULL;
    if(cipher(0,gcm,(unsigned char *)ucv_string_get(key),h,h+40,n,buf)) goto done;
    if(!gcm) {
        unsigned pad=buf[n-1], bad=(pad<1||pad>16); unsigned char diff=0;
        for(size_t i=0;i<16;i++) diff|=(i<pad?buf[n-1-i]^pad:0);
        if(bad||diff) goto done;
        n-=pad;
    }
    if(flags&2) {
        uLongf cap=LIMIT; out=malloc(cap); if(!out) goto done;
        if(uncompress(out,&cap,buf,n)!=Z_OK) goto done;
        ret=ucv_string_new_length((char *)out,cap);
    } else if(n<=LIMIT) ret=ucv_string_new_length((char *)buf,n);
done:
    if(out) { mbedtls_platform_zeroize(out,LIMIT); free(out); }
    mbedtls_platform_zeroize(buf,allocated); free(buf); return ret;
}
static uc_value_t *sync_fd(uc_vm_t *vm, size_t nargs) {
    uc_value_t *arg=uc_fn_arg(0);
    if(ucv_type(arg)!=UC_INTEGER || ucv_int64_get(arg)<0 || ucv_int64_get(arg)>INT32_MAX) return NULL;
    return ucv_boolean_new(fsync((int)ucv_int64_get(arg))==0);
}
static const uc_function_list_t fns[]={ {"encode",encode},{"decode",decode},{"sync_fd",sync_fd} };
void uc_module_init(uc_vm_t *vm, uc_value_t *scope) { uc_function_list_register(scope,fns); }
