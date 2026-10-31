class_name SyntheticVloBytes
extends RefCounted
## Writes the texture bank specs of [SyntheticVlo] as PC texture banks
## ("2GRP"), laid out as the game's tools lay them out (see VloFile), for the
## reader tests.


## A "2GRP" bank of [param specs], as the game's tools lay it out.
static func build_vlo(specs: Array[SyntheticVlo.Spec], names_trailer: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array("2GRP".to_ascii_buffer())
	out.resize(12)
	out.encode_s32(4, specs.size())
	out.encode_s32(8, 12)
	var offset: int = 12 + 24 * specs.size()
	var headers := PackedByteArray()
	var pixel_blob := PackedByteArray()
	for s: SyntheticVlo.Spec in specs:
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
