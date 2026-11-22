#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// dyld slide of App.framework (JavDB AOT image). Does not use
/// _kDartSnapshotText alone: that symbol can live in Flutter.framework
/// and would yield a wrong slide, so a prologue hook would refuse to install.
uint64_t AVDB115AppVmSlide(void);

/// Compare `n` bytes at `addr` with `expected` via vm_read_overwrite.
int AVDB115PrologueMatches(uint64_t addr, const uint8_t *expected, size_t n);

/// Wrap a 16-byte Dart function entry with `wrapper`. `orig_slot` receives
/// an RX trampoline (stolen 16 bytes + jump back to entry+16). Fails safe
/// if the prologue does not match or text is not writable.
int AVDB115InstallDartEntryHook(uint64_t unslid_vm,
                                const uint8_t expected_prologue[16],
                                void *wrapper,
                                void **orig_slot,
                                const char *name);

#ifdef __cplusplus
}
#endif
