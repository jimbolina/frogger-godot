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
