# Terrain movement source contract

Frozen `FROG.C`, `COLLIDE.C` and `froguser.C` govern behavior. GRID shape follows
the [grid contract](grid.md). The run owns copied definitions, snapshots and
ordered command indices. Invalid commands and unsafe authored-storage accesses
fail without committing a partial tick.
Source order is control, movement callbacks, local modifier expiry, collision,
camera, animation scripts and pose. Optional [entity integration](entities.md#bounded-pop-reactions)
advances paths/transforms before this sequence and checks FORM reactions within
collision, after terrain early-return gates. Movement callback actions run as positional
update, matrix update, terrain reaction, then old-position update. `SetFrogUserMode`
runs setup before unconditionally assigning the requested user mode. A failed
slip setup's stationary assignment is therefore overwritten in actual source.
Transforms contain row-major 12-bit integer rotation and whole-unit translation.
`UpdateFrogMatrix` computes terrain facing from average normal and cross products;
freefall preserves the existing rotation. It does not replace cached translation.
Entity transforms and croak scaling are separate source branches.
Local quick/auto/tongue timers are unsigned16. A nonzero timer decrements to zero;
its flag clears on the following modifier call. Quick and auto fixture powers
must supply their remaining timers explicitly. Pickup application and global
timer-speed mutation belong to game flow. Start timer is explicit external context,
not an invented countdown inside the terrain run. `RunStart.start_mode` selects
stationary components, fast/play reset camera wait, or single-start bounce.
`TickCommand.start_timer_context` supplies the game loop's current timer value;
`start_sequence_complete` supplies HUD completion and enters camera wait. The
host must supply that completion; the port does not substitute elapsed ticks for
the source HUD script. Completion commands outside bounce/rest are rejected.

## Reachability and comparison gates

| Source callback or branch | Independent actual-C facts | Godot gate | Scope |
|---|---|---|---|
| Ordinary/super/quick/auto JumpFrog; buffering | terrain_components, terrain_d1 | test_terrain_run | Terrain |
| Landing, stun, deferred death, fade/theme height | terrain_collision | test_terrain_run supported terminal prefix | Terrain |
| Positive odd dimensions; source centred-base hop | grid_odd, terrain_odd | test_grid_queries, test_terrain_specials | Terrain; world-bitmask quirk preserved |
| Map-specific freefall animation, dying velocity, VOL death request and camera-wait collision guard | terrain_map_branches | test_terrain_specials | Terrain selection; effect factories excluded |
| Extreme signed16 normals and signed32 world macros | grid_width | test_grid_queries | Terrain; only macros observed outside grid |
| Terrain UpdateFrogMatrix | terrain_matrix | test_terrain_matrix | Terrain; entity/scaling excluded |
| Grid and simple grid slip setup/movement; signed slope threshold | terrain_special, terrain_slope | test_terrain_specials | Terrain |
| Bounce setup/movement; cliff roll/null fall | terrain_roll | test_terrain_specials | Terrain |
| Freeform setup/movement, held steering and silent tongue | terrain_freeform, terrain_steering; explicit tongue tests | test_terrain_specials | Terrain; entity interaction excluded |
| Local modifier expiry | terrain_modifiers | test_terrain_specials | Terrain; global timer-speed excluded |
| BOUNCY_COBWEB entered by authored N/E wall flags or cliff boundary | terrain_wall | test_terrain_specials | Terrain |
| Single-start bounce/rest and fast-start wait | terrain_startup; explicit completion test | test_terrain_specials, test_terrain_run | Terrain callbacks; HUD completion supplied by caller |
| Combined reaction flags and first-match precedence | terrain_priority | test_terrain_specials | Terrain |
| Signed32 hop delta, wall numerator and freeform floor wrapping; forced failed-search pointer carry | terrain_narrow safe prefixes | test_terrain_specials | Terrain; out-of-global-storage pointers are diagnosed |
| Outward bounds adjustment | terrain_bounds supported prefix | test_terrain_specials | Terrain; final unbounded C lookup is diagnosed |
| Entity slipping, cobweb, thermal and throw | Entity fixture deferred | Not implemented | Entities/forms |
| Move-to-target/checkpoint callbacks | Checkpoint/game-flow fixture deferred | Not implemented | Game flow |

The callback fixtures isolate their declared transport boundaries. The
[collision oracle contract](../testing/terrain-collision-oracle.md) records effect factories,
request interception and omitted RNG work; a match does not establish full
engine effects or RNG parity.
Authored fade corners must fit signed16, death height signed32, flags unsigned32,
modifier timers unsigned16 and stack count/cliff bytes unsigned8. Ordered layer
spans must cover every square. Ignored flag data is retained, with unknown-bit
diagnostics rather than invented behavior. Reaction narrowing is source
unsigned16; obsolete ENTITY bits remain source identity only. CHECKPOINT has no
terrain reaction branch in the source.
The source's outward bounds-adjustment loop is preserved; its eventual unbounded
stack lookup is diagnosed before access. Outside-board fixture facts stop before
that undefined source access rather than claiming arbitrary C memory behavior.
`SourceRandom` records total draw count and ordered per-tick consumer names.
Transactional copies preserve both; each new tick clears only the diagnostic
list. Camera stun draws and animation idle selection share this stream. Omitted
effect factories never cause compensating draws.
Terrain dispatch modes are stationary0, jumping1, dying2, camera-wait3, stun6,
grid-slip258, bouncy-wall261, freeform-slip262, start-bounce265, start-rest266,
simple-slip267, bounce268 and cliff-roll269. Grid/simple use stationary control.
Freeform follows `FroguserSlippingLandNonGridControl`: a held direction steers;
with none held, a pressed tongue starts an idle tongue without the slurp sound.
Freeform never hops or super-hops. Bounce/wall/cliff/start have no ordinary hop
controller. The rows above cover failed setup's mode overwrite, slip-to-safe,
freeform-to-fall/death, wall-to-land, cliff-to-fall/death, bounce-to-reaction and
explicit start completion to camera-wait.
Remaining callback branches require another domain: ON_ENTITY/JUMP_FROM_ENTITY
matrix and movement, slipping-entity/cobweb/thermal/throw setup depend on
entities/forms. Tongue targets, croak lighting, checkpoint collection, HUD start
completion and global timer-speed mutation depend on entities and game flow. These are explicit
command/domain boundaries rather than omitted terrain dispatch modes.
The map identity used by `Game_map` is distinct from archive resource identity.
`LevelDefinition.map_index` supplies that scalar. SKY1 through SKY multiplayer
(indices 42 through 47) request FREEFALL instead of FALLING when delayed freefall animation
starts. A land jump that ends over no usable square enters freefall by clearing
the whole `FROG_LANDED_ON_ENTITY_CLEAR_MASK`, including `JUMP_FROM_COLLPRIM`,
so a frog that bounced off a collision primitive can still land on a FORM below
(the SKY3 squadron after the trigger balloon). CAVES3(index2) damps stationary dying velocity after positional addition:
each signed32 product by14 wraps before the arithmetic shift by4. VOL drowned
or flopped deaths request DROWN again and request fire particles and colour24,0,0;
the original death equate remains unchanged. Effect construction/rendering and
its possible random work remain outside these component facts.
The source census checks terrain dispatch and its global selectors in FROG.C,
froguser.C and COLLIDE.C. Multiplayer lifetime/setup branches, demo input guards,
entity transforms/terrain attachments, croak lighting/scaling, checkpoint/HUD
completion and global timer-speed are separately scoped above. The terrain
map selectors are covered explicitly rather than inferred from theme names.
JumpFrog writes only source target X/Z on terrain jumps; its stored target Y is
retained independently from `fr_y` (snapshot `target_y`). X/Z fixed displacement
subtraction wraps signed32 before division. The narrow fixture uses a declared
1x255 grid and stops before final stack lookup; no padded outside-grid record
supplies a fact. Forced hops still apply the ordinary authored height searches.
After both searches fail, C keeps the pointer immediately before that stack,
clears jump-to-land and proceeds. The port preserves that identity when it lies
inside global square storage and rejects an actual out-of-storage pointer.

The bounded integer census uses the compared WIN95 widths. Vector3i/Vector2i
operations supply signed32 position, velocity and displacement wrapping.
Grid corner sums (at most 131072), signed interpolation products (at most
16776960), byte cliff scaling (at most 16320) and normalized matrix products
(at most 3*4096*4096) fit signed32. Grid scaled-edge cross products are wider and
explicitly wrap before their shift. Normalization uses double precision and
nearest integer ties away from zero, matching VectorNormal; no float32 vector
intermediate is introduced. Hop Y deltas remain within authored jump thresholds;
wall rebound old-Y deltas can span 65535, so its shifted numerator wraps before
division. Triangle interpolation can round one unit below the lowest corner
(-32769); freeform floor conversion wraps signed32 before comparison.
Grid/cliff slip displacements wrap before division; freeform steering
and acceleration stay below the initial hop/slip velocity bound and then clamp
to 80 fixed units. Startup bounce's 400-unit drop bounds its doubled velocity.
Modifier counters remain validated unsigned16. Unsafe source stack/pointer
accesses and stalled cliff searches are diagnosed, without padded memory facts.
