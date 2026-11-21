// AVDB115Crypto.m
// m115 protocol adapted from SheltonZhu/115driver (MIT).
// Logic mirrors AVDB/Services/Pan115Client.swift private enum Pan115Crypto.

#import "AVDB115Crypto.h"
#import <Security/Security.h>

static NSError *AVDB115CryptoError(NSString *msg) {
    return [NSError errorWithDomain:@"AVDB115Crypto" code:1 userInfo:@{NSLocalizedDescriptionKey: msg}];
}

static const uint8_t kSeed[] = {
    0xf0, 0xe5, 0x69, 0xae, 0xbf, 0xdc, 0xbf, 0x8a,
    0x1a, 0x45, 0xe8, 0xbe, 0x7d, 0xa6, 0x73, 0xb8,
    0xde, 0x8f, 0xe7, 0xc4, 0x45, 0xda, 0x86, 0xc4,
    0x9b, 0x64, 0x8b, 0x14, 0x6a, 0xb4, 0xf1, 0xaa,
    0x38, 0x01, 0x35, 0x9e, 0x26, 0x69, 0x2c, 0x86,
    0x00, 0x6b, 0x4f, 0xa5, 0x36, 0x34, 0x62, 0xa6,
    0x2a, 0x96, 0x68, 0x18, 0xf2, 0x4a, 0xfd, 0xbd,
    0x6b, 0x97, 0x8f, 0x4d, 0x8f, 0x89, 0x13, 0xb7,
    0x6c, 0x8e, 0x93, 0xed, 0x0e, 0x0d, 0x48, 0x3e,
    0xd7, 0x2f, 0x88, 0xd8, 0xfe, 0xfe, 0x7e, 0x86,
    0x50, 0x95, 0x4f, 0xd1, 0xeb, 0x83, 0x26, 0x34,
    0xdb, 0x66, 0x7b, 0x9c, 0x7e, 0x9d, 0x7a, 0x81,
    0x32, 0xea, 0xb6, 0x33, 0xde, 0x3a, 0xa9, 0x59,
    0x34, 0x66, 0x3b, 0xaa, 0xba, 0x81, 0x60, 0x48,
    0xb9, 0xd5, 0x81, 0x9c, 0xf8, 0x6c, 0x84, 0x77,
    0xff, 0x54, 0x78, 0x26, 0x5f, 0xbe, 0xe8, 0x1e,
    0x36, 0x9f, 0x34, 0x80, 0x5c, 0x45, 0x2c, 0x9b,
    0x76, 0xd5, 0x1b, 0x8f, 0xcc, 0xc3, 0xb8, 0xf5,
};

@implementation AVDB115Crypto

+ (NSArray<NSNumber *> *)deriveKey:(NSArray<NSNumber *> *)key count:(NSUInteger)count {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) {
        NSUInteger forward = count * index;
        NSUInteger reverse = count * (count - index - 1);
        uint8_t kb = (uint8_t)key[index].unsignedCharValue;
        uint8_t sum = (uint8_t)(kb + kSeed[forward]);
        [result addObject:@(sum ^ kSeed[reverse])];
    }
    return result;
}

+ (NSData *)deriveData:(NSData *)key count:(NSUInteger)count {
    const uint8_t *kb = key.bytes;
    NSMutableData *out = [NSMutableData dataWithLength:count];
    uint8_t *result = out.mutableBytes;
    for (NSUInteger index = 0; index < count; index++) {
        NSUInteger forward = count * index;
        NSUInteger reverse = count * (count - index - 1);
        uint8_t sum = (uint8_t)(kb[index] + kSeed[forward]);
        result[index] = sum ^ kSeed[reverse];
    }
    return out;
}

+ (NSData *)xorData:(NSData *)bytes key:(NSData *)key {
    const uint8_t *b = bytes.bytes;
    const uint8_t *k = key.bytes;
    NSUInteger n = bytes.length;
    NSUInteger kn = key.length;
    NSUInteger mod = n % 4;
    NSMutableData *out = [NSMutableData dataWithLength:n];
    uint8_t *o = out.mutableBytes;
    for (NSUInteger i = 0; i < n; i++) {
        NSUInteger ki = (i < mod ? i : i - mod) % kn;
        o[i] = b[i] ^ k[ki];
    }
    return out;
}

+ (NSData *)randomBytes:(NSUInteger)count error:(NSError **)error {
    NSMutableData *bytes = [NSMutableData dataWithLength:count];
    if (SecRandomCopyBytes(kSecRandomDefault, count, bytes.mutableBytes) != errSecSuccess) {
        if (error) *error = AVDB115CryptoError(@"随机数生成失败");
        return nil;
    }
    return bytes;
}

