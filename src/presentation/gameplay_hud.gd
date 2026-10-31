class_name GameplayHud
extends Control
## Source-style single-player HUD drawn exclusively from committed simulation snapshots.

const CANVAS: Vector2 = Vector2(640, 480)
## Score_library slots of the hop, checkpoint and gold frog awards.
const SCORE_SUPER_HOP: int = 1
const SCORE_ROLL: int = 3
const SCORE_CHECKPOINT: int = 9
const SCORE_GOLD_FROG: int = 10
var assets: GameplayHudAssets
var _state: GameplayState
var _tick: int = 0
var _gold_tick: int = -1
var _help_tick: int = -100
var _help_text: String = ""
var _help_seen: Dictionary[String, bool] = {}
var _rewards: Array[RewardDefinition] = []
var _panels: GameplayHudInk
var _letters: GameplayHudInk
var _score_popups: ScorePopupView

## Releases the previous level's display values and decoded UI textures.
func clear() -> void:
	_state = null
	assets = null
	_rewards.clear()
	_help_seen.clear()
	_help_text = ""
	_gold_tick = -1
	if _score_popups != null:
		_score_popups.release()
	if _panels != null:
		_panels.hide()
		_letters.hide()
		_letters.font_texture = null
		_letters.glyphs.clear()
	queue_redraw()

## Resolves retail sprites; a missing dependency prevents a partially drawn HUD.
func configure(data: AssetCatalog) -> String:
	assets = GameplayHudAssets.from_data(data)
	if data != null and data.is_valid():
		var reward_setup: RewardSetup = RewardSetup.from_table(data.tables.scores())
		if not reward_setup.error.is_empty():
			return reward_setup.error
		_rewards = reward_setup.definitions
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()
	return assets.error

## Prepares the level's score sprite images; returns diagnostics for missing images.
func configure_effects(effects: EffectResources) -> String:
	return _popup_view().configure(effects)

## The score sprite layer drawn over the HUD.
func score_popups() -> ScorePopupView:
	return _popup_view()

## Copies committed display values without advancing any gameplay clock.
func present(state: GameplayState, tick: int, events: Array[TickEvent] = []) -> void:
	if _state == null or tick < _tick:
		_help_tick = -100
		_help_text = ""
		_help_seen.clear()
		_popup_view().clear()
	if _state != null and tick > _tick:
		_present_score_sprites(state, events)
	if _state != null and state.tongue.mode != TongueState.Mode.IDLE and _state.tongue.mode == TongueState.Mode.IDLE:
		_help("TONGUE", tick, false, true)
	for event: TickEvent in events:
		if event.kind == TickEvent.Kind.SUPER_HOP:
			_help("SUPERHOP", tick, false, true)
		elif event.kind == TickEvent.Kind.REWARD and event.reward_id >= 0 and event.reward_id < _rewards.size():
			var reward: RewardDefinition = _rewards[event.reward_id]
			if reward.flags & RewardDefinition.POWERUP:
				match reward.value:
					PowerupFlags.AUTO_HOP: _help("AUTO-HOP", tick, true, false)
					PowerupFlags.SUPER_TONGUE: _help("SUPER TONGUE", tick, true, false)
					PowerupFlags.QUICK_JUMP: _help("QUICK JUMP", tick, true, false)
					PowerupFlags.TIMER_SPEED: _help("LOSE TIME", tick, true, false)
					PowerupFlags.SUPER_LIGHT: _help("BRIGHTEN", tick, true, false)
	if _state == null or tick < _tick or not state.flow.gold_collected:
		_gold_tick = -1
	if state.flow.gold_collected and (_state == null or not _state.flow.gold_collected):
		_gold_tick = tick
	_state = state.copy(false)
	_tick = tick
	queue_redraw()

## Score_library slots AddFrogScore receives this tick: the tick's reward
## requests, the hop scores (SCORE_10 for a super jump, SCORE_50 for a quick
## jump or roll; SCORE_5 has no image), each newly collected checkpoint
## (SCORE_500) and the gold frog (SCORE_1000).
static func score_slots(before: GameplayState, after: GameplayState, events: Array[TickEvent]) -> PackedInt32Array:
	var slots := PackedInt32Array()
	for event: TickEvent in events:
		match event.kind:
			TickEvent.Kind.REWARD:
				slots.append(event.reward_id)
			TickEvent.Kind.SUPER_HOP:
				slots.append(SCORE_SUPER_HOP)
			TickEvent.Kind.QUICK_HOP, TickEvent.Kind.ROLL:
				slots.append(SCORE_ROLL)
	var collected_before: int = before.entity_environment.collected if before.entity_environment != null else 0
	var collected_after: int = after.entity_environment.collected if after.entity_environment != null else 0
	for checkpoint: int in 5:
		if collected_after & ~collected_before & (1 << checkpoint):
			slots.append(SCORE_CHECKPOINT)
	if after.flow.gold_collected and not before.flow.gold_collected:
		slots.append(SCORE_GOLD_FROG)
	return slots

