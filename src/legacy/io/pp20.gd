class_name Pp20
extends RefCounted
## Decompresses PowerPacker ("PP20") data, the compression used in Frogger's archives.
##
## A PP20 stream is laid out as:
## [codeblock]
## "PP20" [4 offset widths] [packed bit stream ...] [unpacked size: 3 bytes, big-endian] [skip bits: 1 byte]
## [/codeblock]
## The bit stream is read [i]backwards[/i], from the byte before the size
## field towards the start, least significant bit of each byte first; a
## multi-bit field takes its first bit read as its most significant bit. The
## output is produced backwards too, from its last byte to its first, as a
## sequence of literal byte runs and copies of already-produced bytes. This is
## what let the original game decompress files in place.
##
## The decoder follows FrogLord's PP20Unpacker. It is written as one tight
## loop over local variables because every level load decompresses megabytes.

## Offset field widths live at bytes 4..7.
const _HEADER_SIZE: int = 8
## Size (3 bytes) and skip count (1 byte) at the end.
const _TRAILER_SIZE: int = 4

## Why the last [method unpack] failed, or "".
var error: String = ""

static var _reversed_bits: PackedByteArray = PackedByteArray()


## True if [param data] starts with the PP20 marker and is long enough to be a stream.
static func is_packed(data: PackedByteArray) -> bool:
	return data.size() > 11 and data[0] == 0x50 and data[1] == 0x50 and data[2] == 0x32 and data[3] == 0x30


## The unpacked size recorded in the stream's trailer, or -1 if [param data] is not PP20.
static func unpacked_size(data: PackedByteArray) -> int:
	if not is_packed(data):
		return -1
	var n: int = data.size()
	return (data[n - 4] << 16) | (data[n - 3] << 8) | data[n - 2]


## Decompresses [param data]. Returns an empty array and sets [member error] on failure.
func unpack(data: PackedByteArray) -> PackedByteArray:
	error = ""
	if not is_packed(data):
		error = "not PP20 data"
		return PackedByteArray()
	if _reversed_bits.is_empty():
		_build_reversed_bits()
	var rev: PackedByteArray = _reversed_bits
	var widths: PackedInt32Array = PackedInt32Array([data[4], data[5], data[6], data[7]])
	var out_size: int = unpacked_size(data)
	var out := PackedByteArray()
	out.resize(out_size)

	# Bit reader state: `acc` holds `bits` unread bits in its low end, the
	# next bit to read being the highest of them. Bytes are fed from the end.
	var src: int = data.size() - _TRAILER_SIZE - 1
	var src_end: int = _HEADER_SIZE
	var acc: int = 0
	var bits: int = 0
	var out_pos: int = out_size

	# Discard the padding bits recorded in the last byte.
	var skip: int = data[data.size() - 1]
	while bits < skip:
		if src < src_end:
			error = "stream too short for its %d skip bits" % skip
			return PackedByteArray()
		acc = ((acc & 0xFFFFFFFFFF) << 8) | rev[data[src]]
		src -= 1
		bits += 8
	bits -= skip

	while out_pos > 0:
		# One flag bit: 0 means a run of literal bytes comes first.
		if bits < 1:
			if src < src_end:
				break
			acc = ((acc & 0xFFFFFFFFFF) << 8) | rev[data[src]]
			src -= 1
			bits += 8
		bits -= 1
		if ((acc >> bits) & 1) == 0:
			var count: int = 1
			while true:
				if bits < 2:
					if src < src_end:
						error = "stream ended inside a literal run length"
						return PackedByteArray()
					acc = ((acc & 0xFFFFFFFFFF) << 8) | rev[data[src]]
					src -= 1
					bits += 8
				bits -= 2
				var inc: int = (acc >> bits) & 3
				count += inc
				if inc != 3:
					break
			if count > out_pos:
				error = "literal run of %d bytes overflows the output at %d" % [count, out_pos]
				return PackedByteArray()
			for _i: int in count:
				if bits < 8:
					if src < src_end:
						error = "stream ended inside a literal run"
						return PackedByteArray()
					acc = ((acc & 0xFFFFFFFFFF) << 8) | rev[data[src]]
					src -= 1
					bits += 8
				bits -= 8
				out_pos -= 1
				out[out_pos] = (acc >> bits) & 0xFF
			if out_pos == 0:
				break

		# A copy of earlier-produced (higher-addressed) bytes.
		while bits < 16 and src >= src_end:
			acc = ((acc & 0xFFFFFFFFFF) << 8) | rev[data[src]]
			src -= 1
			bits += 8
		if bits < 2:
			error = "stream ended before a copy"
			return PackedByteArray()
		bits -= 2
		var level: int = (acc >> bits) & 3
		var offset_bits: int = widths[level]
		if level == 3:
			bits -= 1
			if ((acc >> bits) & 1) == 0:
				offset_bits = 7
		while bits < offset_bits and src >= src_end:
			acc = ((acc & 0xFFFFFFFFFF) << 8) | rev[data[src]]
			src -= 1
			bits += 8
		if bits < offset_bits:
			error = "stream ended inside a copy offset"
			return PackedByteArray()
		bits -= offset_bits
		var offset: int = (acc >> bits) & ((1 << offset_bits) - 1)
		var length: int = level + 2
		if level == 3:
			while true:
				if bits < 3:
					if src < src_end:
						error = "stream ended inside a copy length"
						return PackedByteArray()
					acc = ((acc & 0xFFFFFFFFFF) << 8) | rev[data[src]]
					src -= 1
					bits += 8
				bits -= 3
				var more: int = (acc >> bits) & 7
				length += more
				if more != 7:
					break
		if length > out_pos or out_pos + offset >= out_size:
			error = "copy of %d bytes from distance %d is out of range at %d" % [length, offset + 1, out_pos]
			return PackedByteArray()
		var distance: int = offset + 1
		if distance >= 4:
			# Source and destination do not overlap within a word: copy 4 bytes at a time.
			while length >= 4:
				out_pos -= 4
				out.encode_u32(out_pos, out.decode_u32(out_pos + distance))
				length -= 4
		for _i: int in length:
			out_pos -= 1
			out[out_pos] = out[out_pos + distance]

	if out_pos != 0:
		error = "stream ended with %d bytes still to produce" % out_pos
		return PackedByteArray()
	return out


static func _build_reversed_bits() -> void:
	_reversed_bits.resize(256)
	for value: int in 256:
		var reversed: int = 0
		for bit: int in 8:
			if value & (1 << bit):
				reversed |= 1 << (7 - bit)
		_reversed_bits[value] = reversed
