class_name EmissiveSurfaces
extends RefCounted
## Resolves the glowing images of an [EmissiveImageTable] to global texture ids.


## The entries of [param table] by global texture id, found through
## [param image_names] (FrogLord's image name list); a name the list lacks
## appends one line to [param diagnostics] and is left out. A null table or
## name list gives an empty answer.
static func resolve(table: EmissiveImageTable, image_names: NameBank,
		diagnostics: PackedStringArray) -> Dictionary[int, EmissiveImage]:
	var found: Dictionary[int, EmissiveImage] = {}
	if table == null or table.entries.is_empty():
		return found
	if image_names == null:
		diagnostics.append("No image names; %d emissive images do not glow" % table.entries.size())
		return found
	for entry: EmissiveImage in table.entries:
		if entry == null:
			continue
		var id: int = image_names.index_of(entry.image_name)
		if id < 0:
			diagnostics.append("Emissive image %s is not in the image names; it does not glow" % entry.image_name)
			continue
		found[id] = entry
	return found
