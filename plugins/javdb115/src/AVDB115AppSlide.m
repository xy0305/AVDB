#import "AVDB115AppSlide.h"

#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <string.h>
#import <sys/mman.h>
#import <libkern/OSCacheControl.h>

uint64_t AVDB115AppVmSlide(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        const char *base = strrchr(name, '/');
        base = base ? base + 1 : name;
        // App.framework/App — not Flutter.framework or App.framework/Flutter.
        if (strcmp(base, "App") != 0) continue;
        if (strstr(name, "App.framework") == NULL) continue;
        return (uint64_t)_dyld_get_image_vmaddr_slide(i);
    }
    return 0;
}

int AVDB115PrologueMatches(uint64_t addr, const uint8_t *expected, size_t n) {
    if (!expected || n == 0 || n > 64 || addr < 0x1000ull) return 0;
    uint8_t buf[64];
    vm_size_t out = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(),
                                         (vm_address_t)addr,
                                         (vm_size_t)n,
                                         (vm_address_t)buf,
                                         &out);
    if (kr != KERN_SUCCESS || out < n) return 0;
    return memcmp(buf, expected, n) == 0;
}

static int AVDB115Protect(uint64_t addr, size_t len, vm_prot_t prot) {
    vm_size_t page = vm_page_size ? vm_page_size : 16384;
    uint64_t start = addr & ~((uint64_t)page - 1ull);
    uint64_t end = (addr + len + page - 1ull) & ~((uint64_t)page - 1ull);
    kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)start,
                                  (vm_size_t)(end - start), FALSE, prot);
    return kr == KERN_SUCCESS;
}

static void AVDB115WriteAbsJump(uint8_t *dst, uint64_t dest) {
    uint32_t ldr = 0x58000030; // ldr x16, #8
    uint32_t br  = 0xD61F0200; // br x16
    memcpy(dst, &ldr, 4);
    memcpy(dst + 4, &br, 4);
    memcpy(dst + 8, &dest, 8);
}

int AVDB115InstallDartEntryHook(uint64_t unslid_vm,
                                const uint8_t expected_prologue[16],
                                void *wrapper,
                                void **orig_slot,
                                const char *name) {
    if (!expected_prologue || !wrapper || !orig_slot) return 0;
    uint64_t slide = AVDB115AppVmSlide();
    if (slide == 0) {
        NSLog(@"[AVDB115] %s hook: App.framework slide not found", name ? name : "dart");
        return 0;
    }
    uint64_t entry = slide + unslid_vm;
    if (!AVDB115PrologueMatches(entry, expected_prologue, 16)) {
        NSLog(@"[AVDB115] %s hook: prologue mismatch at 0x%llx (slide 0x%llx)",
              name ? name : "dart", (unsigned long long)entry, (unsigned long long)slide);
        return 0;
    }
    uint8_t stolen[16];
    vm_size_t out = 0;
    if (vm_read_overwrite(mach_task_self(), (vm_address_t)entry, 16,
                          (vm_address_t)stolen, &out) != KERN_SUCCESS || out < 16) {
        return 0;
    }

    size_t map_sz = vm_page_size ? (size_t)vm_page_size : 16384;
    void *page = mmap(NULL, map_sz, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (page == MAP_FAILED) return 0;
    memcpy(page, stolen, 16);
    AVDB115WriteAbsJump((uint8_t *)page + 16, entry + 16);
    if (mprotect(page, map_sz, PROT_READ | PROT_EXEC) != 0 &&
        !AVDB115Protect((uint64_t)page, map_sz, VM_PROT_READ | VM_PROT_EXECUTE)) {
        munmap(page, map_sz);
        return 0;
    }
    sys_icache_invalidate(page, map_sz);
    *orig_slot = page;

    if (!AVDB115Protect(entry, 16, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) &&
        !AVDB115Protect(entry, 16, VM_PROT_READ | VM_PROT_WRITE)) {
        NSLog(@"[AVDB115] %s hook: vm_protect write failed", name ? name : "dart");
        *orig_slot = NULL;
        munmap(page, map_sz);
        return 0;
    }
    AVDB115WriteAbsJump((uint8_t *)entry, (uint64_t)wrapper);
    sys_icache_invalidate((void *)entry, 16);
    AVDB115Protect(entry, 16, VM_PROT_READ | VM_PROT_EXECUTE);
    NSLog(@"[AVDB115] %s hook installed (untested on device).", name ? name : "dart");
    return 1;
}
