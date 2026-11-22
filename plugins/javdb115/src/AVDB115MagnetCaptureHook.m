#import "AVDB115MagnetCaptureHook.h"
#import "AVDB115AppSlide.h"
#import "AVDB115MagnetCache.h"

#if defined(__arm64__)

// Unslid VM = FAT file offset - 0x4000 (__TEXT vmaddr 0, fileoff 0 in the thin slice).
static const uint64_t kVMMagnetsFromJson = 0x9c3fc;
static const uint64_t kVMMagnetListItemBuild = 0x577acc;

// stp x29,x30,[x15,#-0x10]!; mov x29,x15; sub x15,x15,#0x18; mov x4,x1
static const uint8_t kPrologueFromJson[16] = {
    0xfd, 0x79, 0xbf, 0xa9, 0xfd, 0x03, 0x0f, 0xaa,
    0xef, 0x61, 0x00, 0xd1, 0xe4, 0x03, 0x01, 0xaa
};
// stp; mov x29,x15; sub x15,x15,#0xa0; mov x0,x1
static const uint8_t kPrologueBuild[16] = {
    0xfd, 0x79, 0xbf, 0xa9, 0xfd, 0x03, 0x0f, 0xaa,
    0xef, 0x81, 0x02, 0xd1, 0xe0, 0x03, 0x01, 0xaa
};

void *AVDB115OrigMagnetsFromJson = NULL;
void *AVDB115OrigMagnetListItemBuild = NULL;
static BOOL gFromJsonInstalled = NO;
static BOOL gBuildInstalled = NO;

void AVDB115MagnetsFromJsonWrapper(void);
void AVDB115MagnetListItemBuildWrapper(void);

// Save x1 (receiver), run the original Dart function, capture from the
// saved receiver, then return the original x0. CPU SP only; Dart x15 is
// forwarded unchanged. Large buffers stay off this stack.
__attribute__((naked))
void AVDB115MagnetsFromJsonWrapper(void) {
    asm volatile(
        "sub sp, sp, #96\n"
        "stp x29, x30, [sp]\n"
        "stp x1, x2, [sp, #16]\n"
        "stp x22, x26, [sp, #32]\n"
        "stp x27, x28, [sp, #48]\n"
        "str x15, [sp, #64]\n"
        "adrp x16, _AVDB115OrigMagnetsFromJson@PAGE\n"
        "ldr x16, [x16, _AVDB115OrigMagnetsFromJson@PAGEOFF]\n"
        "blr x16\n"
        "str x0, [sp, #72]\n"
        "ldr x0, [sp, #16]\n"
        "bl _AVDB115CacheCaptureMagnets\n"
        "ldr x0, [sp, #72]\n"
        "ldr x15, [sp, #64]\n"
        "ldp x27, x28, [sp, #48]\n"
        "ldp x22, x26, [sp, #32]\n"
        "ldp x29, x30, [sp]\n"
        "add sp, sp, #96\n"
        "ret\n"
    );
}

__attribute__((naked))
void AVDB115MagnetListItemBuildWrapper(void) {
    asm volatile(
        "sub sp, sp, #96\n"
        "stp x29, x30, [sp]\n"
        "stp x1, x2, [sp, #16]\n"
        "stp x22, x26, [sp, #32]\n"
        "stp x27, x28, [sp, #48]\n"
        "str x15, [sp, #64]\n"
        "adrp x16, _AVDB115OrigMagnetListItemBuild@PAGE\n"
        "ldr x16, [x16, _AVDB115OrigMagnetListItemBuild@PAGEOFF]\n"
        "blr x16\n"
        "str x0, [sp, #72]\n"
        "ldr x0, [sp, #16]\n"
        "bl _AVDB115CacheCaptureListItem\n"
        "ldr x0, [sp, #72]\n"
        "ldr x15, [sp, #64]\n"
        "ldp x27, x28, [sp, #48]\n"
        "ldp x22, x26, [sp, #32]\n"
        "ldp x29, x30, [sp]\n"
        "add sp, sp, #96\n"
        "ret\n"
    );
}

#else

static BOOL gFromJsonInstalled = NO;
static BOOL gBuildInstalled = NO;

#endif

@implementation AVDB115MagnetCaptureHook

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
#if defined(__arm64__)
        gFromJsonInstalled = AVDB115InstallDartEntryHook(
            kVMMagnetsFromJson, kPrologueFromJson,
            (void *)&AVDB115MagnetsFromJsonWrapper,
            &AVDB115OrigMagnetsFromJson,
            "Magnets.fromJson") ? YES : NO;
        gBuildInstalled = AVDB115InstallDartEntryHook(
            kVMMagnetListItemBuild, kPrologueBuild,
            (void *)&AVDB115MagnetListItemBuildWrapper,
            &AVDB115OrigMagnetListItemBuild,
            "MagnetListItem.build") ? YES : NO;
        if (!gFromJsonInstalled && !gBuildInstalled) {
            NSLog(@"[AVDB115] magnet capture hooks not installed; cache stays empty until a fallback scan.");
        }
#endif
    });
}

+ (BOOL)fromJsonInstalled { return gFromJsonInstalled; }
+ (BOOL)buildInstalled { return gBuildInstalled; }

@end
