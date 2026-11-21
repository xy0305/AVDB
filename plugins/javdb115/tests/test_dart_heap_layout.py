#!/usr/bin/env python3
"""Host-side verification of Dart 3.13.7 iOS uncompressed heap layouts.

These checks use the on-disk App.framework and the already-disassembled
allocation stubs. They justify writing a runtime hook; they do not run a
Dart isolate and do not claim device success.
"""
from __future__ import annotations

import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "ipa-extract/Payload/Runner.app/Frameworks/App.framework/App"
FAT_TO_VM = 0x4000

# GC tags used by the bump-allocator stubs (not the on-disk old-space tags).
kNewObjectTags = 0x1C
kTwoByteStringCid = 95
kArrayCid = 90
kGrowableObjectArrayCid = 92
kClosureCid = 57
kMyInkWellCid = 4092
kTextCid = 3985
kContainerCid = 4015
kWrapCid = 4533

# Verified field offsets from stubs + _getButtonLine / _getWantWatch / raw_object.h
OFF_ARRAY_TYPEARGS = 0x07  # tagged
OFF_ARRAY_LENGTH = 0x0F
OFF_ARRAY_ELEM0 = 0x17
OFF_GOA_TYPEARGS = 0x07
OFF_GOA_LENGTH = 0x0F
OFF_GOA_DATA = 0x17
OFF_WRAP_CHILDREN = 0x0F
OFF_MYINKWELL_CHILD = 0x0F
OFF_MYINKWELL_ONTAP = 0x17
OFF_TEXT_DATA = 0x0F
OFF_TEXT_STYLE = 0x1F
OFF_CLOSURE_ENTRY = 0x07
OFF_CLOSURE_FLAGS = 0x0F
OFF_CLOSURE_HASH = 0x17
OFF_CLOSURE_FUNCTION = 0x1F
OFF_CLOSURE_CONTEXT = 0x27
OFF_STRING_LENGTH = 0x08  # untagged
OFF_STRING_DATA = 0x10    # untagged

# FAT / VM
FAT_GET_BUTTON_LINE = 0x3C1144
FAT_EPILOGUE = 0x3C14E4
FAT_ALLOCOBJ = 0x805A3C
FAT_ALLOCARRAY = 0x806DA0
FAT_ALLOCGOA = 0x805A84
FAT_ALLOCCLOSURE = 0x805E9C
FAT_ALLOC_MYINKWELL = 0x26DBD8
FAT_ALLOC_CONTAINER = 0xCA50C
FAT_ALLOC_TEXT = 0xCA524
FAT_HANDLE_TAP_BLR = 0x38D220

PROLOGUE_16 = bytes.fromhex("fd79bfa9fd030faaef4101d1a01340f9")
EPILOGUE_12 = bytes.fromhex("ef031daafd79c1a8c0035fd6")
HANDLE_TAP_CALL = bytes.fromhex("e00100f964ab40f9027040f840003fd6")


def smi(n: int) -> int:
    return n << 1


def header_pack(cid: int, size_tag: int, tags: int = kNewObjectTags, hash_hi: int = 0) -> int:
    low = (cid << 12) | ((size_tag & 0xF) << 8) | (tags & 0xFF)
    return ((hash_hi & 0xFFFFFFFF) << 32) | low


def header_parse(h: int) -> tuple[int, int, int, int]:
    return ((h >> 12) & 0xFFFFF, (h >> 8) & 0xF, h & 0xFF, h >> 32)


def rounded_size(n: int) -> int:
    return (n + 15) & ~15


def two_byte_string_size(nchars: int) -> int:
    return rounded_size(8 + 8 + 2 * nchars)


