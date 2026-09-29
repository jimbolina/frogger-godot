class_name PickupData
extends RefCounted
## How one kind of bug (pickup) looks: glow colour, size and animation frames.
##
## The pickup table is one address per bug kind ([constant FroggerIds.FLY_SCORE_TYPES],
## 19 on PC). Each address points at (FrogLord's [code]FroggerPickupData[/code]):
## [codeblock]
## s32 glow colour (0x00BBGGRR)   s32 sprite size (16.16 fixed point, 0x10000 = 1.0)
## u32 texture record address per animation frame ... u32 0 (end)
## [/codeblock]

## Bug kind number (index into [constant FroggerIds.FLY_SCORE_TYPES]).
var fly_type: int = 0
## Address of this record in the program.
var pointer: int = 0
## Colour of the glow sphere, 0x00BBGGRR.
var glow_colour: int = 0
## Sprite scale in 16.16 fixed point.
var sprite_size: int = 0
## Texture record address of each animation frame.
var frame_pointers: PackedInt64Array = PackedInt64Array()


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


## The bug kind's name, e.g. "SCORE_100".
func fly_type_name() -> String:
	return FroggerIds.FLY_SCORE_TYPES[fly_type] if fly_type >= 0 and fly_type < FroggerIds.FLY_SCORE_TYPES.size() else ""
