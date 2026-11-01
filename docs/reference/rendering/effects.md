# Effects

Effects are presentation: every view reads committed `GameplayState`
snapshots and the tick's `TickEvent`s and feeds nothing back. Particle jitter
comes from a presentation-owned, deterministically seeded
`RandomNumberGenerator`; the port never reproduces the frozen generators'
shared `rand()` draws (see [simulation](../gameplay/simulation.md#effects-and-the-random-stream)).
Rules, constants and deliberate-break checks are in the
[effects specification](../../../tests/golden/specs/effects.md); textures,
generator records, splash lists and pop colours come from the player's data
through `EffectResources` on `MapSceneData.effects`.

## Data

- Particle generator records (`MR_PGEN_INIT`) are read from the supplied
  executable by `ExeParticleGenerators`, which locates the table by shape,
  with the frozen `PARTICLE.C` initialisers as the fallback when a build's
  records cannot be found. Retail differs from the vendored C in the exhaust
  scale and texture, the hilite fire lifetimes and scale, and one unnamed
  record; the port follows the executable.
- Effect images resolve from the executable first (generator texture words,
  splash animation lists, the score table), then FrogLord image names
  (`gen_shadow`, `tongue_tip`, `frog_shadow0..2`), then the fixed PC glow
  `bmp_pointers[1727]`. A level whose banks lack an image skips that effect
  with a diagnostic.
- Entity particle hilites (MOF hilite types 3–6: exhaust, cloud, smoke, fire)
  are resolved per entity model into `EntityDefinition.particle_hilites`.

## Depth and blend

The port keeps C's ordering-table offsets as depth-only vertex biases, two
view-depth units per slot, beside the table in [rendering](README.md#depth-ordering):

| Effect | C ordering | Port depth bias |
|---|---|---|
| Frog and entity shadows | `otz − 4` (`SHADOW_OT_OFFSET`) | 8 nearer |
| Slide, bubble, fire and smoke particles; splash ripple | `otz − 0x10` | 32 nearer |
| Exhaust and cloud | `otz + 0x10` | 32 further |
| Gold-frog glow | `otz − 0x30` | 96 nearer |
| Death pop ring, poly-piece pops | fixed OT 2 (the front) | drawn in front |

PC blend rates live in texture-page bits 8–9. The engine follows retail PC
(KEY_FACTS 362–364, 378, 388, 493): the hop trail is additive, the tongue
averages, exhaust, smoke and fire use `im_frog_smoke1`, the pickup and
gold-frog glows use the grey mask 1727, and the gold glow is (255, 255, 16).

## Frog effects (P11b)

- **Shadow** (`EFFECTS.C:327-583, 862-945`; tables `FROG.C:136-179`): a
  0x303030 textured quad whose corners take the grid height, with the offset
  table and `frog_shadow0..2` chosen by jump phase, rotated by the matrix's
  world-Y quadrant, split into two quads at a grid line, hidden while
  `FrogState.shadow_hidden`, attached, dying, jumping without the land flag,
  at a collected checkpoint or after level completion.
- **Hop trail** (`EFFECTS.C:585-644, 961-1056`): six sections of two
  additive triangles between the frog's ±0x40 edge offsets, one new pair per
  tick, timer 26 for a super hop and 16 for a hop, colour rising to 0x606060
  then falling by 0x080808 per tick, each section 0x101010 darker.
- **Slide, bubble and fire particles** (`PARTICLE.C`): camera-plane
  billboards from the generator record's counts, lifetimes, gravity and
  scale. Slide follows `SLIDE_PARTICLES_REQUEST`/`STOP`; bubbles start with a
  drowning splash and live 90 ticks; fire follows the Volcano death request
  until reset; all die with the frog's death, reset and checkpoint.
- **Death pop ring** (`PARTICLE.C:908-1072`): eight additive quads between
  two octagons around the projected frog origin for 30 ticks, red outside and
  the player colour inside, angle from the committed `game_timer`.
- **Splash** (`COLLIDE.C:43-65`): an XZ-plane quad at the `SPLASH` origin,
  eight times the image size, `ripple_tim1..6` every two ticks, three fades,
  lit by the map's lights like a 3D sprite, removed on update 23.
- **Tints**: the committed `FrogState.colour_scale` and `custom_ambient`
  apply through `AnimatedModelInstance.set_source_lighting` with the map's
  lights, scaling colours and replacing the ambient as the C does;
  `set_tint` serves only where no map lights exist (sandbox, mapless models).
- **Score popups** (`score.C:107-226`): the score image rises 0x8000 per
  tick on the HUD canvas from the projected frog origin, fading up for three
  updates and down to its removal on update 45. The HUD derives the
  `Score_library` slot from the tick's `REWARD` events (every scoring path
  emits one, including tongue pickups and the fly and firefly callbacks),
  the hop events, newly collected checkpoints and the gold frog; C places a
  baby frog's 500 at the frog's own origin, which the port approximates with
  the frog origin for every popup.
- **Particle fields**: one frog field at a time, as C's `fr_particle_api_item`;
  slide and fire fields die with the frog's death, reset (`LEVEL_TRANSITION`
  to play) and checkpoint collection, bubbles finish on their own. The field
  random stream is seeded from the tick and slot, so captures repeat.

## Entity effects (P11c)

- **Entity shadows** (`ent_des.c:33-39, 255-533, 1674-1799`): live Desert
  falling rocks and tumbleweeds with the committed `shadow_visible` draw the
  ±0x70 `im_gen_shadow` square through the frog's shadow view (these and
  the frog's blob shadow draw only when `frogger/rendering/effect_shadows` or
  `--effect-shadows=` is `retail`; by default the real shadows replace them,
  [shadows](lighting.md#shadows)); rocks keep
  `NO_ROTATION`, a tumbleweed inside the grid border rotates with its
  matrix. Rolling rocks cast none, as in C.
- **Gold-frog glow** (`PARTICLE.C:2607-2724`): a camera-plane quad of the
  grey mask 1727 in (255, 255, 16) at the entity origin of the GEN gold frog,
  the ORG gold baby frog and the Jungle statue (`op_id` 8), pulsing with
  `GlowPulse` (shared with the pickup glow), blended at the image's page
  rate, 96 nearer, shown while the model is shown and killed with the pop.
- **Entity splashes** (`scripter.c:1411-1453`, `ent_swp.c:1178-1218`):
  every `SPRITE` event (turtles, hippos, one per ORG offset) and `SPLASH`
  event (rats) opens a splash at the owning entity's live matrix plus the
  event offset; the quad stays in the world XZ plane rather than rotating
  with the entity.
- **Exhaust, cloud, smoke and fire** (`ENTITY.C:1766-1953`, `PARTICLE.C`):
  one particle field per resolved hilite, created with the live generation
  and dropped with it at once (C's `DESTROY_BY_DISPLAY` stops the dust and
  fire display immediately), stepped with
  the entity rotation composed with the part's animation rotation at the
  partcel-0 vertex, `moving` from the translation change. Exhaust and cloud
  share the exhaust record (grey `life<<4` clamped by the committed colour
  scale, 32 further), smoke uses the dust record with its `bison1..6`
  frames stepped once per tick at additive rate (32 nearer), fire uses the
  hilite fire record (user from the record's maximum life plus `r & 0x1f`,
  colour (255, user<<1, 0), 32 nearer, never culled in front).
- **Croak throat**: part 15 (`THROAT` in `gen_frog.h`) shows while the
  committed croak mode is active, scaled by `croak_scale / 4096`.
- **Pops not reached**: the ORG gold baby frog is carried like a pink frog
  rather than collected and popped, and the Jungle outro stone frog belongs
  to the ending sequence (P16).

## Poly-piece pops

`ModelPolyPieces` splits part 0 of a model into one piece per drawn polygon
(F/FT/G/GT triangles and quads; E and GE kinds are counted and skipped, as
`RenderPolyPiecePop` never draws them) with C's centroid rule
(`CreateMeshPolyPieces`, `EFFECTS.C:1915-2003`: a triangle's corner sum
divided by three truncating toward zero, a quad's shifted right by two,
narrowed to signed 16). `PolyPiecePopState` owns the 32-tick timer, the
rotation and its (8, 0xC, 0x10) acceleration, and the 16.16 piece motion
under `WORLD_GRAVITY << 1`; the render matrix is `scale × RotMatrix(rotation)
× lwtrans`, with `RotMatrix` taken as `Rx · Ry · Rz` (Z applied first),
which the frozen source does not define and the reference engine settled
against the PlayStation SDK. Pieces are unlit, two-sided and drawn with the
entity's current matrix, as `pp_lwtrans` points at the live entity.

## Limitations

- Particle positions, velocities and counts are approximate by design; C's
  render-rate state (fire user value, dust frame step, pop ring angle) is
  stepped once per committed tick.
- Pop pieces of E/GE polygon types are skipped, as C never draws them.
- The multiplayer frog pop, front-end and high-score shadows and lens flare
  are outside scope; the PSX-only pickup explosion draws nothing on PC.