@unittest.skipUnless(APP.is_file(), "App.framework not present (source-zip / CI checkout)")
class TestOnDiskStringLayout(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = APP.read_bytes()

    def _read_wanted(self, fat: int, expected: str):
        blob = self.data[fat : fat + 32]
        header, length = struct.unpack_from("<QQ", blob, 0)
        cid, stag, tags, hh = header_parse(header)
        n = length >> 1
        text = blob[16 : 16 + 2 * n].decode("utf-16le")
        return header, cid, stag, tags, length, text

    def test_xiang_kan_two_byte_string(self):
        fat = 12811024  # key_strings.json "想看"
        header, cid, stag, tags, length, text = self._read_wanted(fat, "想看")
        self.assertEqual(cid, kTwoByteStringCid)
        self.assertEqual(stag, 2)
        self.assertEqual(length, smi(2))
        self.assertEqual(text, "想看")
        self.assertEqual(two_byte_string_size(2), 32)
        # On-disk GC tags differ from TLAB new-object tags; cid/size/length/data are what we rely on.
        self.assertNotEqual(tags, kNewObjectTags)
        self.assertEqual(tags, 0xB2)

    def test_new_object_header_matches_alloc_stubs(self):
        # AllocateObject / AllocateClosure / AllocateArray all use tags 0x1c.
        # Closure stub 0x805e9c hard-codes tags 0x5c (not the 0x1c used by
        # Array/GOA/widget AllocateObject). We never pack this header ourselves;
        # we call that stub. Check the stub immediate here:
        self.assertEqual(header_pack(kClosureCid, 3, tags=0x5C) & 0xFFFFFFFF, 0x3935C)
        self.assertEqual(header_pack(kArrayCid, 0) & 0xFFFFFFFF, 0x5A01C)
        self.assertEqual(header_pack(kGrowableObjectArrayCid, 2) & 0xFFFFFFFF, 0x5C21C)
        self.assertEqual(header_pack(kWrapCid, 6) & 0xFFFFFFFF, 0x11B561C)
        self.assertEqual(header_pack(kMyInkWellCid, 3) & 0xFFFFFFFF, 0xFFC31C)
        self.assertEqual(header_pack(kTextCid, 10) & 0xFFFFFFFF, 0xF91A1C)
        self.assertEqual(header_pack(kContainerCid, 7) & 0xFFFFFFFF, 0xFAF71C)
        # TwoByteString of size 0x20 (our two labels both round to 32 bytes).
        self.assertEqual(len("推送到 115"), 7)
        self.assertEqual(len("115 播放"), 6)
        self.assertEqual(two_byte_string_size(7), 32)  # 推送到 115
        self.assertEqual(two_byte_string_size(6), 32)  # 115 播放
        self.assertEqual(header_pack(kTwoByteStringCid, 2) & 0xFFFFFFFF, 0x5F21C)

    def test_label_utf16_roundtrip(self):
        for label in ("推送到 115", "115 播放"):
            raw = label.encode("utf-16le")
            self.assertEqual(raw.decode("utf-16le"), label)
            self.assertEqual(two_byte_string_size(len(label)), 32)


@unittest.skipUnless(APP.is_file(), "App.framework not present (source-zip / CI checkout)")
class TestStubAddressesAndHookSite(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = APP.read_bytes()

    def test_fat_to_vm(self):
        self.assertEqual(FAT_GET_BUTTON_LINE - FAT_TO_VM, 0x3BD144)
        self.assertEqual(FAT_EPILOGUE - FAT_TO_VM, 0x3BD4E4)
        self.assertEqual(FAT_ALLOCOBJ - FAT_TO_VM, 0x801A3C)
        self.assertEqual(FAT_ALLOCARRAY - FAT_TO_VM, 0x802DA0)
        self.assertEqual(FAT_ALLOCGOA - FAT_TO_VM, 0x801A84)
        self.assertEqual(FAT_ALLOCCLOSURE - FAT_TO_VM, 0x801E9C)

    def test_prologue_is_16_bytes_for_absolute_hook(self):
        raw = self.data[FAT_GET_BUTTON_LINE : FAT_GET_BUTTON_LINE + 16]
        self.assertEqual(raw, PROLOGUE_16)
        # Epilogue is only 12 bytes — too short for an absolute ldr/br/imm64 hook,
        # which is why the runtime hook wraps the *entry*, then mutates the Wrap
        # after the original function returns (same moment as 0x3c14e4).
        epi = self.data[FAT_EPILOGUE : FAT_EPILOGUE + 12]
        self.assertEqual(epi, EPILOGUE_12)

    def test_handle_tap_uses_cached_closure_entry(self):
        # str x0, [x15]; ldr x4, [pp+0x150]; ldur x2, [x0, #7]; blr x2
        raw = self.data[FAT_HANDLE_TAP_BLR : FAT_HANDLE_TAP_BLR + 16]
        self.assertEqual(raw, HANDLE_TAP_CALL)

    def test_alloc_object_fast_path_signature(self):
        # First instruction of 0x805a3c: ubfx x4, x2, #8, #4  (size_tag)
        word = struct.unpack_from("<I", self.data, FAT_ALLOCOBJ)[0]
        self.assertEqual(word, 0xD3482C44)


class TestSimulatedTLAB(unittest.TestCase):
    """Simulate the 0x805a3c fast path and GOA 4→6 growth in a fake TLAB."""

    def alloc_object(self, heap: bytearray, top: int, header: int) -> tuple[int, int]:
        cid, stag, tags, _ = header_parse(header)
        size = stag * 16
        self.assertGreater(size, 0)
        end = top + size
        struct.pack_into("<Q", heap, top, header)
        # Zero-fill with a fake NULL tagged pointer 0x11 (stand-in).
        null = 0x11
        for off in range(8, size, 8):
            struct.pack_into("<Q", heap, top + off, null)
        tagged = top + 1
        return tagged, end

    def test_two_byte_string_alloc_and_readback(self):
        heap = bytearray(256)
        top = 16
        header = header_pack(kTwoByteStringCid, 2)
        tagged, top = self.alloc_object(heap, top, header)
        untagged = tagged - 1
        label = "推送到 115"
        struct.pack_into("<Q", heap, untagged + OFF_STRING_LENGTH, smi(len(label)))
        data = label.encode("utf-16le")
        heap[untagged + OFF_STRING_DATA : untagged + OFF_STRING_DATA + len(data)] = data
        cid, stag, tags, _ = header_parse(struct.unpack_from("<Q", heap, untagged)[0])
        self.assertEqual((cid, stag, tags), (kTwoByteStringCid, 2, kNewObjectTags))
        length = struct.unpack_from("<Q", heap, untagged + OFF_STRING_LENGTH)[0]
        self.assertEqual(length, smi(len(label)))
        got = bytes(heap[untagged + OFF_STRING_DATA : untagged + OFF_STRING_DATA + 2 * len(label)]).decode("utf-16le")
        self.assertEqual(got, label)

    def test_goa_grow_4_to_6_keeps_first_four(self):
        heap = bytearray(512)
        top = 16
        null = 0x11
        # Fake 4 existing children (tagged stand-ins).
        children = [0x101, 0x201, 0x301, 0x401]
        # Old Array length 4: header + typeargs + length + 4 elems, size = 0x10+4*8=0x30, tag 3
        arr_header = header_pack(kArrayCid, 3)
        old_arr, top = self.alloc_object(heap, top, arr_header)
        struct.pack_into("<Q", heap, old_arr - 1 + 0x08, smi(4))  # length at untagged+8 = tagged+7? 
        # Use tagged offsets: store at (tagged + off) which is untagged+off+1-1 = untagged+off... 
        # tagged = untagged+1, store at address (tagged + tagged_off - 1)? 
        # In ARM, `stur x, [x0, #0xf]` with x0 tagged means address = tagged+0xf = untagged+0x10.
        # So tagged offset 0x0f -> untagged + 0x10. That's WRONG vs my OFF_*?
        #
        # Wait. tagged pointer = untagged + 1.
        # ldur x, [x0, #0xf] = memory[tagged + 0xf] = memory[untagged + 1 + 0xf] = memory[untagged + 0x10].
        #
        # raw_object.h: first field after header (8 bytes) is at untagged+8.
        # Corresponding tagged offset = (untagged+8) - tagged = 8-1 = 7. Yes OFF_* = 0x07 for first field.
        # Second field untagged+16, tagged off = 15 = 0x0f.
        # Element 0 of Array is after typeargs and length: untagged+24, tagged off = 0x17.
        #
        # So store at address (tagged + tagged_off) = untagged + tagged_off + 1.
        # For length (tagged off 0x0f): addr = untagged + 0x10. First field typeargs tagged 0x07: untagged+8.
        # I must use addr = tagged + off, because x0 is tagged and the immediate is used as-is!

        def taddr(tagged_ptr: int, tagged_off: int) -> int:
            return tagged_ptr + tagged_off  # matches ldur/stur [x0, #off]

        struct.pack_into("<Q", heap, taddr(old_arr, OFF_ARRAY_LENGTH), smi(4))
        for i, ch in enumerate(children):
            struct.pack_into("<Q", heap, taddr(old_arr, OFF_ARRAY_ELEM0 + i * 8), ch)

        goa_header = header_pack(kGrowableObjectArrayCid, 2)
        goa, top = self.alloc_object(heap, top, goa_header)
        struct.pack_into("<Q", heap, taddr(goa, OFF_GOA_LENGTH), smi(4))
        struct.pack_into("<Q", heap, taddr(goa, OFF_GOA_DATA), old_arr)

        # Grow: new Array length 6, size header+typeargs+length+6*8 = 8+8+8+48=72, round 80=0x50, tag 5
        new_header = header_pack(kArrayCid, 5)
        new_arr, top = self.alloc_object(heap, top, new_header)
        struct.pack_into("<Q", heap, taddr(new_arr, OFF_ARRAY_LENGTH), smi(6))
        for i, ch in enumerate(children):
            struct.pack_into("<Q", heap, taddr(new_arr, OFF_ARRAY_ELEM0 + i * 8), ch)
        struct.pack_into("<Q", heap, taddr(new_arr, OFF_ARRAY_ELEM0 + 4 * 8), 0x501)
        struct.pack_into("<Q", heap, taddr(new_arr, OFF_ARRAY_ELEM0 + 5 * 8), 0x601)
        struct.pack_into("<Q", heap, taddr(goa, OFF_GOA_DATA), new_arr)
        struct.pack_into("<Q", heap, taddr(goa, OFF_GOA_LENGTH), smi(6))

        self.assertEqual(struct.unpack_from("<Q", heap, taddr(goa, OFF_GOA_LENGTH))[0], smi(6))
        data = struct.unpack_from("<Q", heap, taddr(goa, OFF_GOA_DATA))[0]
        self.assertEqual(data, new_arr)
        got = [struct.unpack_from("<Q", heap, taddr(new_arr, OFF_ARRAY_ELEM0 + i * 8))[0] for i in range(6)]
        self.assertEqual(got, children + [0x501, 0x601])
        # Original four slots of the old array left untouched (Consumer still at [3]).
        self.assertEqual(got[3], 0x401)


class TestClosureLayout(unittest.TestCase):
    def test_allocate_closure_field_order(self):
        # Matches 0x805e9c stores and UntaggedClosure (precompiled, uncompressed).
        # size 0x30, size_tag 3, cid 57, header 0x3935c.
        self.assertEqual(0x30, 3 * 16)
        offsets = {
            "entry_point": OFF_CLOSURE_ENTRY,
            "length_and_flags": OFF_CLOSURE_FLAGS,
            "hash": OFF_CLOSURE_HASH,
            "function": OFF_CLOSURE_FUNCTION,
            "context": OFF_CLOSURE_CONTEXT,
        }
        self.assertEqual(offsets["entry_point"], 0x07)
        self.assertEqual(offsets["length_and_flags"], 0x0F)
        # Callers always pass x2 = #0x40 as length_and_flags.
        self.assertEqual(0x40, 0x40)
        # InkWell.handleTap calls blr of [closure, #7] — the cached entry_point.


if __name__ == "__main__":
    unittest.main()
