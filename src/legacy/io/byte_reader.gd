class_name ByteReader
extends RefCounted
## A little-endian cursor over a window of a [PackedByteArray].
##
## Frogger's data files are little-endian structures written by a 1997 PC and
## PlayStation toolchain. This reader walks them with explicit widths
## (u8/s8/u16/s16/u32/s32) so every field reads exactly the way the original
## code read it.
##
## A reader covers a window [code][base, base + length)[/code] of the shared
## buffer. [method sub_reader] creates a narrower window over the same buffer
## without copying, so a parser can hand a child structure its own reader whose
## positions start at 0.
##
## Errors are sticky rather than fatal: reading past the end of the window
## returns 0 (or an empty value), records a message in [member error], and every
## later read also returns 0. Parsers check [method has_error] once after reading
## a structure. The reader never calls [code]push_error[/code], so malformed
## input can be tested without engine error output.

## The first problem met, or an empty string while the reader is healthy.
var error: String = ""

var _data: PackedByteArray
var _base: int
var _length: int
var _pos: int = 0


## Wraps [param data]. [param base] and [param length] select a window of it;
## a negative [param length] means "to the end of the buffer".
func _init(data: PackedByteArray, base: int = 0, length: int = -1) -> void:
	_data = data
	if base < 0 or base > data.size():
		_base = 0
		_length = 0
		error = "window start %d is outside a buffer of %d bytes" % [base, data.size()]
		return
	_base = base
	if length < 0:
		_length = data.size() - base
	elif base + length > data.size():
		_length = data.size() - base
		error = "window of %d bytes at %d exceeds a buffer of %d bytes" % [length, base, data.size()]
	else:
		_length = length


## Number of bytes in this reader's window.
func size() -> int:
	return _length


## Current cursor position, relative to the start of the window.
func get_position() -> int:
	return _pos


## Moves the cursor to [param position] (window-relative). Moving to exactly
## the end is allowed; beyond it records an error.
func seek(position: int) -> void:
	if position < 0 or position > _length:
		_fail("seek to %d is outside a window of %d bytes" % [position, _length])
		return
	_pos = position


## Advances the cursor by [param count] bytes.
func skip(count: int) -> void:
	seek(_pos + count)


## Advances the cursor to the next multiple of [param alignment].
func align(alignment: int) -> void:
	var over: int = _pos % alignment
	if over != 0:
		skip(alignment - over)


## Bytes left between the cursor and the end of the window.
func remaining() -> int:
	return _length - _pos


## True while at least one byte is left to read.
func has_more() -> bool:
	return _pos < _length


## True once any read or seek has failed.
func has_error() -> bool:
	return not error.is_empty()


## Records [param message] as the reader's error (the first one wins), so a
## parser can report a structural problem through the same channel.
func fail(message: String) -> void:
	_fail(message)


## Absolute offset of this window's first byte in the underlying buffer.
func get_base() -> int:
	return _base


## A reader over [param length] bytes starting at window-relative
## [param offset], sharing this reader's buffer (no copy). Its cursor starts at 0.
func sub_reader(offset: int, length: int) -> ByteReader:
	if offset < 0 or length < 0 or offset + length > _length:
		var bad := ByteReader.new(PackedByteArray())
		bad.error = "sub-window of %d bytes at %d exceeds a window of %d bytes" % [length, offset, _length]
		_fail(bad.error)
		return bad
	return ByteReader.new(_data, _base + offset, length)


## Reads an unsigned byte.
func read_u8() -> int:
	if not _can_read(1):
		return 0
	var v: int = _data.decode_u8(_base + _pos)
	_pos += 1
	return v


## Reads a signed byte.
func read_s8() -> int:
	if not _can_read(1):
		return 0
	var v: int = _data.decode_s8(_base + _pos)
	_pos += 1
	return v


## Reads an unsigned little-endian 16-bit value.
func read_u16() -> int:
	if not _can_read(2):
		return 0
	var v: int = _data.decode_u16(_base + _pos)
	_pos += 2
	return v


