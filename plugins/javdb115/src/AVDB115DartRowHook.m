// Isolated runtime hook: wrap MoviePageState._getButtonLine and append
// two same-style MyInkWell chips ("推送到 115", "115 播放") after the
// existing Consumer. See analysis/movie-detail-aot/disasm/ and
// tests/test_dart_heap_layout.py for the layouts this follows.
//
// Additive only: no payment / VIP / auth circumvention, no getMovieMagnets
// hook, no replacement of 離線觀看, no static rewrite of the 0x3b4 body.

#import "AVDB115DartRowHook.h"
#import "AVDB115DetailActions.h"
#import "AVDB115AppSlide.h"

#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <pthread.h>
#import <string.h>
#import <sys/mman.h>
#import <libkern/OSCacheControl.h>

#if defined(__arm64__)

#pragma mark - Verified constants (JavDB 1.9.41 / Dart 3.13.7 iOS uncompressed)

// Unslid VM addresses = FAT file offset - 0x4000.
static const uint64_t kVMGetButtonLine   = 0x3bd144;
static const uint64_t kVMAllocObject     = 0x801a3c; // 0x805a3c
static const uint64_t kVMAllocArray      = 0x802da0; // 0x806da0
static const uint64_t kVMAllocClosure    = 0x801e9c; // 0x805e9c
static const uint64_t kVMAllocMyInkWell  = 0x269bd8; // 0x26dbd8
static const uint64_t kVMAllocContainer  = 0xc650c;  // 0xca50c
static const uint64_t kVMAllocText       = 0xc6524;  // 0xca524

static const uint32_t kCidTwoByteString = 95;
static const uint32_t kCidArray         = 90;
static const uint32_t kCidGOA           = 92;
static const uint32_t kCidClosure       = 57;
static const uint32_t kCidMyInkWell     = 4092;
static const uint32_t kCidText          = 3985;
static const uint32_t kCidWrap          = 4533;

static const uint32_t kNewTags          = 0x1c;
static const uint32_t kHeaderTwoByte32  = 0x5f21c; // cid 95, size_tag 2, tags 0x1c
static const uint64_t kClosureFlags     = 0x40;    // passed as x2 to AllocateClosure
static const uint64_t kPPWantWatchFn    = 0x22300; // Function template (void callback)
static const uint32_t kStolenBytes      = 16;

// Tagged-pointer field offsets (ldur/stur immediates).
static const int kOffArrayLength     = 0x0f;
static const int kOffArrayElem0      = 0x17;
static const int kOffGOALength       = 0x0f;
static const int kOffGOAData         = 0x17;
static const int kOffWrapChildren    = 0x0f;
static const int kOffMyInkWellChild  = 0x0f;
static const int kOffMyInkWellOnTap  = 0x17;
static const int kOffTextData        = 0x0f;
static const int kOffTextStyle       = 0x1f;
static const int kOffClosureEntry    = 0x07;
static const int kOffStringLengthU   = 0x08; // untagged
static const int kOffStringDataU     = 0x10;

// Precomputed UTF-16LE so the append path does not allocate ObjC objects.
static const uint16_t kLabelPushU16[] = {0x63a8, 0x9001, 0x5230, 0x0020, 0x0031, 0x0031, 0x0035};
static const uint16_t kLabelPlayU16[] = {0x0031, 0x0031, 0x0035, 0x0020, 0x64ad, 0x653e};

#pragma mark - State

static uint64_t gSlide = 0;
static uint8_t gStolen[16];
void *AVDB115OriginalTrampoline = NULL; // executable: stolen 16 + ldr/br back
static BOOL gInstalled = NO;
static void *gHookPage = NULL;

void AVDB115DartOnPushTrampoline(void);
void AVDB115DartOnPlayTrampoline(void);
uint64_t AVDB115Append115ChipsC(uint64_t wrap, uint64_t dart_sp, uint64_t x22,
                                uint64_t x26, uint64_t x27, uint64_t x28);

#pragma mark - Heap helpers

