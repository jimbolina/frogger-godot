extends GutTest
## Source-name resolution is centralized and cannot enable unsupported execution.

func test_known_capabilities_and_unknown_fallback() -> void:
	var turtle: EntityBehavior = EntityBehaviorCatalog.resolve("SUB_TURTLE")
	assert_eq(turtle.kind, EntityBehavior.Kind.TURTLE)
	assert_eq(turtle.layout, EntityBehavior.Layout.PATH)
	assert_eq(turtle.payload_offset, 12)
	assert_eq(turtle.payload_register_count, 3)
	assert_true(turtle.group_moving)
	assert_false(turtle.immortal)
	var baby: EntityBehavior = EntityBehaviorCatalog.resolve("ORG_BABY_FROG")
	assert_true(baby.immortal)
	assert_true(baby.one_shot)
	assert_false(baby.has_custom_update())
	assert_false(baby.has_form_contact())
	baby.execution = EntityBehavior.Execution.CONTACT
	assert_true(baby.has_custom_update())
	assert_true(baby.has_form_contact())
	assert_false(EntityBehaviorCatalog.resolve("ORG_BABY_FROG").has_form_contact())
	var unknown: EntityBehavior = EntityBehaviorCatalog.resolve("NEW_MOD_CODE")
	assert_eq(unknown.kind, EntityBehavior.Kind.UNKNOWN)
	assert_eq(unknown.layout, EntityBehavior.Layout.NONE)
	assert_false(unknown.has_custom_update())
	assert_false(unknown.has_form_contact())

func test_suburbia_reuses_moving_and_matrix_capabilities() -> void:
	var moving: EntityBehavior = EntityBehaviorCatalog.resolve("MOVING_TONGUEABLE")
	assert_eq(moving.kind, EntityBehavior.Kind.PATH_FOLLOWER)
	assert_true(moving.tongueable)
	assert_true(moving.group_moving)
	assert_false(moving.immortal)
	var dynamic: EntityBehavior = EntityBehaviorCatalog.resolve("DYNAMIC")
	assert_eq(dynamic.kind, EntityBehavior.Kind.STATIC)
	assert_eq(dynamic.layout, EntityBehavior.Layout.MATRIX)
	assert_true(dynamic.immortal)
	assert_true(dynamic.group_moving)
	assert_false(dynamic.has_custom_update())
	var dog: EntityBehavior = EntityBehaviorCatalog.resolve("SUB_DOG")
	assert_eq(dog.layout, EntityBehavior.Layout.PATH)
	assert_false(dog.immortal)
	dog.execution = EntityBehavior.Execution.CONTACT
	assert_true(dog.has_custom_update())
	assert_true(dog.has_form_contact())

func test_volcano_names_have_source_lifetimes_and_typed_callback_mapping() -> void:
	for name: String in ["MOVING_PLATFORM", "VOL_COLOUR_SWITCH", "VOL_FALLING_PLATFORM"]:
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve(name)
		assert_true(behavior.immortal, name)
		assert_true(behavior.group_moving, name)
		assert_eq(behavior.layout, EntityBehavior.Layout.PATH if name == "MOVING_PLATFORM" else EntityBehavior.Layout.MATRIX)
		assert_false(behavior.has_custom_update())
		behavior.execution = EntityBehavior.Execution.CONTACT
		assert_true(behavior.has_custom_update())
		assert_true(behavior.has_form_contact())
	assert_eq(EntityBehaviorCatalog.resolve("TRIGGER").kind, EntityBehavior.Kind.TRIGGER)
	assert_eq(FormCallbackCatalog.resolve("pc-retail-v3.0e", 0x41d7e0), FormCallback.Kind.VOL_COLOUR_SWITCH)
	assert_eq(FormCallbackCatalog.resolve("unknown", 0x41d7e0), FormCallback.Kind.UNKNOWN)

func test_cave_names_follow_source_entity_book_capabilities() -> void:
	var light: EntityBehavior = EntityBehaviorCatalog.resolve("CAV_FROGGER_LIGHT")
	assert_eq(light.kind, EntityBehavior.Kind.CAVE_LIGHT)
	assert_eq(light.layout, EntityBehavior.Layout.MATRIX)
	assert_true(light.immortal)
	assert_true(light.group_moving)
	assert_false(light.tongueable)
	var firefly: EntityBehavior = EntityBehaviorCatalog.resolve("FIREFLY")
	assert_eq(firefly.kind, EntityBehavior.Kind.FIREFLY)
	assert_eq(firefly.layout, EntityBehavior.Layout.PATH)
	assert_true(firefly.tongueable)
	assert_true(firefly.group_moving)
	assert_false(firefly.immortal)
	var fat: EntityBehavior = EntityBehaviorCatalog.resolve("CAV_FAT_FIRE_FLY")
	assert_eq(fat.kind, EntityBehavior.Kind.FAT_FIRE_FLY)
	assert_eq(fat.layout, EntityBehavior.Layout.MATRIX)
	assert_true(fat.tongueable)
	assert_false(fat.immortal)
	assert_false(fat.group_moving)
	assert_eq(FormCallbackCatalog.resolve("pc-retail-v3.0e", 0x43d060, true), FormCallback.Kind.CAV_FIREFLY_SCORE)
	assert_eq(FormCallbackCatalog.resolve("pc-retail-v3.0e", 0x43cf20), FormCallback.Kind.UNKNOWN)

