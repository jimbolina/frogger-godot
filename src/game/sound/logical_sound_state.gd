class_name LogicalSoundState
extends RefCounted
## Transaction-owned source allocation, moving-object order and deterministic sound clock.

var definitions: Array[LogicalSoundDefinition] = []
var voices: Array[LogicalSoundVoice] = []
var moving: Array[LogicalMovingSound] = []
var next_identifier: int = 1
var listener: Vector3i = Vector3i.ZERO
var old_listener: Vector3i = Vector3i.ZERO
var listener_enabled: bool = true
var error: String = ""

## Validates and detaches all supplied sample facts before creating empty voice slots.
static func create(samples: Array[LogicalSoundDefinition]) -> LogicalSoundState:
	var result := LogicalSoundState.new()
	var identifiers: Dictionary[int, bool] = {}
	for sample: LogicalSoundDefinition in samples:
		if sample == null or not sample.validate().is_empty() or identifiers.has(sample.sound_id):
			result.error = "Invalid or duplicate logical sound metadata"
			return result
		identifiers[sample.sound_id] = true
		result.definitions.append(sample.copy())
	for index: int in 24:
		result.voices.append(LogicalSoundVoice.new())
	return result

## Allocates the first empty group voice; failure consumes neither RNG nor an identifier.
func play(sound_id: int, random: SourceRandom, pitch_offset: int = 0) -> int:
	var sample: LogicalSoundDefinition = _sample(sound_id)
	if sample == null or random == null:
		error = "Logical sound request requires verified sample metadata and RNG"
		return -1
	for index: int in range(sample.first_voice, sample.last_voice + 1):
		if voices[index].sample != null:
			continue
		var voice := LogicalSoundVoice.new()
		voice.sample = sample.copy()
		voice.identifier = next_identifier
		voice.initialising = true
		voice.note = sample.note
		if pitch_offset != 0:
			voice.note += pitch_offset >> 7
			voice.fine = pitch_offset & 127
		elif sample.pitch_mod != 0:
			var addition: int = random.next_value("sound:%d:pitch" % sound_id) & (sample.pitch_mod - 1)
			voice.note += (addition >> 7) - (sample.pitch_mod >> 8)
			voice.fine = addition & 127
		voice.key_on()
		voices[index] = voice
		next_identifier += 1
		if next_identifier == 32767:
			next_identifier = 1
		return (voice.identifier << 16) | index
	return -1

## Adds a voiceless source moving object at the head of its update list.
func create_moving(owner: int, sound_id: int, near_radius: int, far_radius: int, position: Vector3i, doppler: bool = true) -> String:
	near_radius = 1792 if near_radius == -1 else near_radius & 65535
	far_radius = 7168 if far_radius == -1 else far_radius & 65535
	if owner < 0 or _sample(sound_id) == null or far_radius == near_radius or moving_for(owner) != null:
		return "Invalid logical moving sound creation"
	var value := LogicalMovingSound.new()
	value.owner = owner
	value.sound_id = sound_id
	value.near_radius = near_radius
	value.far_radius = far_radius
	value.position = position
	value.old_position = position
	value.doppler = doppler
	moving.push_front(value)
	return ""

## Resolves a moving object by its typed entity identity.
func moving_for(owner: int) -> LogicalMovingSound:
	for value: LogicalMovingSound in moving:
		if value.owner == owner:
			return value
	return null

## Releases a logical moving owner and its voice immediately at the source retirement.
func retire_moving(owner: int) -> void:
	for index: int in moving.size():
		if moving[index].owner == owner:
			kill(moving[index].voice_tag)
			moving.remove_at(index)
			return

## Kills a matching generation without confusing a recycled voice slot.
func kill(tag: int) -> void:
	var index: int = _voice_index(tag)
	if index >= 0:
		voices[index].killed = true
		voices[index].playing = false
		voices[index].moving_owner = -1

## Applies a logical pitch update only to the matching live voice generation.
func bend(tag: int, pitch: int) -> void:
	var index: int = _voice_index(tag)
	if index >= 0:
		voices[index].bend(pitch)

## Pumps the frozen native quantum, then performs moving and voice updates before input.
func advance(random: SourceRandom) -> String:
	if random == null or voices.size() != 24:
		return "Logical sound advancement requires initialized state and RNG"
	for voice: LogicalSoundVoice in voices:
		voice.advance(735)
	if listener_enabled:
		var ordered: Array[LogicalMovingSound] = moving.duplicate()
		for value: LogicalMovingSound in ordered:
			var radius: int = _radius(value.position - listener)
			if value.voice_tag >= 0:
				var slot: int = value.voice_tag & 65535
				if voices[slot].sample == null:
					retire_moving(value.owner)
					continue
				if radius > value.far_radius:
					kill(value.voice_tag)
					value.voice_tag = -1
			elif radius <= value.far_radius:
				value.voice_tag = play(value.sound_id, random)
				if not error.is_empty():
					return error
				if value.voice_tag >= 0:
					voices[value.voice_tag & 65535].moving_owner = value.owner
			if value.voice_tag >= 0 and value.doppler:
				var old_radius: int = _radius(value.old_position - old_listener)
				var change: int = clampi(PlatformMath.s16(radius - old_radius), -512, 511)
				bend(value.voice_tag, (-change * 127) / 512)
	for voice: LogicalSoundVoice in voices:
		if voice.sample == null:
			continue
		if voice.initialising:
			voice.initialising = false
		elif not voice.playing:
			if not voice.killed and voice.sample.flags == LogicalSoundDefinition.REPEAT:
				voice.initialising = true
				voice.key_on()
			else:
				voice.sample = null
				if voice.moving_owner >= 0:
					retire_moving(voice.moving_owner)
	return ""

## Detaches every voice and moving owner for rollback and checkpoint persistence.
func copy() -> LogicalSoundState:
	var result := LogicalSoundState.new()
	for sample: LogicalSoundDefinition in definitions:
		result.definitions.append(sample.copy())
	for voice: LogicalSoundVoice in voices:
		result.voices.append(voice.copy())
	for value: LogicalMovingSound in moving:
		result.moving.append(value.copy())
	result.next_identifier = next_identifier
	result.listener = listener
	result.old_listener = old_listener
	result.listener_enabled = listener_enabled
	result.error = error
	return result

func _sample(sound_id: int) -> LogicalSoundDefinition:
	for sample: LogicalSoundDefinition in definitions:
		if sample.sound_id == sound_id:
			return sample
	return null

func _voice_index(tag: int) -> int:
	if tag < 0:
		return -1
	var index: int = tag & 65535
	return index if index < voices.size() and voices[index].sample != null and voices[index].identifier == tag >> 16 else -1

static func _radius(delta: Vector3i) -> int:
	var reduced := Vector3i(delta.x >> 4, delta.y >> 4, delta.z >> 4)
	return (int(sqrt(reduced.x * reduced.x + reduced.y * reduced.y + reduced.z * reduced.z)) << 4) & 65535
