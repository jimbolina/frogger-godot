class_name TextureRemapList
extends Resource
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
@export var remaps: Array[TextureRemap] = []
## Why reading failed, or "".
@export var error: String = ""

var _by_resource: Dictionary[int, TextureRemap] = {}
var _by_name: Dictionary[String, TextureRemap] = {}


## Finds and reads every remap of [param exe] (see [TextureRemapListReader]).
static func read(exe: ExeImage, mwi: MwiIndex, map_book: MapBook) -> TextureRemapList:
	return TextureRemapListReader.read(exe, mwi, map_book)


## Number of remaps.
func size() -> int:
	return remaps.size()


## The remap of map resource [param map_resource_id], or null.
func for_resource(map_resource_id: int) -> TextureRemap:
	_index()
	return _by_resource[map_resource_id] if _by_resource.has(map_resource_id) else null


## The remap called [param remap_name] (e.g. "txl_sky_land"), or null.
func find_by_name(remap_name: String) -> TextureRemap:
	_index()
	return _by_name[remap_name] if _by_name.has(remap_name) else null


## Total number of ids in all remaps.
func id_count() -> int:
	var n: int = 0
	for remap: TextureRemap in remaps:
		n += remap.size()
	return n


func _index() -> void:
	if not error.is_empty() or not _by_resource.is_empty() or not _by_name.is_empty():
		return
	for remap: TextureRemap in remaps:
		if remap.resource_id >= 0 and not _by_resource.has(remap.resource_id):
			_by_resource[remap.resource_id] = remap
		if not remap.name.is_empty() and not _by_name.has(remap.name):
			_by_name[remap.name] = remap