func test_desert_names_follow_source_entity_book_capabilities() -> void:
	var expected: Dictionary[String, Array] = {
		"DES_FALLING_ROCK": [EntityBehavior.Kind.DES_FALLING_ROCK, EntityBehavior.Layout.MATRIX, true],
		"DES_ROLLING_ROCK": [EntityBehavior.Kind.DES_ROLLING_ROCK, EntityBehavior.Layout.PATH, true],
		"DES_TUMBLE_WEED": [EntityBehavior.Kind.DES_TUMBLE_WEED, EntityBehavior.Layout.PATH, false],
		"DES_SNAKE": [EntityBehavior.Kind.DES_SNAKE, EntityBehavior.Layout.PATH, false],
		"DES_VULTURE": [EntityBehavior.Kind.DES_VULTURE, EntityBehavior.Layout.PATH, false],
		"DES_CROC_HEAD": [EntityBehavior.Kind.DES_CROC_HEAD, EntityBehavior.Layout.MATRIX, true],
		"DES_CRACK": [EntityBehavior.Kind.DES_CRACK, EntityBehavior.Layout.MATRIX, true],
	}
	for name: String in expected:
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve(name)
		var facts: Array = expected[name]
		var kind: EntityBehavior.Kind = facts[0]
		var layout: EntityBehavior.Layout = facts[1]
		var immortal: bool = facts[2]
		assert_eq(behavior.kind, kind, name)
		assert_eq(behavior.layout, layout, name)
		assert_eq(behavior.immortal, immortal, name)
		assert_true(behavior.group_moving, name)
		assert_false(behavior.tongueable, name)
		assert_false(behavior.one_shot, name)
		assert_true(behavior.has_form_contact(), name)
		assert_false(behavior.has_custom_update(), name)
		behavior.execution = EntityBehavior.Execution.UPDATE
		assert_true(behavior.has_custom_update(), name)
	assert_eq(EntityBehaviorCatalog.resolve("DES_THERMAL").kind, EntityBehavior.Kind.UNKNOWN)
	assert_ne(EntityBehaviorCatalog.resolve("DES_CROC_HEAD").kind, EntityBehaviorCatalog.resolve("ORG_CROC_HEAD").kind)

func test_jungle_names_follow_source_entity_book_capabilities() -> void:
	var expected: Dictionary[String, Array] = {
		"JUN_PLANT": [EntityBehavior.Kind.JUN_PLANT, EntityBehavior.Layout.MATRIX, true, true, false],
		"JUN_ROPE_BRIDGE": [EntityBehavior.Kind.JUN_ROPE_BRIDGE, EntityBehavior.Layout.MATRIX, true, true, false],
		"JUN_HIPPO": [EntityBehavior.Kind.JUN_HIPPO, EntityBehavior.Layout.PATH, false, true, false],
		"JUN_SCORPION": [EntityBehavior.Kind.JUN_SCORPION, EntityBehavior.Layout.PATH, false, true, false],
		"JUN_BOUNCY_MUSHROOM": [EntityBehavior.Kind.JUN_BOUNCY_MUSHROOM, EntityBehavior.Layout.MATRIX, false, false, true],
		"JUN_OUTRO_DOOR": [EntityBehavior.Kind.JUN_OUTRO_DOOR, EntityBehavior.Layout.MATRIX, true, true, false],
		"JUN_OUTRO": [EntityBehavior.Kind.JUN_OUTRO, EntityBehavior.Layout.MATRIX, true, true, false],
		"JUN_PLINTH": [EntityBehavior.Kind.JUN_PLINTH, EntityBehavior.Layout.MATRIX, true, true, false],
		"JUN_GOLD_FROG": [EntityBehavior.Kind.JUN_GOLD_FROG, EntityBehavior.Layout.MATRIX, true, true, false],
		"JUN_STONE_FROG": [EntityBehavior.Kind.JUN_STONE_FROG, EntityBehavior.Layout.MATRIX, true, true, false],
	}
	for name: String in expected:
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve(name)
		var facts: Array = expected[name]
		var kind: EntityBehavior.Kind = facts[0]
		var layout: EntityBehavior.Layout = facts[1]
		assert_eq(behavior.kind, kind, name)
		assert_eq(behavior.layout, layout, name)
		var immortal: bool = facts[2]
		var group_moving: bool = facts[3]
		var one_shot: bool = facts[4]
		assert_eq(behavior.immortal, immortal, name)
		assert_eq(behavior.group_moving, group_moving, name)
		assert_eq(behavior.one_shot, one_shot, name)
		assert_false(behavior.tongueable, name)
		assert_true(behavior.has_form_contact(), name)
		behavior.execution = EntityBehavior.Execution.UPDATE
		assert_eq(behavior.has_custom_update(), layout == EntityBehavior.Layout.MATRIX, name)
	var hippo: EntityBehavior = EntityBehaviorCatalog.resolve("JUN_HIPPO")
	assert_eq([hippo.payload_offset, hippo.payload_register_count], [12, 3])
	assert_eq(EntityBehaviorCatalog.resolve("JUN_SCORPION").payload_register_count, 0)
	for name: String in ["JUN_STATUE", "JUN_OUTRO_STATUE", "JUN_FLOATINGTREES", "JUN_CRACK"]:
		assert_eq(EntityBehaviorCatalog.resolve(name).kind, EntityBehavior.Kind.UNKNOWN, name)
