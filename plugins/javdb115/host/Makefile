# Host (Linux) crypto fixture test. Not an iOS dylib.
CC ?= gcc
CFLAGS ?= -O2 -Wall
LDLIBS ?= -lcrypto

test_crypto_host: test_crypto_host.c avdb115_crypto.c avdb115_crypto.h
	$(CC) $(CFLAGS) -o $@ test_crypto_host.c avdb115_crypto.c $(LDLIBS)

.PHONY: test
test: test_crypto_host
	./test_crypto_host