static inline BOOL AVDB115IsSmi(uint64_t p) { return (p & 1u) == 0; }
static inline BOOL AVDB115IsHeap(uint64_t p) { return (p & 1u) != 0; }
static inline int64_t AVDB115SmiVal(uint64_t p) { return (int64_t)p >> 1; }
static inline uint64_t AVDB115Smi(int64_t n) { return ((uint64_t)n) << 1; }

static uint32_t AVDB115Cid(uint64_t tagged) {
    if (!AVDB115IsHeap(tagged)) return 0;
    uint64_t h = *(const uint64_t *)(tagged - 1);
    return (uint32_t)((h >> 12) & 0xFFFFF);
}

static inline uint64_t AVDB115Load(uint64_t tagged, int off) {
    return *(const uint64_t *)(tagged + (uint64_t)off);
}

static inline void AVDB115Store(uint64_t tagged, int off, uint64_t value) {
    *(uint64_t *)(tagged + (uint64_t)off) = value;
}

/// Generational write-barrier predicate copied from handleTap / AllocateContext.
/// If it says a barrier is required, we abort the mutation rather than guess
/// the 0x8072ec calling convention.
static BOOL AVDB115NeedsWriteBarrier(uint64_t object, uint64_t value, uint64_t heapBits) {
    if (!AVDB115IsHeap(object) || !AVDB115IsHeap(value)) return NO;
    uint8_t destTag = *(const uint8_t *)(object - 1);
    uint8_t valTag  = *(const uint8_t *)(value - 1);
    uint64_t mixed  = ((uint64_t)valTag) & (((uint64_t)destTag) >> 2);
    return (mixed & (heapBits >> 32)) != 0;
}

#pragma mark - Dart stub calls (C ABI in, Dart ABI at the blr)

typedef struct {
    uint64_t stub;
    uint64_t dart_sp;
    uint64_t x1, x2, x3;
    uint64_t x22, x26, x27, x28;
    uint64_t result;
} AVDB115DartCall;

// x0 = &AVDB115DartCall. Preserves the C frame; sets Dart reserved regs only
// around the stub blr.
static void AVDB115CallDartStub(AVDB115DartCall *c) {
    // Keep the struct pointer in callee-saved x19 so a clobbered input
    // register cannot dangle across the stub blr.
    asm volatile(
        "stp x19, x20, [sp, #-16]!\n"
        "mov x19, %[c]\n"
        "ldp x1, x2, [x19, #16]\n"
        "ldr x3, [x19, #32]\n"
        "ldr x15, [x19, #8]\n"
        "ldr x22, [x19, #40]\n"
        "ldr x26, [x19, #48]\n"
        "ldr x27, [x19, #56]\n"
        "ldr x28, [x19, #64]\n"
        "ldr x16, [x19]\n"
        "stp x29, x30, [sp, #-16]!\n"
        "blr x16\n"
        "ldp x29, x30, [sp], #16\n"
        "str x0, [x19, #72]\n"
        "ldp x19, x20, [sp], #16\n"
        :
        : [c] "r"(c)
        : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7",
          "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15",
          "x16", "x17", "x22", "x26", "x27", "x28", "memory", "cc"
    );
}

typedef struct {
    uint64_t dart_sp;
    uint64_t x22, x26, x27, x28;
} AVDB115DartRegs;

static uint64_t AVDB115Stub(uint64_t vm, uint64_t x1, uint64_t x2, uint64_t x3,
                            const AVDB115DartRegs *r) {
    AVDB115DartCall c = {0};
    c.stub = gSlide + vm;
    c.dart_sp = r->dart_sp;
    c.x1 = x1;
    c.x2 = x2;
    c.x3 = x3;
    c.x22 = r->x22;
    c.x26 = r->x26;
    c.x27 = r->x27;
    c.x28 = r->x28;
    AVDB115CallDartStub(&c);
    return c.result;
}

#pragma mark - Object construction

