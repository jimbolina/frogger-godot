class_name AudioResources
extends RefCounted
## Playable sound-effect streams per global sound id, with the frozen pitch, volume and pan rules.
##
## Streams are built on first request, loading each sound bank once. Every
## stream plays at the frozen 11025 Hz reference ([constant MIX_RATE]) whatever
## its header rate, so [method pitch_scale] alone reproduces the native step.
## LOOPED samples loop over the whole sample; REPEAT samples, which the frozen
## backend retriggers until killed, loop the same way. A sound that cannot be
## built returns [code]null[/code] and adds one entry to [member diagnostics].

const MIX_RATE: int = 11025
const OUTPUT_RATE: int = 44100
const DEFAULT_EFFECT_VOLUME: int = 79
const MAX_VOLUME_LEVEL: int = 127

var diagnostics: PackedStringArray = PackedStringArray()
var _definitions: Dictionary[int, LogicalSoundDefinition] = {}
var _bank_of: Dictionary[int, int] = {}
var _loader: Callable = Callable()
var _banks: Dictionary[int, SoundBankSetup] = {}
var _streams: Dictionary[int, AudioStreamWAV] = {}
var _failed: Dictionary[int, bool] = {}

## Resolves banks through the supplied executable's sound tables; loading waits for the first request.
static func from_data(data: AssetCatalog, definitions: Array[LogicalSoundDefinition]) -> AudioResources:
	if data == null or not data.is_valid():
		var invalid := from_loader(definitions, {}, Callable())
		invalid.diagnostics.append("Audio resources require valid supplied game data")
		return invalid
	var tables: SoundTables = data.tables.sound_tables()
	var bank_of: Dictionary[int, int] = {}
	for sample: SoundSampleEntry in tables.samples:
		bank_of[sample.sound_id] = sample.bank_id
	var banks: Array[Vector2i] = tables.banks
	var loader: Callable = func(bank_id: int) -> SoundBankSetup:
		if bank_id < 0 or bank_id >= banks.size():
			var missing := SoundBankSetup.new()
			missing.error = "Unknown sound bank %d" % bank_id
			return missing
		return SoundBankSetup.from_resources(data, banks[bank_id].x, banks[bank_id].y)
	var result := from_loader(definitions, bank_of, loader)
	if not tables.error.is_empty():
		result.diagnostics.append(tables.error)
	return result

## Uses [param loader], called as [code]loader(bank_id) -> SoundBankSetup[/code], for each bank in [param bank_of].
static func from_loader(definitions: Array[LogicalSoundDefinition], bank_of: Dictionary[int, int], loader: Callable) -> AudioResources:
	var result := AudioResources.new()
	for definition: LogicalSoundDefinition in definitions:
		if definition != null:
			result._definitions[definition.sound_id] = definition
	result._bank_of = bank_of
	result._loader = loader
	return result

## The detached definition for [param sound_id], or [code]null[/code].
func definition_for(sound_id: int) -> LogicalSoundDefinition:
	return _definitions[sound_id] if _definitions.has(sound_id) else null

## The stream for [param sound_id], loading its bank on first use; [code]null[/code] after a diagnostic.
func stream_for(sound_id: int) -> AudioStreamWAV:
	if _streams.has(sound_id):
		return _streams[sound_id]
	if _failed.has(sound_id):
		return null
	var problem: String = ""
	var definition: LogicalSoundDefinition = definition_for(sound_id)
	var bank: SoundBankSetup = null
	if definition == null:
		problem = "Sound %d has no logical definition" % sound_id
	elif not _bank_of.has(sound_id):
		problem = "Sound %d has no sound bank" % sound_id
	else:
		bank = _bank(_bank_of[sound_id])
		if not bank.error.is_empty():
			problem = "Sound %d bank %d: %s" % [sound_id, _bank_of[sound_id], bank.error]
		elif bank.header == null or sound_id >= bank.header.entries.size():
			problem = "Sound %d is missing from bank %d" % [sound_id, _bank_of[sound_id]]
	if problem.is_empty():
		var pcm: SoundBankPcm = SoundBankPcm.slice(bank.header.entries[sound_id], bank.body)
		problem = pcm.error
		if problem.is_empty():
			_streams[sound_id] = build_stream(pcm, definition.flags)
			return _streams[sound_id]
	_failed[sound_id] = true
	diagnostics.append(problem)
	return null

