class_name ExeSplashAnimListsReader
extends RefCounted
## Finds the water splash sprite animation lists ([ExeSplashAnimLists]) by
## their fixed command shape in the program bytes.


## Finds the splash lists of [param exe], resolving images through [param bmp].
static func read(exe: ExeImage, bmp: BmpPointers) -> ExeSplashAnimLists:
	var result := ExeSplashAnimLists.new()
	if exe == null or not exe.is_valid() or bmp == null or not bmp.error.is_empty():
		result.warnings.append("Splash animation lists need a readable executable and texture pointer list")
		return result
	var prefix: PackedInt64Array = ExeSplashAnimLists.PREFIX
	var words: PackedInt64Array = ExeParticleGeneratorsReader.program_words(exe)
	var length: int = prefix.size() + 2 * ExeSplashAnimLists.IMAGES + 2 * ExeSplashAnimLists.FADES.size() * 2 + 1
	for index: int in words.size() - length:
		if words[index + 7] != prefix[7] or words[index + 6] != prefix[6]:
			continue
		var matches: bool = true
		for slot: int in prefix.size():
			if words[index + slot] != prefix[slot]:
				matches = false
				break
		if not matches:
			continue
		var ids: PackedInt32Array = _ripples(words, index + prefix.size(), bmp)
		var address: int = exe.offset_to_pointer(index * 4)
		if ids.is_empty():
			result.warnings.append("Splash animation list at 0x%X does not have the frozen command shape" % address)
			continue
		result.lists.append(ids)
		result.addresses.append(address)
	if result.lists.is_empty():
		result.warnings.append("No splash animation list was found in the executable")
	for ids: PackedInt32Array in result.lists:
		if ids != result.lists[0]:
			result.warnings.append("The splash animation lists show different ripple images")
			break
	return result


static func _ripples(words: PackedInt64Array, at: int, bmp: BmpPointers) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for slot: int in ExeSplashAnimLists.IMAGES:
		if words[at + 2 * slot] != ExeSplashAnimLists.OP_SETIMAGE:
			return PackedInt32Array()
		var id: int = bmp.texture_id_for_pointer(words[at + 2 * slot + 1])
		if id < 0:
			return PackedInt32Array()
		ids.append(id)
	var last: int = words[at + 2 * ExeSplashAnimLists.IMAGES - 1]
	var cursor: int = at + 2 * ExeSplashAnimLists.IMAGES
	for fade: int in ExeSplashAnimLists.FADES:
		if words[cursor] != ExeSplashAnimLists.OP_SETCOLOUR or words[cursor + 1] != fade \
				or words[cursor + 2] != ExeSplashAnimLists.OP_SETIMAGE or words[cursor + 3] != last:
			return PackedInt32Array()
		cursor += 4
	if words[cursor] != ExeSplashAnimLists.OP_KILL:
		return PackedInt32Array()
	return ids