+ (NSData *)transform:(NSData *)input error:(NSError **)error {
    // PKCS#1 RSAPublicKey DER; positive 1024-bit modulus, exponent 65537.
    static const char *hex =
        "8686980c0f5a24c4b9d43020cd2c22703ff3f450756529058b1cf88f09b8602136477198a6e2683149659bd122c33592fdb5ad47944ad1ea4d36c6b172aad6338c3bb6ac6227502d010993ac967d1aef00f0c8e038de2e4d3bc2ec368af2e9f10a6f1eda4f7262f136420c07c331b871bf139f74f3010e3c4fe57df3afb71683";
    if (input.length != 128) {
        if (error) *error = AVDB115CryptoError(@"115 RSA 数据无效");
        return nil;
    }
    NSMutableData *mod = [NSMutableData data];
    for (const char *p = hex; *p; p += 2) {
        unsigned int byte = 0;
        sscanf(p, "%2x", &byte);
        uint8_t b = (uint8_t)byte;
        [mod appendBytes:&b length:1];
    }
    uint8_t prefix[] = {0x30, 0x81, 0x89, 0x02, 0x81, 0x81, 0x00};
    uint8_t suffix[] = {0x02, 0x03, 0x01, 0x00, 0x01};
    NSMutableData *der = [NSMutableData dataWithBytes:prefix length:sizeof(prefix)];
    [der appendData:mod];
    [der appendBytes:suffix length:sizeof(suffix)];

    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits: @1024
    };
    CFErrorRef cfError = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)der, (__bridge CFDictionaryRef)attrs, &cfError);
    if (!key) {
        if (error) *error = AVDB115CryptoError(@"115 RSA 数据无效");
        if (cfError) CFRelease(cfError);
        return nil;
    }
    CFDataRef out = SecKeyCreateEncryptedData(key, kSecKeyAlgorithmRSAEncryptionRaw, (__bridge CFDataRef)input, &cfError);
    CFRelease(key);
    if (!out) {
        if (error) *error = AVDB115CryptoError(@"115 RSA 数据无效");
        if (cfError) CFRelease(cfError);
        return nil;
    }
    NSData *result = (__bridge_transfer NSData *)out;
    return result;
}

+ (NSString *)encodeJSONData:(NSData *)data key:(NSData *)key error:(NSError **)error {
    static const uint8_t k12[] = {0x78,0x06,0xad,0x4c,0x33,0x86,0x5d,0x18,0x4c,0x01,0x3f,0x46};
    NSData *d4 = [self deriveData:key count:4];
    NSData *step1 = [self xorData:data key:d4];
    NSMutableData *reversed = [NSMutableData dataWithLength:step1.length];
    const uint8_t *s = step1.bytes;
    uint8_t *r = reversed.mutableBytes;
    for (NSUInteger i = 0; i < step1.length; i++) r[i] = s[step1.length - 1 - i];
    NSData *step2 = [self xorData:reversed key:[NSData dataWithBytes:k12 length:sizeof(k12)]];
    NSMutableData *payload = [NSMutableData dataWithData:key];
    [payload appendData:step2];

    NSMutableData *output = [NSMutableData data];
    const uint8_t *p = payload.bytes;
    NSUInteger n = payload.length;
    for (NSUInteger offset = 0; offset < n; offset += 117) {
        NSUInteger partLen = MIN((NSUInteger)117, n - offset);
        NSData *part = [NSData dataWithBytes:p + offset length:partLen];
        NSUInteger padLen = 125 - partLen;
        NSMutableData *padding = [[self randomBytes:padLen error:error] mutableCopy];
        if (!padding) return nil;
        uint8_t *pb = padding.mutableBytes;
        for (NSUInteger i = 0; i < padLen; i++) {
            while (pb[i] == 0) {
                NSData *one = [self randomBytes:1 error:error];
                if (!one) return nil;
                pb[i] = ((const uint8_t *)one.bytes)[0];
            }
        }
        NSMutableData *block = [NSMutableData data];
        uint8_t head[] = {0, 2};
        uint8_t z = 0;
        [block appendBytes:head length:2];
        [block appendData:padding];
        [block appendBytes:&z length:1];
        [block appendData:part];
        NSData *enc = [self transform:block error:error];
        if (!enc) return nil;
        [output appendData:enc];
    }
    return [output base64EncodedStringWithOptions:0];
}

+ (NSData *)decodeText:(NSString *)text key:(NSData *)key error:(NSError **)error {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:text options:0];
    if (!data || data.length == 0 || data.length % 128 != 0 || data.length > 1024 * 1024) {
        if (error) *error = AVDB115CryptoError(@"115 加密响应无效");
        return nil;
    }
    const uint8_t *bytes = data.bytes;
    NSMutableData *plain = [NSMutableData data];
    for (NSUInteger offset = 0; offset < data.length; offset += 128) {
        NSData *chunk = [NSData dataWithBytes:bytes + offset length:128];
        NSData *block = [self transform:chunk error:error];
        if (!block || block.length != 128) return nil;
        const uint8_t *b = block.bytes;
        if (b[0] != 0 || (b[1] != 1 && b[1] != 2)) {
            if (error) *error = AVDB115CryptoError(@"115 RSA 填充无效");
            return nil;
        }
        NSInteger end = -1;
        for (NSUInteger i = 2; i < 128; i++) {
            if (b[i] == 0) { end = (NSInteger)i; break; }
        }
        if (end < 10) {
            if (error) *error = AVDB115CryptoError(@"115 RSA 填充无效");
            return nil;
        }
        [plain appendBytes:b + end + 1 length:128 - (NSUInteger)end - 1];
    }
    if (plain.length < 16) {
        if (error) *error = AVDB115CryptoError(@"115 解密响应过短");
        return nil;
    }
    NSData *respKey = [plain subdataWithRange:NSMakeRange(0, 16)];
    NSData *body = [plain subdataWithRange:NSMakeRange(16, plain.length - 16)];
    NSData *d12 = [self deriveData:respKey count:12];
    NSData *x1 = [self xorData:body key:d12];
    NSMutableData *reversed = [NSMutableData dataWithLength:x1.length];
    const uint8_t *s = x1.bytes;
    uint8_t *r = reversed.mutableBytes;
    for (NSUInteger i = 0; i < x1.length; i++) r[i] = s[x1.length - 1 - i];
    NSData *d4 = [self deriveData:key count:4];
    return [self xorData:reversed key:d4];
}

@end
