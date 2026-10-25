class_name MapAnimationPlayer
extends RefCounted
## Deterministic 30 Hz MAP_ANIM state. Source records and shared cel lists
## remain immutable; each track owns its counters.

class Track extends RefCounted:
	var source: MapAnimation
	var offset: int = 0
	var uv_count: int = 0
	var cel_count: int = 0
	var cel: int = 0
	var image: int = -1
	var initial_image: int = -1
	var cels := PackedInt32Array()

var tick: int = -1
var diagnostics := PackedStringArray()
var _tracks: Array[Track] = []
var _base: Dictionary[int, PackedVector2Array] = {}
var _images: Dictionary[int, int] = {}
var _original_images: Dictionary[int, int] = {}
var _uvs: Dictionary[int, PackedVector2Array] = {}
var _library: TextureLibrary
var _preferred: VloFile


## Resolves local texture ids and derives pixel bases once from original images.
func configure(polygons: Array[MapPolygon], animations: Array[MapAnimation],
		remap: TextureRemap, library: TextureLibrary, preferred: VloFile = null) -> void:
	_library = library
	_preferred = preferred
	_tracks.clear()
	_base.clear()
	_images.clear()
	_original_images.clear()
	diagnostics.clear()
	for index: int in polygons.size():
		var polygon: MapPolygon = polygons[index]
		var global_id: int = remap.global_id(polygon.texture_id)
		_images[index] = global_id
		_original_images[index] = global_id
		var image: VloImage = library.image_for_id(global_id, preferred)
		var pixels := PackedVector2Array()
		if image != null:
			for uv: Vector2 in polygon.uvs:
				@warning_ignore("integer_division")
				var u: int = roundi(uv.x * 255.0) * image.width / 255
				@warning_ignore("integer_division")
				var v: int = roundi(uv.y * 255.0) * image.height / 255
				pixels.append(Vector2(u & 255, v & 255))
		elif polygon.texture_id >= 0:
			diagnostics.append("Polygon %d original texture %d is unavailable; pixel UV base cannot be resolved, renderer uses zero base even after valid texture cels" % [index, global_id])
		_base[index] = pixels
	for animation: MapAnimation in animations:
		var track := Track.new()
		track.source = animation
		for local_id: int in animation.texture_ids:
			var cel_id: int = remap.global_id(local_id)
			track.cels.append(cel_id)
			if library.image_for_id(cel_id, preferred) == null:
				diagnostics.append("Animation at 0x%x texture %d is unavailable" % [animation.source_offset, cel_id])
		if (animation.type & 2) and (track.cels.is_empty() or animation.initial_cel >= track.cels.size()):
			diagnostics.append("Animation at 0x%x has an unavailable cel range" % animation.source_offset)
		for target: int in animation.target_polygon_indices:
			if _images.has(target):
				track.initial_image = _images[target]
			else:
				diagnostics.append("Animation target %d is outside polygons" % target)
		_tracks.append(track)
	reset()


## Restores the load-time state, before the first game update.
func reset() -> void:
	tick = -1
	_uvs.clear()
	_images = _original_images.duplicate()
	for index: int in _base:
		_uvs[index] = _base[index].duplicate()
	for track: Track in _tracks:
		track.offset = (track.source.initial_u & 255) | ((track.source.initial_v & 255) << 8)
		track.uv_count = track.source.initial_uv_count
		track.cel_count = track.source.initial_cel_count
		track.cel = track.source.initial_cel
		track.image = track.initial_image


## Performs one C MapUpdateAnimatedPolys update, including byte/ushort wraps.
func step() -> void:
	tick += 1
	for track: Track in _tracks:
		var source: MapAnimation = track.source
		if source.type & 1:
			track.uv_count = (track.uv_count + 1) & 65535
			if track.uv_count == source.uv_frame_count:
				track.offset = 0
				track.uv_count = 0
			else:
				track.offset = (track.offset + (source.delta_u & 255) + ((source.delta_v & 255) << 8)) & 65535
		if source.type & 2 and not track.cels.is_empty():
			track.cel_count = (track.cel_count + 1) & 65535
			if track.cel_count >= source.frames_per_texture:
				track.cel_count = 0
				track.cel = (track.cel + 1) & 65535
				if track.cel == track.cels.size():
					track.cel = 0
				if track.cel < track.cels.size():
					track.image = track.cels[track.cel]
		var image: VloImage = _library.image_for_id(track.image, _preferred)
		for target: int in source.target_polygon_indices:
			if not _base.has(target):
				continue
			_images[target] = track.image
			var result := PackedVector2Array()
			var base: PackedVector2Array = _base[target]
			if image != null:
				var u: int = (image.u + (track.offset & 255)) & 255
				var v: int = (image.v + (track.offset >> 8)) & 255
				for point: Vector2 in base:
					result.append(Vector2(((int(point.x) + u) & 255) - image.u,
						((int(point.y) + v) & 255) - image.v))
			_uvs[target] = result


## Replays from load state; tick zero includes the first update.
func seek(to_tick: int) -> void:
	reset()
	for _index: int in maxi(0, to_tick + 1):
		step()


## Global image id at the current tick, or -1 for an unknown target.
func image_id(polygon_index: int) -> int:
	return _images.get(polygon_index, -1)


## Pixel coordinates relative to the current image's in-game origin.
func pixel_uvs(polygon_index: int) -> PackedVector2Array:
	var result: PackedVector2Array = _uvs.get(polygon_index, PackedVector2Array())
	return result.duplicate()


## Current track image for material overrides without rebuilding geometry.
func track_image_id(track_index: int) -> int:
	return _tracks[track_index].image if track_index >= 0 and track_index < _tracks.size() else -1


## Wrapped byte offsets, shared by all targets of a track. The shader adds
## image u/v, wraps each final byte, then subtracts the current image origin.
func track_offset(track_index: int) -> Vector2i:
	if track_index < 0 or track_index >= _tracks.size():
		return Vector2i.ZERO
	var offset: int = _tracks[track_index].offset
	return Vector2i(offset & 255, offset >> 8)


## Counter snapshot for diagnostics and independent C fact comparisons.
func track_counters(track_index: int) -> PackedInt32Array:
	if track_index < 0 or track_index >= _tracks.size():
		return PackedInt32Array()
	var track: Track = _tracks[track_index]
	return PackedInt32Array([track.uv_count, track.cel, track.cel_count])


## Immutable pixel UV base for building animated surfaces once.
func base_pixel_uvs(polygon_index: int) -> PackedVector2Array:
	var result: PackedVector2Array = _base.get(polygon_index, PackedVector2Array())
	return result.duplicate()
