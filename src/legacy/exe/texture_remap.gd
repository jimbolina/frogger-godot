class_name TextureRemap
extends RefCounted
## A texture remap: the list turning a file's local texture numbers into global texture ids.
##
## A map file numbers its textures 0, 1, 2, ... in its own order; the
## executable holds, for each map, a list of 16-bit global texture ids so
## that local number [i]n[/i] means global texture [code]texture_ids[n][/code].
## The global id then selects an image in a loaded texture bank (VLO) through
## the texture pointer list ([BmpPointers]). A few remaps belong to no map
## file (the sky backdrop's [code]txl_sky_land[/code]).

## FrogLord's name for the remap, e.g. "txl_sub1" or "txl_sky_land".
var name: String = ""
## File offset of the first id in the executable.
var file_offset: int = 0
## Resource id of the map using this remap, or -1 when it belongs to no map.
var resource_id: int = -1
## Global texture ids in local order.
var texture_ids: PackedInt32Array = PackedInt32Array()
## Slots available before the next remap begins (at least the id count).
var slots: int = 0


## The global texture id of local texture [param local_index], or -1 when the
## remap has no such entry.
func global_id(local_index: int) -> int:
	return texture_ids[local_index] if local_index >= 0 and local_index < texture_ids.size() else -1


## Number of texture ids.
func size() -> int:
	return texture_ids.size()
