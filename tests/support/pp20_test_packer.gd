class_name Pp20TestPacker
extends RefCounted
## A small PowerPacker ("PP20") compressor, used only to make test input.
##
## It writes the format [Pp20] reads, independently of the decoder: the
## output is described as a list of bits in reading order, which is then laid
## out backwards, least significant bit first, the way the format stores it.
## Matching is a plain greedy search, so the result is valid rather than small.

## The offset widths FrogLord's packer uses for its strongest setting.
const OFFSET_WIDTHS: Array[int] = [9, 10, 12, 13]

var _bits: Array[int] = []


## Compresses [param data] into a PP20 stream, looking back at most
## [param window] bytes for repeats. With [param literals_only] every byte is
## stored as a literal (exercises the literal path alone).
func pack(data: PackedByteArray, window: int = 700, literals_only: bool = false) -> PackedByteArray:
	_bits.clear()
	var pos: int = data.size() # Bytes [pos, size) are already described.
	var literals: Array[int] = []
	while pos > 0:
		var best_length: int = 0
		var best_distance: int = 0
		if not literals_only:
			var max_distance: int = mini(window, 1 << OFFSET_WIDTHS[3])
			for distance: int in range(1, mini(max_distance, data.size() - pos + 1) + 1):
				var length: int = 0
				while length < pos and length < 300 and pos - 1 - length + distance < data.size() \
						and data[pos - 1 - length] == data[pos - 1 - length + distance]:
					length += 1
				if length < 5 and length >= 2 and distance > (1 << OFFSET_WIDTHS[length - 2]):
					length = 0 # Too far for a short copy's offset field.
				if length > best_length:
					best_length = length
					best_distance = distance
		if best_length >= 2:
			_segment(literals, best_length, best_distance)
			literals.clear()
			pos -= best_length
		else:
			pos -= 1
			literals.append(data[pos])
	if not literals.is_empty():
		_segment(literals, 0, 0)
	return _assemble(data.size())


## Writes one segment: optional literal run, then a copy unless [param length] is 0.
func _segment(literals: Array[int], length: int, distance: int) -> void:
	if literals.is_empty():
		_put(1, 1)
	else:
		_put(0, 1)
		var extra: int = literals.size() - 1
		while extra >= 3:
			_put(3, 2)
			extra -= 3
		_put(extra, 2)
		for value: int in literals:
			_put(value, 8)
	if length == 0:
		return
	var offset: int = distance - 1
	if length <= 4:
		var level: int = length - 2
		_put(level, 2)
		_put(offset, OFFSET_WIDTHS[level])
		return
	_put(3, 2)
	if offset < 128:
		_put(0, 1)
		_put(offset, 7)
	else:
		_put(1, 1)
		_put(offset, OFFSET_WIDTHS[3])
	var more: int = length - 5
	while more >= 7:
		_put(7, 3)
		more -= 7
	_put(more, 3)


func _put(value: int, width: int) -> void:
	for i: int in range(width - 1, -1, -1):
		_bits.append((value >> i) & 1)


func _assemble(unpacked_size: int) -> PackedByteArray:
	var skip: int = (8 - _bits.size() % 8) % 8
	var stream: Array[int] = []
	for _i: int in skip:
		stream.append(1) # Padding bits the decoder discards.
	stream.append_array(_bits)
	var body := PackedByteArray()
	body.resize(stream.size() / 8)
	for k: int in body.size():
		var value: int = 0
		for j: int in 8:
			value |= stream[k * 8 + j] << j
		body[body.size() - 1 - k] = value # The first byte read is the last one stored.
	var out: PackedByteArray = "PP20".to_ascii_buffer()
	for width: int in OFFSET_WIDTHS:
		out.append(width)
	out.append_array(body)
	out.append((unpacked_size >> 16) & 0xFF)
	out.append((unpacked_size >> 8) & 0xFF)
	out.append(unpacked_size & 0xFF)
	out.append(skip)
	return out
