#!/usr/bin/env python3
"""Print the golden digests of committed asset files, decoded in pure Python.

PNG (8-bit RGBA or RGB, not interlaced; every filter type) gives its size,
the SHA-256 of its RGBA8 pixels (rows top to bottom, RGB widened with alpha
255) and its opaque pixel count: the padded image digest of vlo_images.tsv.
WAV (PCM, 16-bit) gives channels, rate, frames and the SHA-256 of its sample
bytes: the pcm16 digest of sound_samples.tsv and the PCM digest of
disc_tracks.tsv. Palette, greyscale,
16-bit and interlaced PNGs and non-PCM WAVs are rejected with a message.

Used to fill tests/golden/imported/overrides.tsv for reviewed hand edits
(tests/golden/specs/imported-assets.md).

Usage:
    python3 tools/hash_asset.py FILE...
    python3 tools/hash_asset.py --self-test
"""

import argparse
import hashlib
import struct
import sys
import zlib

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class AssetError(Exception):
    pass


def png_chunks(data):
    """(type, body) of each chunk, checking the signature and every CRC."""
    if data[:8] != PNG_SIGNATURE:
        raise AssetError("not a PNG file")
    pos = 8
    while pos < len(data):
        if pos + 12 > len(data):
            raise AssetError("truncated chunk at %d" % pos)
        length, kind = struct.unpack_from(">I4s", data, pos)
        body = data[pos + 8:pos + 8 + length]
        if len(body) != length:
            raise AssetError("truncated %s chunk" % kind.decode("latin-1"))
        if zlib.crc32(kind + body) != struct.unpack_from(">I", data, pos + 8 + length)[0]:
            raise AssetError("bad CRC in %s chunk" % kind.decode("latin-1"))
        yield kind, body
        pos += 12 + length
        if kind == b"IEND":
            return
    raise AssetError("no IEND chunk")