static uint64_t AVDB115NewTwoByteString(const uint16_t *units, uint32_t n, const AVDB115DartRegs *r) {
    if (!units || n == 0 || n > 16) return r->x22;
    uint64_t s = AVDB115Stub(kVMAllocObject, r->x22, kHeaderTwoByte32, 0, r);
    if (!AVDB115IsHeap(s) || AVDB115Cid(s) != kCidTwoByteString) return r->x22;
    uint8_t *raw = (uint8_t *)(s - 1);
    *(uint64_t *)(raw + kOffStringLengthU) = AVDB115Smi((int64_t)n);
    memcpy(raw + kOffStringDataU, units, (size_t)n * 2);
    return s;
}

static uint64_t AVDB115NewClosure(uint64_t entry, const AVDB115DartRegs *r) {
    uint64_t function = *(const uint64_t *)(r->x27 + kPPWantWatchFn);
    if (!AVDB115IsHeap(function)) return r->x22;
    uint64_t c = AVDB115Stub(kVMAllocClosure, function, kClosureFlags, r->x22, r);
    if (!AVDB115IsHeap(c) || AVDB115Cid(c) != kCidClosure) return r->x22;
    // Patch the cached entry_point used by InkWell.handleTap (`blr [closure,#7]`).
    AVDB115Store(c, kOffClosureEntry, entry);
    return c;
}

static uint64_t AVDB115FindText(uint64_t container, uint64_t nullv) {
    if (!AVDB115IsHeap(container)) return nullv;
    // Container instance is 0x68 bytes; fields live after the header.
    for (int off = 0x07; off <= 0x5f; off += 8) {
        uint64_t f = AVDB115Load(container, off);
        if (AVDB115IsHeap(f) && AVDB115Cid(f) == kCidText) return f;
    }
    return nullv;
}

static uint64_t AVDB115CloneChip(uint64_t templateInk, uint64_t label, uint64_t onTap,
                                 const AVDB115DartRegs *r) {
    uint64_t nullv = r->x22;
    if (AVDB115Cid(templateInk) != kCidMyInkWell) return nullv;
    uint64_t oldContainer = AVDB115Load(templateInk, kOffMyInkWellChild);
    uint64_t oldText = AVDB115FindText(oldContainer, nullv);
    if (oldText == nullv) return nullv;
    uint64_t style = AVDB115Load(oldText, kOffTextStyle);

    uint64_t text = AVDB115Stub(kVMAllocText, 0, 0, 0, r);
    if (!AVDB115IsHeap(text) || AVDB115Cid(text) != kCidText) return nullv;
    AVDB115Store(text, kOffTextData, label);
    AVDB115Store(text, kOffTextStyle, style);

    uint64_t container = AVDB115Stub(kVMAllocContainer, 0, 0, 0, r);
    if (!AVDB115IsHeap(container)) return nullv;
    // Copy instance fields (skip header so the new-space tags stay), then
    // replace the Text child wherever it sat on the template.
    memcpy((void *)(container - 1 + 8), (const void *)(oldContainer - 1 + 8), 0x68 - 8);
    BOOL replaced = NO;
    for (int off = 0x07; off <= 0x5f; off += 8) {
        uint64_t f = AVDB115Load(container, off);
        if (f == oldText) {
            if (AVDB115NeedsWriteBarrier(container, text, r->x28)) return nullv;
            AVDB115Store(container, off, text);
            replaced = YES;
            break;
        }
    }
    if (!replaced) return nullv;

    uint64_t chip = AVDB115Stub(kVMAllocMyInkWell, 0, 0, 0, r);
    if (!AVDB115IsHeap(chip) || AVDB115Cid(chip) != kCidMyInkWell) return nullv;
    if (AVDB115NeedsWriteBarrier(chip, container, r->x28)) return nullv;
    if (AVDB115NeedsWriteBarrier(chip, onTap, r->x28)) return nullv;
    AVDB115Store(chip, kOffMyInkWellChild, container);
    AVDB115Store(chip, kOffMyInkWellOnTap, onTap);
    return chip;
}

