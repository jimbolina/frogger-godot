# P6 — Map parsing, rendering and camera

Status: planning brief, not a completed implementation plan. No P6 code has
been started. The [roadmap](../PORTING.md) establishes the phase boundary;
the next session should survey the data and reference behavior before
proposing the detailed implementation and acceptance checklist.

## Established scope

- Decode PC map data using FrogLord's format definitions and independent Python facts.
- Render map geometry and apply map lighting; establish camera placement and projection
  against the frozen C engine's map pictures.
- Check texture remaps, pixel UV offsets and seams under nearest/linear filtering.
- Load a real FrogLord-saved map from a small edit as the first compatibility check.
- Keep grid movement, collision, deaths and gameplay camera behavior in P7;
  entity behavior and the first playable level remain P8.

## Planning checklist

- [ ] Survey retail map variants, sections, flags, bounds and dependencies.
- [ ] Trace FrogLord map saving and the C loading/rendering/camera behavior.
- [ ] Inventory reusable readers, texture lookup and model placement interfaces.
- [ ] Define malformed-input tests, independent golden families and deliberate-break checks.
- [ ] Choose representative maps, reference capture setup and comparison tolerances.
- [ ] Resolve projection calibration and define map-lighting/texture-seam checks.
- [ ] Measure a representative large-map build before choosing conversion/cache strategy.
- [ ] Confirm the owner-supplied mod folder and define its load checks.
- [ ] Turn this brief into the detailed scope, delivery steps and phase acceptance plan.

## Inputs and constraints

The owner must provide all three saved files: `modded_FROGGER.EXE`,
`modded_FROGPSX.MWD`, `modded_FROGPSX.MWI`. Survey work can proceed before
that folder arrives; the compatibility gate cannot be claimed without it.
No retail copies, new dependencies or changes to the reference repository.

Read on demand: [sources](../reference/sources.md),
[map texture rules](../reference/textures.md#map-texture-contract),
[coordinates/projection](../reference/coordinates.md),
[lighting](../reference/rendering.md#lighting-contract-for-p6),
[model lookup](../reference/models.md), and [test procedure](../reference/testing.md).
