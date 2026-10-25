class_name TextureRemapList
extends RefCounted
## Every texture remap in the executable, found and sized the way FrogLord does.
##
## Remaps are found through the tables that point at them: the level list
## (each row's high- and low-poly map remap) and the build's
## [code]txl_sky_land[/code] address. Remaps store no length, so (as in
## FrogLord's [code]SCGameInstance.updateRemap[/code]) they are sorted by
## address and each one is read as 16-bit ids until:
## [br]- a zero id (the list terminator), or
## [br]- the start of the next remap.
## [br]After a zero terminator, further zero padding up to the next remap is
## skipped. If more than 4 unexplained bytes are left before the next remap,
## they are read as an extra, unnamed remap ("txl_unknown"), which is how
## FrogLord keeps remaps that no table points at.
##
## Rows of the level list with a zero map id are ignored even if they carry a
## remap address, and an address met twice is registered once.

## Remaps in address order.
var remaps: Array[TextureRemap] = []
## Why reading failed, or "".
var error: String = ""

var _by_resource: Dictionary[int, TextureRemap] = {}
var _by_name: Dictionary[String, TextureRemap] = {}


## Finds and reads every remap of [param exe], naming map remaps after their
## files in [param mwi] and using the rows of [param map_book].
static func read(exe: ExeImage, mwi: MwiIndex, map_book: MapBook) -> TextureRemapList:
	var list := TextureRemapList.new()
	var found: Dictionary[int, TextureRemap] = {}
	if exe.version.txl_sky_land > 0:
		list._register(found, exe.version.txl_sky_land, "txl_sky_land", -1)
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
			list._register(found, exe.pointer_to_offset(pointer), remap_name, map_id)
	var starts: Array[int] = found.keys()
	starts.sort()
	var i: int = 0
	while i < starts.size():
		var next_start: int = starts[i + 1] if i + 1 < starts.size() else -1
		var remap: TextureRemap = found[starts[i]]
		var end: int = list._read_ids(exe, remap, next_start)
		if not list.error.is_empty():
			return list
		list.remaps.append(remap)
		if next_start >= 0 and next_start - end > 4:
			list._register(found, end, "txl_unknown", -1)
			starts.insert(i + 1, end)
		i += 1
	for remap: TextureRemap in list.remaps:
		if remap.resource_id >= 0 and not list._by_resource.has(remap.resource_id):
			list._by_resource[remap.resource_id] = remap
		if not remap.name.is_empty() and not list._by_name.has(remap.name):
			list._by_name[remap.name] = remap
	return list


## Number of remaps.
func size() -> int:
	return remaps.size()


## The remap of map resource [param map_resource_id], or null.
func for_resource(map_resource_id: int) -> TextureRemap:
	return _by_resource[map_resource_id] if _by_resource.has(map_resource_id) else null


## The remap called [param remap_name] (e.g. "txl_sky_land"), or null.
func find_by_name(remap_name: String) -> TextureRemap:
	return _by_name[remap_name] if _by_name.has(remap_name) else null


## Total number of ids in all remaps.
func id_count() -> int:
	var n: int = 0
	for remap: TextureRemap in remaps:
		n += remap.size()
	return n


func _register(found: Dictionary[int, TextureRemap], offset: int, remap_name: String, resource: int) -> void:
	if found.has(offset):
		return
	var remap := TextureRemap.new()
	remap.name = remap_name
	remap.file_offset = offset
	remap.resource_id = resource
	found[offset] = remap


func _read_ids(exe: ExeImage, remap: TextureRemap, next_start: int) -> int:
	var reader: ByteReader = exe.reader_at(remap.file_offset)
	if reader.has_error():
		error = "%s at %d: %s" % [remap.name, remap.file_offset, reader.error]
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
