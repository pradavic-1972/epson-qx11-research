#!/usr/bin/env python3
"""Convert a raw sector image to a vfloppy-compatible D88 file.

The default geometry is the Epson QX-11 360 KiB format:
40 cylinders, 2 heads, 9 sectors per track, 512 bytes per sector.
Raw sectors are expected in cylinder/head/sector order.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path


D88_HEADER_SIZE = 0x2B0
D88_TRACK_SLOTS = 164
D88_SECTOR_HEADER_SIZE = 16

DISK_TYPES = {
    "2d": 0x00,
    "2dd": 0x10,
    "2hd": 0x20,
}

VFLOPPY_SIGNATURES = ("D88 VFloppy", "TELEDISK")


def positive_int(value: str) -> int:
    try:
        number = int(value, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"not an integer: {value}") from exc
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def size_code(sector_size: int) -> int:
    """Return the floppy N code for a sector size of 128 * 2**N."""
    if sector_size < 128 or sector_size % 128:
        raise ValueError("sector size must be 128, 256, 512, 1024, ... bytes")

    quotient = sector_size // 128
    if quotient & (quotient - 1):
        raise ValueError("sector size must be 128 multiplied by a power of two")

    code = quotient.bit_length() - 1
    if code > 255:
        raise ValueError("sector size is too large for a D88 N field")
    return code


def disk_name_bytes(name: str) -> bytes:
    try:
        encoded = name.encode("ascii")
    except UnicodeEncodeError as exc:
        raise ValueError("disk name must contain ASCII characters only") from exc

    if len(encoded) > 16:
        raise ValueError("disk name must be at most 16 ASCII characters")
    return encoded + b"\x00" * (17 - len(encoded))


def convert(args: argparse.Namespace) -> tuple[int, int]:
    track_count = args.cylinders * args.heads
    if track_count > D88_TRACK_SLOTS:
        raise ValueError(
            f"geometry requires {track_count} tracks; D88 supports {D88_TRACK_SLOTS}"
        )
    if args.sectors_per_track > 0xFFFF:
        raise ValueError("sectors per track exceeds the D88 field size")
    if args.first_sector + args.sectors_per_track - 1 > 0xFF:
        raise ValueError("sector numbers must fit in one byte")
    if args.cylinders - 1 > 0xFF or args.heads - 1 > 0xFF:
        raise ValueError("cylinder and head numbers must fit in one byte")

    if args.name not in VFLOPPY_SIGNATURES:
        raise ValueError(
            "vfloppy accepts only the D88 header names "
            f"{VFLOPPY_SIGNATURES[0]!r} or {VFLOPPY_SIGNATURES[1]!r}"
        )

    n_code = size_code(args.sector_size)
    expected_size = (
        args.cylinders
        * args.heads
        * args.sectors_per_track
        * args.sector_size
    )
    raw = args.input.read_bytes()
    if len(raw) != expected_size:
        raise ValueError(
            f"input is {len(raw):,} bytes, but this geometry requires "
            f"{expected_size:,} bytes"
        )

    if args.output.exists() and not args.force:
        raise FileExistsError(
            f"output already exists: {args.output} (use --force to replace it)"
        )

    sector_record_size = D88_SECTOR_HEADER_SIZE + args.sector_size
    track_size = args.sectors_per_track * sector_record_size
    disk_size = D88_HEADER_SIZE + track_count * track_size
    if disk_size > 0xFFFFFFFF:
        raise ValueError("resulting D88 file is too large")

    header = bytearray(D88_HEADER_SIZE)
    header[0:17] = disk_name_bytes(args.name)
    header[0x1A] = 0x10 if args.write_protected else 0x00
    header[0x1B] = DISK_TYPES[args.disk_type]
    struct.pack_into("<I", header, 0x1C, disk_size)

    track_offset = D88_HEADER_SIZE
    for track_index in range(track_count):
        struct.pack_into("<I", header, 0x20 + track_index * 4, track_offset)
        track_offset += track_size

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("wb") as d88:
        d88.write(header)
        raw_offset = 0

        for cylinder in range(args.cylinders):
            for head in range(args.heads):
                for sector_index in range(args.sectors_per_track):
                    sector_number = args.first_sector + sector_index
                    sector_header = bytearray(D88_SECTOR_HEADER_SIZE)
                    sector_header[0] = cylinder
                    sector_header[1] = head
                    sector_header[2] = sector_number
                    sector_header[3] = n_code
                    struct.pack_into(
                        "<H", sector_header, 4, args.sectors_per_track
                    )
                    sector_header[6] = 0x00  # double density
                    sector_header[7] = 0x00  # not deleted
                    sector_header[8] = 0x00  # normal status
                    struct.pack_into("<H", sector_header, 14, args.sector_size)

                    d88.write(sector_header)
                    next_offset = raw_offset + args.sector_size
                    d88.write(raw[raw_offset:next_offset])
                    raw_offset = next_offset

    return expected_size, disk_size


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Convert a raw sector image to a vfloppy-compatible D88 file. "
            "Defaults to the Epson QX-11 40-cylinder, double-sided, "
            "9x512-byte (360 KiB) format."
        )
    )
    parser.add_argument("input", type=Path, help="input raw .bin or .img file")
    parser.add_argument("output", type=Path, help="output .d88 file")
    parser.add_argument("-c", "--cylinders", type=positive_int, default=40)
    parser.add_argument("-H", "--heads", type=positive_int, default=2)
    parser.add_argument(
        "-s", "--sectors-per-track", type=positive_int, default=9
    )
    parser.add_argument("-z", "--sector-size", type=positive_int, default=512)
    parser.add_argument(
        "--first-sector", type=positive_int, default=1,
        help="first sector ID on each track (default: 1)",
    )
    parser.add_argument(
        "--disk-type", choices=DISK_TYPES, default="2d",
        help="D88 media type byte (default: 2d)",
    )
    parser.add_argument(
        "-n", "--name", choices=VFLOPPY_SIGNATURES, default="D88 VFloppy",
        help="required vfloppy D88 signature (default: 'D88 VFloppy')",
    )
    parser.add_argument(
        "--write-protected", action="store_true",
        help="mark the D88 image write-protected",
    )
    parser.add_argument(
        "-f", "--force", action="store_true",
        help="replace the output file if it already exists",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        raw_size, d88_size = convert(args)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))

    print(
        f"Converted {args.input} ({raw_size:,} bytes) to {args.output} "
        f"({d88_size:,} bytes)"
    )
    print(
        f"Geometry: {args.cylinders} cylinders, {args.heads} heads, "
        f"{args.sectors_per_track} sectors/track, {args.sector_size} bytes/sector"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
