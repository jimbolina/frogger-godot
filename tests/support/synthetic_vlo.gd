class_name SyntheticVlo
extends RefCounted
## Builds small PC texture banks ("2GRP") for tests, laid out as the game's
## tools lay them out (see VloFile).


## One image for [method build_vlo]: header values and stored A,B,G,R pixels.
class Spec:
	extends RefCounted
	var vram_x: int = 0
	var vram_y: int = 0
	var padded_width: int = 1
	var padded_height: int = 1
	var width: int = 1
	var height: int = 1
	var texture_id: int = 0
	var flags: int = 0
	var blend_mode: int = 0
	## Stored pixels, A,B,G,R per pixel.
	var abgr := PackedByteArray()


static func spec(w: int, h: int, pad: int, texture_id: int, flags: int, stored: PackedByteArray) -> Spec:
	var s := Spec.new()
	s.padded_width = w + pad
	s.padded_height = h + pad
	s.width = w
	s.height = h
	s.texture_id = texture_id
	s.flags = flags
	s.abgr = stored
	return s


## A "2GRP" bank of [param specs], as the game's tools lay it out.
static func build_vlo(specs: Array[Spec], names_trailer: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array("2GRP".to_ascii_buffer())
	out.resize(12)
	out.encode_s32(4, specs.size())
	out.encode_s32(8, 12)
	var offset: int = 12 + 24 * specs.size()
	var headers := PackedByteArray()
	var pixel_blob := PackedByteArray()
	for s: Spec in specs:
		offset = (offset + 3) & ~3
		var h := PackedByteArray()
		h.resize(24)
		h.encode_s16(0, s.vram_x)
		h.encode_s16(2, s.vram_y)
		h.encode_s16(4, s.padded_width)
		h.encode_s16(6, s.padded_height)
		h.encode_s32(8, offset)
		h.encode_s16(12, s.texture_id)
		h.encode_u16(14, ((s.vram_y / 256) & 0xFF) | (s.blend_mode << 8))
		h.encode_u16(16, s.flags)
		h.encode_s16(18, 0)
		h[20] = (s.vram_x % 256) + (s.padded_width - s.width) / 2
		h[21] = (s.vram_y % 256) + (s.padded_height - s.height) / 2
		h[22] = s.width & 0xFF
		h[23] = s.height & 0xFF
		headers.append_array(h)
		while (12 + 24 * specs.size() + pixel_blob.size()) % 4 != 0:
			pixel_blob.append(0)
		pixel_blob.append_array(s.abgr)
		offset += s.abgr.size()
	out.append_array(headers)
	out.append_array(pixel_blob)
	out.append_array(names_trailer)
	return out


## Stored pixels from R,G,B triples, with alpha byte [param stored_alpha].
static func abgr(rgb: Array[int], stored_alpha: int = 0) -> PackedByteArray:
	var out := PackedByteArray()
	for i: int in range(0, rgb.size(), 3):
		out.append_array(PackedByteArray([stored_alpha, rgb[i + 2], rgb[i + 1], rgb[i]]))
	return out