def unfilter(raw, width, height, bpp):
    """The image bytes of a non-interlaced scanline stream, undoing filters 0-4."""
    stride = width * bpp
    if len(raw) != height * (stride + 1):
        raise AssetError("decompressed %d bytes, expected %d" % (len(raw), height * (stride + 1)))
    out = bytearray(height * stride)
    prior = bytearray(stride)
    for y in range(height):
        kind = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        if kind == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + prior[i]) & 0xFF
        elif kind == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prior[i]) >> 1)) & 0xFF
        elif kind == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prior[i]
                c = prior[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
        elif kind != 0:
            raise AssetError("row %d has filter type %d" % (y, kind))
        out[y * stride:(y + 1) * stride] = line
        prior = line
    return bytes(out)


def decode_png(data):
    """(width, height, RGBA8 bytes) of an 8-bit RGBA or RGB PNG."""
    header, idat = None, []
    for kind, body in png_chunks(data):
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
    if header is None:
        raise AssetError("no IHDR chunk")
    width, height, depth, colour, compression, filtering, interlace = header
    if depth != 8 or colour not in (2, 6):
        raise AssetError("only 8-bit RGBA or RGB PNGs are supported (bit depth %d, colour type %d)" % (depth, colour))
    if compression or filtering or interlace:
        raise AssetError("unsupported compression, filter method or interlacing")
    bpp = 4 if colour == 6 else 3
    pixels = unfilter(zlib.decompress(b"".join(idat)), width, height, bpp)
    if colour == 2:
        rgba = bytearray(width * height * 4)
        rgba[0::4], rgba[1::4], rgba[2::4] = pixels[0::3], pixels[1::3], pixels[2::3]
        rgba[3::4] = b"\xff" * (width * height)
        pixels = bytes(rgba)
    return width, height, pixels


def decode_wav(data):
    """(channels, rate, sample bytes) of a 16-bit PCM WAV."""
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise AssetError("not a WAV file")
    fmt, samples, pos = None, None, 12
    while pos + 8 <= len(data):
        kind, size = struct.unpack_from("<4sI", data, pos)
        body = data[pos + 8:pos + 8 + size]
        if kind == b"fmt ":
            fmt = struct.unpack_from("<HHIIHH", body)
        elif kind == b"data":
            samples = body
        pos += 8 + size + (size & 1)
    if fmt is None or samples is None:
        raise AssetError("missing fmt or data chunk")
    tag, channels, rate, _byte_rate, align, bits = fmt
    if tag != 1 or bits != 16 or align != 2 * channels:
        raise AssetError("only 16-bit PCM WAVs are supported (format %d, %d bits)" % (tag, bits))
    if len(samples) % align:
        raise AssetError("data chunk ends inside a frame")
    return channels, rate, bytes(samples)


def describe(path):
    """One line of key=value digests for path."""
    data = open(path, "rb").read()
    if data[:8] == PNG_SIGNATURE:
        width, height, rgba = decode_png(data)
        return "%s\tpng\twidth=%d\theight=%d\trgba_sha256=%s\topaque_pixels=%d" % (
            path, width, height, hashlib.sha256(rgba).hexdigest(), rgba[3::4].count(255))
    if data[:4] == b"RIFF":
        channels, rate, samples = decode_wav(data)
        return "%s\twav\tchannels=%d\trate=%d\tframes=%d\tpcm_sha256=%s" % (
            path, channels, rate, len(samples) // (2 * channels), hashlib.sha256(samples).hexdigest())
    raise AssetError("not a PNG or WAV file")


def encode_png(width, height, rgba):
    """A PNG of RGBA8 pixels, row y using filter type y % 5, for the self-test."""
    stride = width * 4
    rows = []
    prior = bytes(stride)
    for y in range(height):
        line = rgba[y * stride:(y + 1) * stride]
        kind = y % 5
        out = bytearray(stride)
        for i in range(stride):
            a = line[i - 4] if i >= 4 else 0
            b = prior[i]
            c = prior[i - 4] if i >= 4 else 0
            if kind == 0:
                pred = 0
            elif kind == 1:
                pred = a
            elif kind == 2:
                pred = b
            elif kind == 3:
                pred = (a + b) >> 1
            else:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else b if pb <= pc else c
            out[i] = (line[i] - pred) & 0xFF
        rows.append(bytes([kind]) + bytes(out))
        prior = line

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    return (PNG_SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))


def self_test():
    """Round-trips a synthetic PNG through every filter type and a WAV; returns 0 on success."""
    width, height = 7, 11
    rgba = bytes((x * 37 + y * 11 + k * 101 + (x * y) % 13) & 0xFF if k < 3 else (255 if (x + y) % 3 else 0)
                 for y in range(height) for x in range(width) for k in range(4))
    w, h, decoded = decode_png(encode_png(width, height, rgba))
    assert (w, h) == (width, height) and decoded == rgba, "PNG round trip differs"
    pcm = struct.pack("<6h", 0, 1, -1, 32767, -32768, 1234)
    wav = (b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVE" + b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, 11025, 22050, 2, 16)
           + b"data" + struct.pack("<I", len(pcm)) + pcm)
    assert decode_wav(wav) == (1, 11025, pcm), "WAV round trip differs"
    for bad, message in ((b"\x89PNG\r\n\x1a\n" + b"\0" * 4, "truncated"), (wav[:20] + struct.pack("<H", 3) + wav[22:], "format")):
        try:
            (decode_png if bad[:4] == b"\x89PNG" else decode_wav)(bad)
        except AssetError as err:
            assert message in str(err), str(err)
        else:
            raise AssertionError("bad input accepted")
    print("self-test passed: PNG filters 0-4, WAV PCM16 and two rejections")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="*")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not args.files:
        parser.error("name at least one file, or --self-test")
    status = 0
    for path in args.files:
        try:
            print(describe(path))
        except (AssetError, OSError, struct.error, zlib.error) as err:
            print("%s\terror\t%s" % (path, err), file=sys.stderr)
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
