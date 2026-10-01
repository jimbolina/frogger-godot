# Simulation contracts

These are the gameplay design constraints for later phases; only the viewer clock and animation playback are implemented so far.

- Game logic runs in `_physics_process` at the original tick rate, with at most 3 steps per rendered frame. Rendering is interpolated. Godot's physics engine is not used; collision is the game's own.
- The tick rate is an open question to settle in P7: the reference engine runs 30 ticks per second, while FrogLord's editor treats the PC release as 25. Compare reference traces and the retail game in P7.
- The model viewer uses that existing 30 Hz clock. Its optional smoothing changes only presentation and defaults off; textures and animation state stay tick-driven.
- Entities update in the original list order, because random-number use depends on it.
- These keep integer behaviour: the random number generator, script timers and counters, path distance stepping, grid coordinates and form heights, the game timer, score, entity delay counters, and radius-squared collision tests.
- Frog hops last a whole number of ticks and snap to the grid on landing, so recorded demos replay approximately. Demo checks compare completion and end state, not the path.
- Floats are fine for camera easing, particles, animation blending and interpolation.

The C source defines 30 logic calls per second and creates a 33 ms PC timer; FrogLord converts PC entity delays using 25. P7 must resolve this discrepancy. If float demo playback drifts, use an integer-only frog and path core.

Future directories are created only when used: `src/game/` for world, entities, scripts, frog, camera, collision and effects; `src/mod/` for watching mod files and reporting unmapped behavior. See the [README layout](../../README.md#layout) for implemented directories.