static uint64_t AVDB115GrowAndAppend(uint64_t wrap, uint64_t chip0, uint64_t chip1,
                                     const AVDB115DartRegs *r) {
    uint64_t nullv = r->x22;
    if (AVDB115Cid(wrap) != kCidWrap) return wrap;
    uint64_t goa = AVDB115Load(wrap, kOffWrapChildren);
    if (AVDB115Cid(goa) != kCidGOA) return wrap;
    uint64_t lenWord = AVDB115Load(goa, kOffGOALength);
    if (!AVDB115IsSmi(lenWord) || AVDB115SmiVal(lenWord) != 4) return wrap;
    uint64_t oldArr = AVDB115Load(goa, kOffGOAData);
    if (AVDB115Cid(oldArr) != kCidArray) return wrap;

    uint64_t typeArgs = AVDB115Load(oldArr, 0x07);
    uint64_t newArr = AVDB115Stub(kVMAllocArray, typeArgs, AVDB115Smi(6), 0, r);
    if (!AVDB115IsHeap(newArr) || AVDB115Cid(newArr) != kCidArray) return wrap;
    for (int i = 0; i < 4; i++) {
        uint64_t e = AVDB115Load(oldArr, kOffArrayElem0 + i * 8);
        AVDB115Store(newArr, kOffArrayElem0 + i * 8, e);
    }
    AVDB115Store(newArr, kOffArrayElem0 + 4 * 8, chip0);
    AVDB115Store(newArr, kOffArrayElem0 + 5 * 8, chip1);
    // AllocateArray already wrote length Smi 6.

    if (AVDB115NeedsWriteBarrier(goa, newArr, r->x28)) return wrap;
    AVDB115Store(goa, kOffGOAData, newArr);
    AVDB115Store(goa, kOffGOALength, AVDB115Smi(6));
    (void)nullv;
    return wrap;
}

static uint64_t AVDB115Append115Chips(uint64_t wrap, const AVDB115DartRegs *r) {
    if (!gInstalled || !AVDB115IsHeap(wrap)) return wrap;
    uint64_t goa = AVDB115Load(wrap, kOffWrapChildren);
    if (AVDB115Cid(goa) != kCidGOA) return wrap;
    uint64_t lenWord = AVDB115Load(goa, kOffGOALength);
    // Already extended, or unexpected shape: leave alone.
    if (!AVDB115IsSmi(lenWord) || AVDB115SmiVal(lenWord) != 4) return wrap;
    uint64_t oldArr = AVDB115Load(goa, kOffGOAData);
    if (AVDB115Cid(oldArr) != kCidArray) return wrap;
    uint64_t templateInk = AVDB115Load(oldArr, kOffArrayElem0);
    if (AVDB115Cid(templateInk) != kCidMyInkWell) return wrap;

    uint64_t sPush = AVDB115NewTwoByteString(kLabelPushU16, (uint32_t)(sizeof(kLabelPushU16) / sizeof(kLabelPushU16[0])), r);
    uint64_t sPlay = AVDB115NewTwoByteString(kLabelPlayU16, (uint32_t)(sizeof(kLabelPlayU16) / sizeof(kLabelPlayU16[0])), r);
    uint64_t cPush = AVDB115NewClosure((uint64_t)&AVDB115DartOnPushTrampoline, r);
    uint64_t cPlay = AVDB115NewClosure((uint64_t)&AVDB115DartOnPlayTrampoline, r);
    if (!AVDB115IsHeap(sPush) || !AVDB115IsHeap(sPlay) ||
        !AVDB115IsHeap(cPush) || !AVDB115IsHeap(cPlay)) {
        return wrap;
    }
    uint64_t chip0 = AVDB115CloneChip(templateInk, sPush, cPush, r);
    uint64_t chip1 = AVDB115CloneChip(templateInk, sPlay, cPlay, r);
    if (!AVDB115IsHeap(chip0) || !AVDB115IsHeap(chip1)) return wrap;
    return AVDB115GrowAndAppend(wrap, chip0, chip1, r);
}

#pragma mark - Dart trampolines (call$0 ABI)

