class_name SoundVoiceView
extends Node
## Plays the logical model's 24 source voices from committed snapshots, one player and panned bus per voice.
##
## Each committed tick is compared with the one before it: a voice slot whose
## identifier changes starts its sample at [method AudioResources.pitch_scale]
## of its note, fine tune and bend; a pitch change on the same identifier is a
## bend; a killed voice stops at once, and a looping stream stops when its
## voice is no longer playing. One-shot samples that end on their own are left
## to finish. Fixed voices play at the sample's maximum volume; voices linked
## to a moving owner follow [method AudioResources.moving_volumes] about the
## frog every tick. Left and right levels become one player volume and an
## [AudioEffectPanner] setting on the voice's bus, which feeds [constant BUS].
## The view reads committed state only and never changes it. Pages shown outside
## a tick play their generic sounds on [member page_player], a spare player
## beside the voice slots ([method play_page_sound]).

## Source voice slots in [LogicalSoundState].
const VOICES: int = 24
## Bus every voice bus sends to.
const BUS: StringName = &"Sfx"
## Name prefix of the per-voice buses.
const VOICE_BUS_PREFIX: String = "Sfx voice "
## Player volume used for silence.
const SILENT_DB: float = -80.0

## One player per source voice slot.
var players: Array[AudioStreamPlayer] = []
## The spare player [method play_page_sound] uses, outside the voice slots.
var page_player: AudioStreamPlayer
## Effect volume (0..127) applied to every requested level.
var effect_volume: int = AudioResources.DEFAULT_EFFECT_VOLUME
var _resources: AudioResources = null
var _panners: Array[AudioEffectPanner] = []
var _identifiers := PackedInt32Array()
var _pitches := PackedInt32Array()
var _tick: int = -1

func _init() -> void:
	_identifiers.resize(VOICES)
	_pitches.resize(VOICES)
	for slot: int in VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % slot
		players.append(player)
		add_child(player)
		_panners.append(null)
	page_player = AudioStreamPlayer.new()
	page_player.name = "PageSound"
	add_child(page_player)

func _ready() -> void:
	ensure_bus(BUS, &"Master")
	page_player.bus = BUS
	for slot: int in VOICES:
		var bus_name := StringName(VOICE_BUS_PREFIX + str(slot))
		var index: int = ensure_bus(bus_name, BUS)
		if AudioServer.get_bus_effect_count(index) == 0:
			AudioServer.add_bus_effect(index, AudioEffectPanner.new())
		_panners[slot] = AudioServer.get_bus_effect(index, 0) as AudioEffectPanner
		players[slot].bus = bus_name

func _exit_tree() -> void:
	collapse()

## Returns the index of the bus called [param bus_name], adding it with [param send] when missing.
static func ensure_bus(bus_name: StringName, send: StringName) -> int:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, send)
	return index

## Uses [param resources] for later voices after stopping every playing one; null silences effects.
func configure(resources: AudioResources) -> void:
	collapse()
	_resources = resources

## Builds the streams of [param sound_ids] now so the first play of each needs no bank load.
func preload_sounds(sound_ids: PackedInt32Array) -> void:
	if _resources == null:
		return
	for sound_id: int in sound_ids:
		_resources.stream_for(sound_id)

## Starts, bends, pans and stops players from the voices of [param after] against [param before]; a repeated tick does nothing.
func accept_state(before: GameplayState, after: GameplayState) -> void:
	if after == null or after.tick_index == _tick:
		return
	_tick = after.tick_index
	if after.sound == null or _resources == null:
		_stop_all()
		return
	var previous: Array[LogicalSoundVoice] = []
	if before != null and before.sound != null:
		previous = before.sound.voices
	for slot: int in mini(VOICES, after.sound.voices.size()):
		var voice: LogicalSoundVoice = after.sound.voices[slot]
		var old: LogicalSoundVoice = previous[slot] if slot < previous.size() else null
		var live: bool = voice.sample != null and not voice.killed
		if live and voice.playing and (old == null or old.sample == null or old.identifier != voice.identifier):
			_start(slot, voice, after)
		elif live and _identifiers[slot] == voice.identifier and _identifiers[slot] != 0:
			if not voice.playing and _loops(slot):
				_stop(slot)
				continue
			if voice.pitch != _pitches[slot]:
				_pitches[slot] = voice.pitch
				players[slot].pitch_scale = AudioResources.pitch_scale(voice.note, voice.fine, voice.pitch)
			if voice.moving_owner >= 0:
				_apply_volumes(slot, _volumes(voice, after))
		elif _identifiers[slot] != 0:
			if voice.killed or _loops(slot) or (voice.sample != null and voice.identifier != _identifiers[slot]):
				_stop(slot)
			else:
				_identifiers[slot] = 0