## Builds a mono 16-bit stream at [constant MIX_RATE], looping whole LOOPED and REPEAT samples.
static func build_stream(pcm: SoundBankPcm, flags: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.mix_rate = MIX_RATE
	stream.data = pcm.to_signed_16()
	if flags == LogicalSoundDefinition.LOOPED or flags == LogicalSoundDefinition.REPEAT:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = pcm.frame_count()
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream

## Wraps Redbook PCM ([DiscAudio]'s 16-bit stereo 44100 Hz) as a stream, optionally looping the whole track.
static func music_stream(pcm: PackedByteArray, looping: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = DiscAudio.SAMPLE_RATE
	stream.data = pcm
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = pcm.size() / 4
	return stream

## Playback-rate ratio for a [constant MIX_RATE] stream, using [method LogicalSoundVoice.key_on]'s rounded 16.16 step.
static func pitch_scale(note: int, fine: int, bend: int = 64) -> float:
	var voice := LogicalSoundVoice.new()
	voice.note = note
	voice.fine = fine
	voice.key_on()
	voice.bend(bend)
	return float(voice.step_16) * float(OUTPUT_RATE) / (65536.0 * float(MIX_RATE))

## Requested left and right levels (0..127) of a fixed voice: the sample's maximum volume on both sides.
static func fixed_volumes(definition: LogicalSoundDefinition) -> Vector2i:
	return Vector2i(definition.maximum_volume, definition.maximum_volume)

## Requested left and right levels of a moving voice, mirroring MRSNDUpdateMovingSounds' fade and soft pan.
##
## [param listener_matrix] holds at least the nine 4.12 rotation entries of
## the listener (the frog's transform); an empty array means no rotation.
static func moving_volumes(definition: LogicalSoundDefinition, moving: LogicalMovingSound, listener: Vector3i, listener_matrix: PackedInt32Array = PackedInt32Array()) -> Vector2i:
	var delta: Vector3i = moving.position - listener
	var volume: int = fade_volume(definition, radius(delta), moving.near_radius, moving.far_radius)
	var matrix: PackedInt32Array = listener_matrix if listener_matrix.size() >= 9 else EntityTransform.IDENTITY
	var pan: Vector3i = PlatformMath.apply(PlatformMath.transpose(matrix), normalise(delta))
	var side: int = clampi(pan.x + 4096, 0, 8191)
	return Vector2i((volume * (8191 - side)) >> 18, (volume * side) >> 18)

## The 0..4095 faded level between the sample's maximum at [param near_radius] and minimum at [param far_radius].
static func fade_volume(definition: LogicalSoundDefinition, distance: int, near_radius: int, far_radius: int) -> int:
	if far_radius == near_radius:
		return (definition.maximum_volume << 5) & 65535
	var clamped: int = mini(maxi(distance, near_radius), far_radius)
	var angle: int = PlatformMath.divide(1024 * (clamped - near_radius), far_radius - near_radius)
	var volume: int = ((4096 - rsin(angle)) * (definition.maximum_volume - definition.minimum_volume)) >> 7
	return ((volume & 65535) + (definition.minimum_volume << 5)) & 65535

## The frozen moving-sound radius: components reduced by 16, integer root, scaled back, stored in 16 bits.
static func radius(delta: Vector3i) -> int:
	var reduced := Vector3i(delta.x >> 4, delta.y >> 4, delta.z >> 4)
	return (int(sqrt(reduced.x * reduced.x + reduced.y * reduced.y + reduced.z * reduced.z)) << 4) & 65535

## Unit vector at 4.12 scale with components rounded half away from zero; zero for a zero vector.
static func normalise(vector: Vector3i) -> Vector3i:
	var length: float = Vector3(vector).length()
	if length == 0.0:
		return Vector3i.ZERO
	return Vector3i(roundi(vector.x * 4096.0 / length), roundi(vector.y * 4096.0 / length), roundi(vector.z * 4096.0 / length))

## Rounded 4.12 sine of a 4096-step angle.
static func rsin(angle: int) -> int:
	return roundi(sin(float(angle & 4095) * TAU / 4096.0) * 4096.0)

## Linear amplitude of a requested 0..127 level after the effect-volume scaling and the mixer's division by 127.
static func gain(volume: int, effect_volume: int = DEFAULT_EFFECT_VOLUME) -> float:
	return float((clampi(volume, 0, MAX_VOLUME_LEVEL) * clampi(effect_volume, 0, MAX_VOLUME_LEVEL)) >> 7) / float(MAX_VOLUME_LEVEL)

func _bank(bank_id: int) -> SoundBankSetup:
	if not _banks.has(bank_id):
		var loaded: SoundBankSetup = null
		if _loader.is_valid():
			loaded = _loader.call(bank_id)
		if loaded == null:
			loaded = SoundBankSetup.new()
			loaded.error = "Sound bank %d could not be loaded" % bank_id
		_banks[bank_id] = loaded
	return _banks[bank_id]
