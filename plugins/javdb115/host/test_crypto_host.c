#include "avdb115_crypto.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int expect_eq(const char *name, const uint8_t *a, const uint8_t *b, size_t n) {
    if (memcmp(a, b, n) != 0) {
        fprintf(stderr, "FAIL %s\n", name);
        for (size_t i = 0; i < n; i++) {
            if (a[i] != b[i]) fprintf(stderr, "  [%zu] got %u want %u\n", i, a[i], b[i]);
        }
        return 1;
    }
    return 0;
}

int main(void) {
    FILE *f = fopen("tests/115-crypto-fixture.json", "r");
    if (!f) f = fopen("../tests/115-crypto-fixture.json", "r");
    if (!f) { perror("fixture"); return 1; }
    /* Minimal JSON number-array reader for the known fixture fields. */
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc((size_t)sz + 1);
    if (!buf) return 1;
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) return 1;
    buf[sz] = 0;
    fclose(f);

    int failed = 0;
    uint8_t key[16], d4[4], d12[12], raw_in[128], raw_out[128];
    /* Parse by scanning for field names then reading integers. */
    const char *fields[] = {"\"rawInput\"", "\"rawOutput\"", "\"key\"", "\"derived4\"", "\"derived12\""};
    uint8_t *dests[] = {raw_in, raw_out, key, d4, d12};
    size_t caps[] = {128, 128, 16, 4, 12};
    for (int fi = 0; fi < 5; fi++) {
        char *p = strstr(buf, fields[fi]);
        if (!p) { fprintf(stderr, "missing %s\n", fields[fi]); return 1; }
        p = strchr(p, '[');
        if (!p) return 1;
        size_t n = 0;
        p++;
        while (*p && *p != ']') {
            while (*p == ' ' || *p == '\n' || *p == '\r' || *p == '\t' || *p == ',') p++;
            if (*p == ']') break;
            dests[fi][n++] = (uint8_t)atoi(p);
            if (n > caps[fi]) { fprintf(stderr, "%s too long\n", fields[fi]); return 1; }
            while (*p == '-' || (*p >= '0' && *p <= '9')) p++;
        }
        if (n != caps[fi]) { fprintf(stderr, "%s count %zu want %zu\n", fields[fi], n, caps[fi]); return 1; }
    }

    uint8_t got4[4], got12[12], got_tf[128];
    avdb115_derive(key, 4, got4);
    avdb115_derive(key, 12, got12);
    failed |= expect_eq("derive4", got4, d4, 4);
    failed |= expect_eq("derive12", got12, d12, 12);
    if (avdb115_transform(raw_in, 128, got_tf) != 0) {
        fprintf(stderr, "FAIL transform rc\n");
        failed = 1;
    } else {
        failed |= expect_eq("transform", got_tf, raw_out, 128);
    }

    uint8_t tmp[251], back[251];
    for (int count = 0; count <= 250; count++) {
        for (int i = 0; i < count; i++) tmp[i] = (uint8_t)(i % 256);
        avdb115_xor(tmp, (size_t)count, key, 16, back);
        avdb115_xor(back, (size_t)count, key, 16, back);
        if (memcmp(tmp, back, (size_t)count) != 0) {
            fprintf(stderr, "FAIL xor identity count=%d\n", count);
            failed = 1;
            break;
        }
    }

    free(buf);
    if (failed) return 1;
    printf("PASS: Security raw RSA vector, XOR derivation, xor identity\n");
    return 0;
}
