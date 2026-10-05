#!/usr/bin/env python3
"""Verify that a hybrid ISO's appended EFI partition matches its prepared image."""
import hashlib
import struct
import sys
import uuid
import zlib
from pathlib import Path


def verify(iso, expected):
    with iso.open("rb") as source:
        source.seek(512)
        header = bytearray(source.read(512))
        if header[:8] != b"EFI PART":
            raise ValueError("ISO has no primary GPT")
        size, crc = struct.unpack_from("<II", header, 12)
        if not 92 <= size <= 512:
            raise ValueError("Invalid GPT header size")
        struct.pack_into("<I", header, 16, 0)
        if zlib.crc32(header[:size]) != crc:
            raise ValueError("GPT header checksum mismatch")
        entries_lba, count, entry_size, table_crc = struct.unpack_from("<QIII", header, 72)
        if not 1 <= count <= 4096 or not 128 <= entry_size <= 4096:
            raise ValueError("Invalid GPT entry dimensions")
        source.seek(entries_lba * 512)
        table = source.read(count * entry_size)
        if zlib.crc32(table) != table_crc:
            raise ValueError("GPT partition table checksum mismatch")
        esp = uuid.UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b").bytes_le
        entries = [table[i:i + entry_size] for i in range(0, len(table), entry_size)
                   if table[i:i + 16] == esp]
        if len(entries) != 1:
            raise ValueError("Expected exactly one EFI system partition")
        start, end = struct.unpack_from("<QQ", entries[0], 32)
        length = expected.stat().st_size
        if start > end or (end - start + 1) * 512 < length or (end + 1) * 512 > iso.stat().st_size:
            raise ValueError("EFI partition outside image or smaller than prepared filesystem")
        source.seek(start * 512)
        actual_hash = hashlib.sha256(source.read(length)).hexdigest()
        expected_hash = hashlib.sha256(expected.read_bytes()).hexdigest()
        if actual_hash != expected_hash:
            raise ValueError("Appended EFI partition does not match the updated EFI filesystem")
        print(f"PASS: GPT checksums and appended EFI partition match ({length} bytes, {actual_hash})")


if __name__ == "__main__":
    verify(Path(sys.argv[1]), Path(sys.argv[2]))