func _present_score_sprites(state: GameplayState, events: Array[TickEvent]) -> void:
	var popups: ScorePopupView = _popup_view()
	if state.camera != null:
		var at := Vector3i(state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11])
		for slot: int in score_slots(_state, state, events):
			if popups.has_image(slot) and GameplayWorldView.in_front_of(state.camera, at):
				popups.spawn(slot, GameplayWorldView.canvas_point(state.camera, at))
	popups.step()

func _popup_view() -> ScorePopupView:
	if _score_popups == null:
		_score_popups = ScorePopupView.new()
		_score_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_score_popups)
	return _score_popups

## Source spare-life grouping: each large icon represents three spare lives.
static func life_icons(lives: int) -> Vector2i:
	var spare: int = clampi(lives - 1, 0, 10)
	if spare == 0:
		return Vector2i.ZERO
	return Vector2i(PlatformMath.divide(spare - 1, 3), (spare - 1) % 3 + 1)

## Deterministic gather/scatter positions, including the source delay boundary tick.
static func start_checkpoint_position(index: int, ticks: int) -> Vector2:
	var destination := Vector2(16 + index * 16, 436)
	var delay: int = (index + 1) * 5 + 1
	if ticks < LevelStartSequence.GATHER_FINISH:
		var origin := Vector2(240 + index * 40, 280)
		var steps: int = clampi(ticks - delay, 0, 30)
		var velocity := Vector2i(PlatformMath.divide(int(destination.x - origin.x) << 16, 30), PlatformMath.divide(int(destination.y - origin.y) << 16, 30))
		return Vector2((int(origin.x * 65536) + velocity.x * steps) >> 16, (int(origin.y * 65536) + velocity.y * steps) >> 16)
	return destination + Vector2(0, 2 * clampi(ticks - LevelStartSequence.GATHER_FINISH - delay, 0, 20))

func _draw() -> void:
	if _state == null or assets == null or not assets.error.is_empty():
		return
	var factor: float = minf(size.x / CANVAS.x, size.y / CANVAS.y)
	if factor <= 0.0:
		return
	if _panels == null:
		_panels = GameplayHudInk.new()
		_panels.configure(CanvasItemMaterial.BLEND_MODE_MIX)
		_panels.panels.assign([Rect2(555, 11, 74, 26), Rect2(260, 444, 120, 8)])
		add_child(_panels)
		_letters = GameplayHudInk.new()
		_letters.configure(CanvasItemMaterial.BLEND_MODE_MIX)
		add_child(_letters)
		move_child(_popup_view(), -1)
	for ink: GameplayHudInk in [_panels, _letters]:
		ink.show()
		ink.position = (size - CANVAS * factor) * 0.5
		ink.scale = Vector2.ONE * factor
		ink.queue_redraw()
	var popups: ScorePopupView = _popup_view()
	popups.position = (size - CANVAS * factor) * 0.5
	popups.scale = Vector2.ONE * factor
	_letters.font_texture = assets.textures.get("newfont")
	_letters.glyphs.clear()
	draw_set_transform((size - CANVAS * factor) * 0.5, 0.0, Vector2.ONE * factor)
	var flow: LevelFlowState = _state.flow
	_text("1 UP", Vector2(592, 16))
	_text("%8d" % flow.score, Vector2(560, 24))
	_timer(flow)
	_checkpoints(flow)
	var help_age: int = _tick - _help_tick
	if help_age >= 0 and help_age < 56:
		var brightness: float = float(help_age) / 16.0 if help_age < 16 else 1.0 if help_age < 40 else float(56 - help_age) / 16.0
		_text(_help_text, Vector2(320 - _help_text.length() * 4, 436), Color(brightness, brightness, brightness))
	var icons: Vector2i = life_icons(_state.frog.lives)
	var frame: int = PlatformMath.divide(_tick, 2) % 5 + 1
	for index: int in icons.x:
		_sprite("lives_bg%d" % frame, Vector2(624 - (index + 1) * 30, 420))
	for index: int in icons.y:
		_sprite("lifes%d" % frame, Vector2(624 - (index + 1) * 24, 438))
	if flow.gold_collected:
		var elapsed: int = clampi(_tick - _gold_tick + 1, 0, 30) if _gold_tick >= 0 else 30
		var height: int = (-20 * 65536 + PlatformMath.divide(456 << 16, 30) * elapsed) >> 16
		_sprite("babyfroggold_%d" % (PlatformMath.divide(_tick, 2) % 7), Vector2(96, height))
	draw_set_transform(Vector2.ZERO)

