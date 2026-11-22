#import "AVDB115PlaintextHarvest.h"
#import "AVDB115MagnetJSON.h"
#import <TargetConditionals.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR || defined(__APPLE__)
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <mach/vm_region.h>
#import <mach/vm_statistics.h>
#endif

// Same crash-safety rules as the v10/v11 scanner: heap-allocated state,
// vm_read_overwrite only, never raw-deref foreign pointers, fail empty.
static const double kBudgetSec = 0.30;
static const vm_size_t kMaxRead = 96ull * 1024ull * 1024ull;
static const vm_size_t kChunk = 256ull * 1024ull;

@implementation AVDB115PlaintextHarvest

+ (NSUInteger)harvestMatchingCatalog:(NSString *)number {
    NSUInteger added = 0;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR || defined(__APPLE__)
    @try {
        CFTimeInterval t0 = CFAbsoluteTimeGetCurrent();
        vm_size_t got = 0;
        uint8_t *buf = (uint8_t *)malloc(kChunk);
        if (!buf) {
            [AVDB115MagnetJSON setPlaintextHarvestCount:0];
            return 0;
        }
        vm_address_t addr = 0;
        vm_size_t size = 0;
        while (addr + size >= addr) {
            if (CFAbsoluteTimeGetCurrent() - t0 > kBudgetSec) break;
            if (got >= kMaxRead) break;
            addr += size;
            size = 0;
            vm_region_basic_info_data_64_t info;
            mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
            mach_port_t obj = MACH_PORT_NULL;
            kern_return_t kr = vm_region_64(mach_task_self(),
                                            &addr, &size,
                                            VM_REGION_BASIC_INFO_64,
                                            (vm_region_info_t)&info,
                                            &count, &obj);
            if (obj != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), obj);
            if (kr != KERN_SUCCESS) break;
            // Only readable, non-executable data (heap / malloc / IO buffers).
            if (!(info.protection & VM_PROT_READ)) continue;
            if (info.protection & VM_PROT_EXECUTE) continue;
            if (size < 32) continue;

            vm_address_t off = 0;
            while (off < size) {
                if (CFAbsoluteTimeGetCurrent() - t0 > kBudgetSec) break;
                if (got >= kMaxRead) break;
                vm_size_t want = kChunk;
                if (want > size - off) want = size - off;
                vm_size_t out = 0;
                kr = vm_read_overwrite(mach_task_self(), addr + off, want,
                                       (vm_address_t)buf, &out);
                off += want;
                if (kr != KERN_SUCCESS || out < 24) continue;
                got += out;
                added += [self harvestBuffer:buf length:out catalog:number];
            }
        }
        free(buf);
    } @catch (NSException *ex) {
        added = 0;
    }
#endif
    [AVDB115MagnetJSON setPlaintextHarvestCount:added];
    return added;
}

+ (NSUInteger)harvestBuffer:(const uint8_t *)buf length:(NSUInteger)len catalog:(NSString *)number {
    if (!buf || len < 24) return 0;
    // Cheap needle: "hash" or "ed2k" / "magnet" before attempting UTF-8 parse.
    const uint8_t *p = buf;
    const uint8_t *end = buf + len;
    NSUInteger added = 0;
    while (p + 8 < end) {
        const uint8_t *hit = NULL;
        for (const uint8_t *q = p; q + 6 < end; q++) {
            if (q[0] == '"' && q[1] == 'h' && q[2] == 'a' && q[3] == 's' && q[4] == 'h' && q[5] == '"') {
                hit = q; break;
            }
            if ((q[0] == 'e' || q[0] == 'E') && (q[1] == 'd' || q[1] == 'D') &&
                (q[2] == '2') && (q[3] == 'k' || q[3] == 'K')) {
                hit = q; break;
            }
        }
        if (!hit) break;
        const uint8_t *w0 = hit > buf + 512 ? hit - 512 : buf;
        const uint8_t *w1 = hit + 512 < end ? hit + 512 : end;
        NSUInteger wlen = (NSUInteger)(w1 - w0);
        added += [AVDB115MagnetJSON ingestUTF8Bytes:w0 length:wlen catalogHint:number];
        p = hit + 6;
        if (added > 64) break;
    }
    return added;
}

@end
