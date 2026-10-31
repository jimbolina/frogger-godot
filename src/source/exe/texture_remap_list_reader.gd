class_name TextureRemapListReader
extends RefCounted
## Finds and sizes every texture remap ([TextureRemapList]) in the executable, as FrogLord does.


## Finds and reads every remap of [param exe], naming map remaps after their
## files in [param mwi] and using the rows of [param map_book].
static func read(exe: ExeImage, mwi: MwiIndex, map_book: MapBook) -> TextureRemapList:
	var list := TextureRemapList.new()
	var found: Dictionary[int, TextureRemap] = {}
	if exe.version.txl_sky_land > 0:
		_register(found, exe.version.txl_sky_land, "txl_sky_land", -1)
	for row: MapBookEntry in map_book.entries:
		for low_poly: bool in [false, true]:
			var map_id: int = row.map_id(low_poly)
			var pointer: int = row.remap_pointer(low_poly)
			if map_id <= 0 or pointer <= 0:
				continue
			var entry: MwiEntry = mwi.get_entry(map_id)
			if entry == null:
				continue
			var remap_name: String = ""
			if not entry.path.is_empty():
				remap_name = "txl_" + entry.display_name().get_basename().to_lower()
			_register(found, exe.pointer_to_offset(pointer), remap_name, map_id)
	var starts: Array[int] = found.keys()
	starts.sort()
	var i: int = 0
	while i < starts.size():
		var next_start: int = starts[i + 1] if i + 1 < starts.size() else -1
		var remap: TextureRemap = found[starts[i]]
		var end: int = _read_ids(list, exe, remap, next_start)
		if not list.error.is_empty():
			return list
		list.remaps.append(remap)
		if next_start >= 0 and next_start - end > 4:
			_register(found, end, "txl_unknown", -1)
			starts.insert(i + 1, end)
		i += 1
	return list


static func _register(found: Dictionary[int, TextureRemap], offset: int, remap_name: String, resource: int) -> void:
	if found.has(offset):
		return
	var remap := TextureRemap.new()
	remap.name = remap_name
	remap.file_offset = offset
	remap.resource_id = resource
	found[offset] = remap


static func _read_ids(list: TextureRemapList, exe: ExeImage, remap: TextureRemap, next_start: int) -> int:
	var reader: ByteReader = exe.reader_at(remap.file_offset)
	if reader.has_error():
		list.error = "%s at %d: %s" % [remap.name, remap.file_offset, reader.error]
		return 0
	var value: int = 0
	while reader.remaining() >= 2:
		value = reader.read_s16()
		if value == 0 or (next_start >= 0 and reader.get_position() - 2 >= next_start):
			break
		remap.texture_ids.append(value)
	var pos: int = reader.get_position()
	if value != 0:
		if not remap.texture_ids.is_empty():
			pos -= 2
	else:
		var limit: int = next_start if next_start >= 0 else exe.program_length
		while limit >= pos and pos + 2 <= exe.program_length:
			var padding: int = reader.s16_at(pos)
			pos += 2
			if padding != 0:
				break
		pos -= 2
	remap.slots = maxi(remap.texture_ids.size(), (pos - remap.file_offset) / 2)
	return pos
