class_name PickupDataReader
extends RefCounted
## Reads the pickup (bug) appearance table ([PickupData] per bug kind) from the executable.


## Reads the whole pickup table of [param exe]. Sets [param problems] entries
## for anything unreadable; returns what could be read.
static func read_table(exe: ExeImage, problems: PackedStringArray) -> Array[PickupData]:
	var result: Array[PickupData] = []
	if exe.version.pickup_data <= 0:
		problems.append("this build has no pickup table address")
		return result
	var table: ByteReader = exe.reader_at(exe.version.pickup_data)
	for kind: int in FroggerIds.FLY_SCORE_TYPES.size():
		var data := PickupData.new()
		data.fly_type = kind
		data.pointer = table.read_u32()
		var reader: ByteReader = exe.reader_at_pointer(data.pointer)
		data.glow_colour = reader.read_s32()
		data.sprite_size = reader.read_s32()
		while reader.remaining() >= 4:
			var frame: int = reader.read_u32()
			if frame == 0:
				break
			data.frame_pointers.append(frame)
		if table.has_error() or reader.has_error():
			problems.append("pickup %s: %s" % [data.fly_type_name(), table.error if table.has_error() else reader.error])
			return result
		result.append(data)
	return result