// Forward decls for the naked trampolines referenced above.
void AVDB115DartOnPushTrampoline(void);
void AVDB115DartOnPlayTrampoline(void);
static void AVDB115GetButtonLineWrapper(void);

void AVDB115DartHandleTap(intptr_t kind) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (kind == 0) {
            [AVDB115DetailActions performPushFromDartRow];
        } else {
            [AVDB115DetailActions performPlayFromDartRow];
        }
    });
}

__attribute__((naked))
void AVDB115DartOnPushTrampoline(void) {
    asm volatile(
        "stp x29, x30, [x15, #-16]!\n"
        "mov x29, x15\n"
        "sub sp, sp, #48\n"
        "stp x29, x30, [sp]\n"
        "stp x22, x26, [sp, #16]\n"
        "stp x27, x28, [sp, #32]\n"
        "mov x0, #0\n"
        "bl _AVDB115DartHandleTap\n"
        "ldp x22, x26, [sp, #16]\n"
        "ldp x27, x28, [sp, #32]\n"
        "ldp x29, x30, [sp]\n"
        "add sp, sp, #48\n"
        "mov x0, x22\n"
        "mov x15, x29\n"
        "ldp x29, x30, [x15], #16\n"
        "ret\n"
    );
}

__attribute__((naked))
void AVDB115DartOnPlayTrampoline(void) {
    asm volatile(
        "stp x29, x30, [x15, #-16]!\n"
        "mov x29, x15\n"
        "sub sp, sp, #48\n"
        "stp x29, x30, [sp]\n"
        "stp x22, x26, [sp, #16]\n"
        "stp x27, x28, [sp, #32]\n"
        "mov x0, #1\n"
        "bl _AVDB115DartHandleTap\n"
        "ldp x22, x26, [sp, #16]\n"
        "ldp x27, x28, [sp, #32]\n"
        "ldp x29, x30, [sp]\n"
        "add sp, sp, #48\n"
        "mov x0, x22\n"
        "mov x15, x29\n"
        "ldp x29, x30, [x15], #16\n"
        "ret\n"
    );
}

// Dart-ABI wrapper: call the original _getButtonLine, then append chips.
// CPU x0 is unused on entry (args live on the Dart stack).
__attribute__((naked))
static void AVDB115GetButtonLineWrapper(void) {
    asm volatile(
        "sub sp, sp, #80\n"
        "stp x29, x30, [sp]\n"
        "stp x22, x26, [sp, #16]\n"
        "stp x27, x28, [sp, #32]\n"
        "str x15, [sp, #48]\n"
        // Call the original (stolen prologue + jump back into the function).
        "adrp x16, _AVDB115OriginalTrampoline@PAGE\n"
        "ldr x16, [x16, _AVDB115OriginalTrampoline@PAGEOFF]\n"
        "blr x16\n"
        // x0 = Wrap. Keep it, then pass Dart reserved regs into the C helper.
        "str x0, [sp, #56]\n"
        "str x15, [sp, #48]\n"
        "ldr x0, [sp, #56]\n"
        "mov x1, x15\n"
        "mov x2, x22\n"
        "mov x3, x26\n"
        "mov x4, x27\n"
        "mov x5, x28\n"
        "bl _AVDB115Append115ChipsC\n"
        "ldp x29, x30, [sp]\n"
        "ldp x22, x26, [sp, #16]\n"
        "ldp x27, x28, [sp, #32]\n"
        "ldr x15, [sp, #48]\n"
        "add sp, sp, #80\n"
        "ret\n"
    );
}

uint64_t AVDB115Append115ChipsC(uint64_t wrap, uint64_t dart_sp, uint64_t x22,
                                uint64_t x26, uint64_t x27, uint64_t x28) {
    AVDB115DartRegs r = { dart_sp, x22, x26, x27, x28 };
    return AVDB115Append115Chips(wrap, &r);
}

#pragma mark - Text patch


static BOOL AVDB115Protect(uint64_t addr, size_t len, vm_prot_t prot) {
    uint64_t page = addr & ~((uint64_t)vm_page_size - 1);
    uint64_t end  = (addr + len + vm_page_size - 1) & ~((uint64_t)vm_page_size - 1);
    kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)page,
                                  (vm_size_t)(end - page), FALSE, prot);
    return kr == KERN_SUCCESS;
}