## Plays generic sound [param sound_id] once on [member page_player], outside any tick: the
## sample's stream at the pitch of its note with no offset and its fixed volume mixed with
## [member effect_volume], centred; an id without a definition or stream does nothing.
func play_page_sound(sound_id: int) -> void:
	if _resources == null:
		return
	var definition: LogicalSoundDefinition = _resources.definition_for(sound_id)
	if definition == null:
		return
	var stream: AudioStreamWAV = _resources.stream_for(sound_id)
	if stream == null:
		return
	page_player.stop()
	page_player.stream_paused = false
	page_player.stream = stream
	page_player.pitch_scale = AudioResources.pitch_scale(definition.note, 0)
	page_player.volume_db = mix(AudioResources.fixed_volumes(definition), effect_volume).x
	if page_player.is_inside_tree():
		page_player.play()

## Stops every voice and the page sound and forgets the last tick, for reset, rollback and detach.
func collapse() -> void:
	_stop_all()
	page_player.stop()
	page_player.stream_paused = false
	_tick = -1

## Holds or resumes every player, the page sound's included, where it is.
func pause(paused: bool) -> void:
	for player: AudioStreamPlayer in players:
		player.stream_paused = paused
	page_player.stream_paused = paused

## The identifier the player of [param slot] was started for, or 0 when none is tracked.
func identifier(slot: int) -> int:
	return _identifiers[slot]

## The pan (-1 left to 1 right) on the bus of [param slot].
func pan(slot: int) -> float:
	return _panners[slot].pan if _panners[slot] != null else 0.0

## Player volume and pan reproducing requested left and right levels (0..127) on a mono sample.
##
## The panner sends a duplicated mono signal as [code]s * (1 - pan)[/code]
## left and [code]s * (1 + pan)[/code] right, so the player's amplitude is
## the mean of both gains and the pan their normalised difference.
static func mix(volumes: Vector2i, effect_volume_level: int = AudioResources.DEFAULT_EFFECT_VOLUME) -> Vector2:
	var left: float = AudioResources.gain(volumes.x, effect_volume_level)
	var right: float = AudioResources.gain(volumes.y, effect_volume_level)
	var total: float = left + right
	if total <= 0.0:
		return Vector2(SILENT_DB, 0.0)
	return Vector2(linear_to_db(total * 0.5), (right - left) / total)

func _start(slot: int, voice: LogicalSoundVoice, state: GameplayState) -> void:
	var player: AudioStreamPlayer = players[slot]
	player.stop()
	_identifiers[slot] = voice.identifier
	_pitches[slot] = voice.pitch
	var stream: AudioStreamWAV = _resources.stream_for(voice.sample.sound_id)
	player.stream = stream
	if stream == null:
		return
	player.pitch_scale = AudioResources.pitch_scale(voice.note, voice.fine, voice.pitch)
	_apply_volumes(slot, _volumes(voice, state))
	if player.is_inside_tree():
		player.play()

func _volumes(voice: LogicalSoundVoice, state: GameplayState) -> Vector2i:
	if voice.moving_owner >= 0:
		var moving: LogicalMovingSound = state.sound.moving_for(voice.moving_owner)
		if moving != null:
			return AudioResources.moving_volumes(voice.sample, moving, state.sound.listener, state.frog.matrix12)
	return AudioResources.fixed_volumes(voice.sample)

func _apply_volumes(slot: int, volumes: Vector2i) -> void:
	var mixed: Vector2 = mix(volumes, effect_volume)
	players[slot].volume_db = mixed.x
	if _panners[slot] != null:
		_panners[slot].pan = mixed.y

func _loops(slot: int) -> bool:
	var stream: AudioStreamWAV = players[slot].stream as AudioStreamWAV
	return stream != null and stream.loop_mode != AudioStreamWAV.LOOP_DISABLED

func _stop(slot: int) -> void:
	players[slot].stop()
	players[slot].stream_paused = false
	_identifiers[slot] = 0
	_pitches[slot] = 0

func _stop_all() -> void:
	for slot: int in VOICES:
		_stop(slot)
