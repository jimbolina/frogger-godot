extends GutTest
## Typed notifications preserve external trace spelling without consumer parsing.

func test_parameterized_events_and_entity_scope() -> void:
	var sound: TickEvent = TickEvent.sound(19).for_entity(2)
	assert_eq(sound.kind, TickEvent.Kind.SOUND)
	assert_eq(sound.entity_index, 2)
	assert_eq(sound.sound_id, 19)
	assert_eq(sound.to_trace_line(), "entity:2:sound:19:0:0:0")
	assert_eq(TickEvent.moving_sound(27, 768, 1536).to_trace_line(), "moving:27:768:1536")
	assert_eq(TickEvent.sprite(Vector3i(0, -64, -256), Vector2i(1, -16)).to_trace_line(), "sprite:0:-64:-256:1:-16")
	var created: TickEvent = TickEvent.lifecycle(TickEvent.Kind.CREATE, 9, 2)
	assert_eq(created.generation, 2)
	assert_eq(created.to_trace_line(), "create:9:2")
	assert_eq(TickEvent.lifecycle(TickEvent.Kind.DESTROY, 9, 2).to_trace_line(), "destroy:9:2")
	assert_eq(TickEvent.death_animation(8).to_trace_line(), "death_animation_8")

func test_outbox_copies_detach_events_and_preserve_order() -> void:
	var events: Array[TickEvent] = [TickEvent.make(TickEvent.Kind.HOP), TickEvent.sound(13)]
	var detached: Array[TickEvent] = TickEvent.copy_all(events)
	events[1].sound_id = 99
	events.reverse()
	assert_eq(TickEvent.trace_lines(detached), ["hop", "sound:13:0:0:0"])
	detached[1].sound_id = 14
	assert_eq(events[0].sound_id, 99)