static void *AVDB115MapRX(size_t size) {
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (p == MAP_FAILED) return NULL;
    return p;
}

static BOOL AVDB115MakeRX(void *p, size_t size) {
    if (mprotect(p, size, PROT_READ | PROT_EXEC) != 0) {
        // Some iOS versions want vm_protect instead.
        return AVDB115Protect((uint64_t)p, size, VM_PROT_READ | VM_PROT_EXECUTE);
    }
    sys_icache_invalidate(p, size);
    return YES;
}

// 16-byte absolute jump: ldr x16, #8; br x16; .quad dest
static void AVDB115WriteAbsJump(uint8_t *dst, uint64_t dest) {
    uint32_t ldr = 0x58000030; // ldr x16, #8
    uint32_t br  = 0xD61F0200; // br x16
    memcpy(dst, &ldr, 4);
    memcpy(dst + 4, &br, 4);
    memcpy(dst + 8, &dest, 8);
}

static BOOL AVDB115InstallHook(void) {
    if (gInstalled) return YES;
    gSlide = AVDB115AppVmSlide();
    if (gSlide == 0) return NO;
    uint64_t entry = gSlide + kVMGetButtonLine;
    static const uint8_t kPrologueGetButtonLine[16] = {
        0xfd, 0x79, 0xbf, 0xa9, 0xfd, 0x03, 0x0f, 0xaa,
        0xef, 0x41, 0x01, 0xd1, 0xa0, 0x13, 0x40, 0xf9
    };
    if (!AVDB115PrologueMatches(entry, kPrologueGetButtonLine, 16)) {
        // Prologue does not match JavDB 1.9.41; refuse to patch.
        return NO;
    }
    vm_size_t stole_n = 0;
    if (vm_read_overwrite(mach_task_self(), (vm_address_t)entry, 16,
                          (vm_address_t)gStolen, &stole_n) != KERN_SUCCESS || stole_n < 16) {
        return NO;
    }

    gHookPage = AVDB115MapRX(vm_page_size);
    if (!gHookPage) return NO;
    // original trampoline at page+0: stolen 16 + abs jump to entry+16
    memcpy(gHookPage, gStolen, 16);
    AVDB115WriteAbsJump((uint8_t *)gHookPage + 16, entry + 16);
    AVDB115OriginalTrampoline = gHookPage;
    if (!AVDB115MakeRX(gHookPage, vm_page_size)) {
        munmap(gHookPage, vm_page_size);
        gHookPage = NULL;
        AVDB115OriginalTrampoline = NULL;
        return NO;
    }

    // Patch the entry to jump to our wrapper. Need RW on the text page.
    // VM_PROT_COPY breaks COW on a signed mapping when it is allowed.
    if (!AVDB115Protect(entry, 16, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) &&
        !AVDB115Protect(entry, 16, VM_PROT_READ | VM_PROT_WRITE)) {
        return NO;
    }
    AVDB115WriteAbsJump((uint8_t *)entry, (uint64_t)&AVDB115GetButtonLineWrapper);
    sys_icache_invalidate((void *)entry, 16);
    AVDB115Protect(entry, 16, VM_PROT_READ | VM_PROT_EXECUTE);
    gInstalled = YES;
    [AVDB115DetailActions setOverlayRowSuppressed:YES];
    return YES;
}

#else // !__arm64__

static BOOL gInstalled = NO;
static BOOL AVDB115InstallHook(void) { return NO; }

#endif

@implementation AVDB115DartRowHook

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        BOOL ok = AVDB115InstallHook();
        if (!ok) {
            NSLog(@"[AVDB115] Dart row hook not installed; keeping UIKit overlay.");
        } else {
            NSLog(@"[AVDB115] Dart row hook installed (untested on device).");
        }
    });
}

+ (BOOL)isInstalled {
    return gInstalled;
}

@end