## Reads a signed little-endian 16-bit value.
func read_s16() -> int:
	if not _can_read(2):
		return 0
	var v: int = _data.decode_s16(_base + _pos)
	_pos += 2
	return v


## Reads an unsigned little-endian 32-bit value (0 .. 0xFFFFFFFF).
func read_u32() -> int:
	if not _can_read(4):
		return 0
	var v: int = _data.decode_u32(_base + _pos)
	_pos += 4
	return v


## Reads a signed little-endian 32-bit value.
func read_s32() -> int:
	if not _can_read(4):
		return 0
	var v: int = _data.decode_s32(_base + _pos)
	_pos += 4
	return v


## Reads an unsigned byte at window-relative [param offset] without moving the cursor.
func u8_at(offset: int) -> int:
	return _data.decode_u8(_base + offset) if _in_window(offset, 1) else 0


## Reads an unsigned 16-bit value at [param offset] without moving the cursor.
func u16_at(offset: int) -> int:
	return _data.decode_u16(_base + offset) if _in_window(offset, 2) else 0


## Reads a signed 16-bit value at [param offset] without moving the cursor.
func s16_at(offset: int) -> int:
	return _data.decode_s16(_base + offset) if _in_window(offset, 2) else 0


## Reads an unsigned 32-bit value at [param offset] without moving the cursor.
func u32_at(offset: int) -> int:
	return _data.decode_u32(_base + offset) if _in_window(offset, 4) else 0


## Reads a signed 32-bit value at [param offset] without moving the cursor.
func s32_at(offset: int) -> int:
	return _data.decode_s32(_base + offset) if _in_window(offset, 4) else 0


## Copies the next [param count] bytes out.
func read_bytes(count: int) -> PackedByteArray:
	if count < 0 or not _can_read(count):
		return PackedByteArray()
	var start: int = _base + _pos
	_pos += count
	return _data.slice(start, start + count)


## Copies the whole window out (independent of the cursor).
func to_bytes() -> PackedByteArray:
	return _data.slice(_base, _base + _length)


## Reads a fixed-size ASCII field of [param count] bytes; the text stops at the
## first NUL, and the cursor always moves by [param count].
func read_fixed_string(count: int) -> String:
	var raw := read_bytes(count)
	var end: int = raw.find(0)
	if end >= 0:
		raw = raw.slice(0, end)
	return raw.get_string_from_ascii()


## Reads a NUL-terminated ASCII string and moves past its terminator. A
## missing terminator before the window end records an error.
func read_cstring() -> String:
	var text := cstring_at(_pos)
	if has_error():
		return ""
	_pos += text.length() + 1
	return text


## Reads the NUL-terminated ASCII string at window-relative [param offset]
## without moving the cursor.
func cstring_at(offset: int) -> String:
	if offset < 0 or offset >= _length:
		_fail("string at %d is outside a window of %d bytes" % [offset, _length])
		return ""
	var start: int = _base + offset
	var end: int = _data.find(0, start)
	if end < 0 or end >= _base + _length:
		_fail("string at %d has no terminator inside the window" % offset)
		return ""
	return _data.slice(start, end).get_string_from_ascii()


## Reads [param text].length() bytes and compares them with [param text];
## a mismatch records an error and returns false.
func expect_signature(text: String) -> bool:
	var at: int = _pos
	var got := read_bytes(text.length())
	if has_error():
		return false
	if got != text.to_ascii_buffer():
		_fail("expected signature '%s' at %d, found '%s'" % [text, at, got.get_string_from_ascii()])
		return false
	return true


func _can_read(count: int) -> bool:
	if not error.is_empty():
		return false
	if _pos + count > _length:
		_fail("read of %d bytes at %d exceeds a window of %d bytes" % [count, _pos, _length])
		return false
	return true


func _in_window(offset: int, count: int) -> bool:
	if offset < 0 or offset + count > _length:
		_fail("read of %d bytes at %d exceeds a window of %d bytes" % [count, offset, _length])
		return false
	return true


func _fail(message: String) -> void:
	if error.is_empty():
		error = message