func _timer(flow: LevelFlowState) -> void:
	var width: int = PlatformMath.divide(118 * flow.remaining_time, 2250)
	if width != 0:
		var colour_step: int = PlatformMath.divide(192 * flow.remaining_time, 2250)
		var end := Color(float(224 - colour_step) / 255.0, float(32 + colour_step) / 255.0, 32.0 / 255.0)
		draw_polygon(PackedVector2Array([Vector2(261, 445), Vector2(261 + width, 445), Vector2(261 + width, 451), Vector2(261, 451)]), PackedColorArray([Color(224.0 / 255.0, 32.0 / 255.0, 32.0 / 255.0), end, end, Color(224.0 / 255.0, 32.0 / 255.0, 32.0 / 255.0)]))
	var seconds: int = clampi(PlatformMath.divide(flow.remaining_time + 29, 30), 0, 99)
	if flow.phase == LevelFlowState.Phase.START:
		if flow.start_hud_ticks >= LevelStartSequence.GATHER_FINISH:
			_digits(seconds, 2, "32x32_", Vector2(288, 410), 32)
			_sprite("opt_sec", Vector2(352, 426))
			if flow.start_phrase >= 0:
				_sprite(GameplayHudAssets.PHRASES[flow.start_phrase % 6], Vector2(325, 396))
	elif flow.phase != LevelFlowState.Phase.CHECKPOINT and seconds <= 10:
		var pulse := Color(float(flow.remaining_time % 30) * 3.0 / 128.0, 0, 0)
		_digits(seconds, 2, "32x32_", Vector2(288, 410), 32, pulse)
	elif flow.phase == LevelFlowState.Phase.CHECKPOINT and flow.bonus_stage in [2, 3]:
		var checkpoint_time: int = flow.checkpoint_times[flow.last_checkpoint] if flow.last_checkpoint >= 0 and flow.last_checkpoint < 5 else flow.elapsed_time
		_digits(clampi(PlatformMath.divide(checkpoint_time + 29, 30), 0, 99), 2, "med_", Vector2(320, 221), 16)
		_sprite("opt_sec", Vector2(352, 221))
		_sprite("bonus", Vector2(260, 248))
		_digits(flow.bonus_score, 5, "med_", Vector2(320, 246), 16)

func _checkpoints(flow: LevelFlowState) -> void:
	var frame: int = PlatformMath.divide(_tick, 2) % 7
	if flow.phase == LevelFlowState.Phase.START and flow.start_hud_ticks > 0:
		for index: int in 5:
			_sprite("babyfrog%d_%d" % [index + 1, frame], start_checkpoint_position(index, flow.start_hud_ticks))
		return
	var covered: int = _state.entity_environment.collected if _state.entity_environment != null else 0
	var slot: int = 0
	for index: int in 5:
		if not covered & (1 << index):
			continue
		var position_at := Vector2(16 + slot * 16, 436)
		if flow.phase == LevelFlowState.Phase.CHECKPOINT and index == flow.last_checkpoint:
			if flow.bonus_stage == 0:
				continue
			if flow.bonus_stage == 1:
				position_at = checkpoint_motion(Vector2i(250, -20), Vector2i(250, 215), flow.transition_ticks)
			elif flow.bonus_stage in [2, 3]:
				position_at = Vector2(250, 215)
			elif flow.bonus_stage == 4:
				position_at = checkpoint_motion(Vector2i(250, 215), Vector2i(position_at), flow.transition_ticks)
		_sprite("babyfrog%d_%d" % [index + 1, frame], position_at.floor())
		slot += 1

## Source checkpoint motion takes 31 updates with a velocity divided by 30.
static func checkpoint_motion(origin: Vector2i, destination: Vector2i, remaining: int) -> Vector2:
	var elapsed: int = clampi(31 - remaining, 0, 31)
	var velocity := Vector2i(PlatformMath.divide((destination.x - origin.x) << 16, 30), PlatformMath.divide((destination.y - origin.y) << 16, 30))
	return Vector2(((origin.x << 16) + velocity.x * elapsed) >> 16, ((origin.y << 16) + velocity.y * elapsed) >> 16)

func _sprite(name: String, at: Vector2, colour: Color = Color.WHITE) -> void:
	var texture: Texture2D = assets.textures.get(name)
	if texture != null:
		draw_texture_rect(texture, Rect2(at, assets.retail_size(name)), false, colour)

func _digits(value: int, count: int, prefix: String, at: Vector2, spacing: int, colour: Color = Color.WHITE) -> void:
	var digits: String = str(maxi(0, value)).pad_zeros(count).right(count)
	for index: int in digits.length():
		_sprite(prefix + digits[index], at + Vector2(index * spacing, 0), colour)

func _text(value: String, at: Vector2, colour: Color = Color.WHITE) -> void:
	if _letters == null or _letters.font_texture == null:
		return
	var texels: Vector2 = assets.texture_scale("newfont")
	for index: int in value.length():
		var code: int = value.unicode_at(index) - 32
		if code >= 0 and code < 96:
			var cell := Vector2((code % 32) * 8, PlatformMath.divide(code, 32) * 8)
			_letters.glyph(Rect2(at + Vector2(index * 8, 0), Vector2(8, 8)), Rect2(cell * texels, Vector2(8, 8) * texels), colour)

func _help(message: String, tick: int, overwrite: bool, once: bool) -> void:
	if _help_seen.has(message) or (not overwrite and tick - _help_tick < 56):
		return
	_help_text = message
	_help_tick = tick
	if once:
		_help_seen[message] = true
