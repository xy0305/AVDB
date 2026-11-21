#pragma once
#include <stddef.h>
#include <stdint.h>

int avdb115_derive(const uint8_t *key, size_t count, uint8_t *out);
int avdb115_xor(const uint8_t *bytes, size_t n, const uint8_t *key, size_t kn, uint8_t *out);
int avdb115_transform(const uint8_t *input, size_t n, uint8_t *out);
