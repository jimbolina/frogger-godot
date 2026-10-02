# PC timing evidence

The owner selected the frozen `froggy` source port as the behavioral target,
including its 30 Hz clock. Original retail timing is a separate comparison;
it no longer blocks source-port movement work. Static evidence below strongly
supports a nominal 25 Hz budget for the supplied original executable, without
measuring timer delivery or game speed on the current machine.

## Supplied retail executable

Inspected 2026-10-01 using GNU objdump from `C:/msys64/mingw64/bin`.
The source is the owner's `FROGGER.EXE` at the [retail location](sources.md).
SHA-256: `215b444ebb6317c136cfaded17922909b743deb34ab16f72e140a99d87340e06`.
PE32 image base is `0x00400000`; addresses below are virtual addresses.
Only scalar facts are retained here, never retail bytes or disassembly.

| Fact | Address/evidence |
|---|---|
| `WINMM.timeSetEvent` import slot | `0x004ad5bc` |
| Timer creation wrapper | `0x00457b50`; API call at `0x00457b8d` |
| Period passed to wrapper | 20 ms at call `0x004234ed` |
| Callback passed to wrapper | `0x004238c0` |
| Periodic flag passed to API | 1 |
| Callback counter increment | `0x00475918` at `0x004238e1`, every callback |
| Logic-budget counter increment | `0x0047591c` at `0x004238f2`, only when the first counter is odd |
| Nominal budget cadence | One increment per two 20 ms callbacks: 40 ms, 25 Hz |
| Main-loop budget read/wait | `0x004312bd`, `0x004312d1` |
| Budget reset | `0x004312e1` |
| Budget clamp | Maximum 2 at `0x004312eb`–`0x004312f0` |
| Logic call | `0x004312f5` calls `0x004310d0`; additional calls at `0x00431335` with counter decrement at `0x00431350` |
| Global logic frame counter | `0x00475920`: load at `0x004310df`, increment at `0x004310ea`, store at `0x004310ed` |

The loop attribution follows the source-shaped sequence: Windows update,
non-network budget wait/reset/clamp, logic update, game-mode callback,
additional input/sound/logic updates. This is a high-confidence static match,
not a runtime symbol observation. Another branch reads/resets/clamps the same
counter at `0x00431358`–`0x0043137d`; network behavior needs its own contract.
Several front-end loops also consume this counter.

The global logic counter is independently attributed by the source-shaped
`GameUpdateLogic` body. Retail's branch at `0x004310d9` bypasses its increment
when the pause flag is set; frozen C places the increment before the pause
check. It therefore measures executed unpaused logic updates in this binary,
not every attempted invocation. Keep this distinction in runtime analysis.

A separate timer setup at `0x0041cb70` receives frequency 25 at
`0x0041c459`. Its API call at `0x0041cbee` passes integer `1000 / frequency`
and callback `0x0041cb50`, which calls `0x0041c9a0` when enabled. It does not
increment the logic-budget counter in its callback. Do not confuse this
separate 40 ms timer with the 20 ms callback that supplies logic ticks.
Other timers use 500 ms and 1000 ms periods.

## Frozen C and editor disagreement

The vendored `gamesys.H:164-165` declares maximum 3 loops and 30 logic calls
per second. `MAIN.C:820,857` creates an integer 33 ms timer and increments
`Main_frame_count`. `gamesys.C:1526-1561` consumes that counter. These are
source facts, not verified facts about this supplied PC binary.

FrogLord `SCGameInstance.java:732-735` returns 25 for PC and states that
Frogger PC is locked to 25 regardless of EU/NA. Entity delay editors use this
`getFPS()` conversion. The supplied retail static cadence agrees with that
editor convention and differs from the frozen C clock and clamp.

The frozen engine builds transformed source, not byte-identical upstream C:
`tools/sanitize_frogger_source.sh` applies lexical and semantic transforms.
The existing build's `CMakeCache.txt` selects `RelWithDebInfo` and the vendored
source directory. Its sanitized `MAIN.C:820,857` still has the same timer
request/counter increment; sanitized `gamesys.H:164-165` still declares 3/30.
`mr_stub_timer.c:28` asserts 30 and delivers deterministic ticks by presented
frame rather than measuring retail wall time.

Audit SHA-256 identities (working-tree bytes):

| Input | SHA-256 |
|---|---|
| Sanitization script | `94eea225c95f0b990e6a8f5f0bd2fbeac09bb7cf7209939d32b3d2a36824cb04` |
| Vendored MAIN.C | `2563708752458f63f91a314c84e7fcdf15e1a19a4e1ef848859d5b15f2fede46` |
| Sanitized MAIN.C | `0ac5a67b5529977184bb720257562a9af14f96df01b5723cdd0e053df0b19a74` |
| Vendored gamesys.H | `e73e33456f2c6f7984c29401f4c2af180b2f7258c4100872d71c1c35261ff830` |
| Sanitized gamesys.H | `6bf3b37bb6c8a6e00ec624d5deb08e72a90bee249695316501971b8fd680f120` |

### Source-port clock actually implemented

`mr_stub_timer.c:122-139` arms one pending virtual tick at timer creation.
`MRStub_TimerArm` (`:151`) sets a boolean rather than accumulating time.
`MRStub_TimerDeliver` (`:156-177`) consumes that pending tick once and calls
the registered callback. The stored requested delay is not used as a
wall-clock scheduler. `mr_stub_disp.c:643` delivers at ordering-table clear;
`:930-936` increments the presented-frame count and arms after display swap.
`mr_stub_boot.c:754` also arms at level load to prevent an initial empty wait.

Human driver `frogger.h:573` sets `FROGGER_TARGET_FPS` to 30;
`fg_main.c:883-885` computes its period from SDL performance frequency divided
by 30. `fg_hook.c:6393-6408` paces human sessions with an accumulating deadline,
sleeping for coarse waits. An overrun exceeding one period resets the deadline
to now plus one period, so a stall does not bank a burst. Smoke mode bypasses
wall-clock pacing. Thus 30 is the driver's actual human pacing target as well
as the C constant; it is not a promise of exact elapsed time on a slow machine.

The non-network game loop reads/resets the tick budget, caps at 3 and discards
any excess (`gamesys.C:1526-1556`). In ordinary source-port operation only one
virtual tick is pending per swap. Input and sound are read in the outer
options loop (`OPTIONS.C:146-147`) and again for additional logic steps
(`gamesys.C:1553-1555`). Gameplay object/animation updates occur within each
unpaused `GameUpdateLogic` (`gamesys.C:1321-1343`); front-end animation updates
occur per outer page iteration when gameplay is inactive (`OPTIONS.C:165-176`).
Render-instance polygon animation has separate per-render calls. These clocks
must not all be replaced by elapsed-time animation updates. The source global
logic counter increments even before its pause check (`gamesys.C:1315-1319`),
which differs from the audited original executable.

## Original-retail comparison limits

For an optional original-retail comparison, observe the executable running,
record its identity and
environment, measure elapsed wall time against logic-counter progression or
an independently countable game event, and compare a frozen reference trace.
Account for focus, pauses, timer delivery, render stalls and discarded budget.
Repeat for other supported executable identities before generalizing.
Static results cannot establish observed 25 Hz pacing. This comparison is
separate from the owner's authorized 30 Hz source-port target.

### Original executable startup prerequisites

Read-only startup analysis identifies a clean early return before timing
observation is possible. OS initialization at `0x00457200` calls
`GetVersionExA` at `0x0045729b` and tests `dwPlatformId`. Value 1 enters the
Windows 95 path (`0x004572f6`); value 2 takes `0x00457453`, returning zero at
`0x00457460`. WinMain's caller at `0x0042322d` takes this failure and returns
zero at `0x00423234`. Thus a modern NT-family Windows result can produce a
successful process exit code without launching gameplay. This statically
established path is consistent with a short exit-zero attempt, but the
attempt's actual branch was not observed.

Renderer setup is a second prerequisite, later in startup. The loader at
`0x00448200` opens the 32-bit game's HKLM
`Software\Hasbro Interactive\Frogger` key and reads `MR_RENDERER_CORE` at
`0x00448272`. It passes the selected DLL path to `LoadLibraryA` at
`0x004482a9`. Missing key/value or DLL is an error path; there is no local
`SETUP.DAT` fallback in this loader. Its caller at `0x00447ece` returns an
error at `0x00447eda`; WinMain tests that result at `0x004234ae` and cleans up
before its return at `0x004234de`. Other renderer configuration and DLL entry
points are also required after successfully loading the DLL. This does not
establish that renderer setup was reached in the short launch attempt.

The owner's original `SETUP.INI` specifies installing the renderer DLLs,
registering the game, and running VideoSetup before Frogger. The installer
stages `VIDSETUP.EXE` as `VideoSetup.exe`; its renderer selection supplies
configuration needed by the game's registry loader. Original `README.TXT`
documents DirectX 5 or later and VideoSetup. These are facts about the supplied
installation materials, not a recommendation to install their old DirectX
components on the current system. Merely staging EXE/MWD/SETUP.DAT and DLLs
does not satisfy the OS check or renderer registry configuration. No supported
command-line override for these two checks was found in the audited paths.

The subsequent bounded launch probe used the staged original executable with
process-only `__COMPAT_LAYER=WIN95` and error mode `0x8003`. It terminated after
0.146324 seconds with status `0xc0000005`, before gameplay observation; external
evidence is `p7/retail-probe/win95-launch.json`. This records a failed launch,
not proof that a particular OS-check branch changed or that any timing counter
ran. No installer or registry/settings modification was performed. No further
launches are planned within this investigation.

A working original retail environment supplied by the owner is
needed to observe this identity without changing its executable. An SDL
rebuild of the frozen engine cannot establish original-retail runtime timing.

Runtime access checked on 2026-10-01: an isolated external copy of the supplied
retail executable exited with code 0 after 0.410 seconds, before gameplay.
The owner's portable `C:/Users/janit/Desktop/frogger/frogger.exe` has SHA-256
`8886f43a067e0822a5b2f1dceb2aada7293971ac6421a0166a15bb8488cf8e1b`.
Its existing log identifies rebuilt engine entry points and live SDL input;
it is not the audited retail binary and was not launched for this measurement.
Its timing therefore cannot establish retail cadence. A working original-PC
runtime or suitably timestamped original-PC observation remains necessary.

Reproduce the identity-pinned static assertions with:

```powershell
python -B tools/audit_pc_timing.py ../froggy/resources/pc-version/extracted/FROGGER/FROGGER.EXE --objdump C:/msys64/mingw64/bin/objdump.exe
```

Once the owner has launched that game, substitute its known PID and an
existing output directory outside the repository:

```powershell
python -B tools/observe_pc_timing.py --pid 1234 --exe ../froggy/resources/pc-version/extracted/FROGGER/FROGGER.EXE --duration 30 --interval 0.01 --output C:/existing-evidence-directory/pc-timing.csv
```

The sampler verifies the PID's image path and SHA-256 before reading three
fixed counters. It uses only process read/query access, no debug attach,
injection or writes. CSV timestamps bracket each group of reads, which are
not atomic. The JSON sidecar records identity and configuration. Output paths
inside this repository, existing outputs, unknown identities, unsupported
platforms and durations over 300 seconds are refused. Failed observations
may leave partial evidence; a complete run and independent event comparison
are required for that comparison. Budget counts reset during consumption and cannot
be treated as monotonic; use callback/global-frame deltas for rates, accounting
for unsigned wrap and pauses.

The summary sidecar reports callback and global-frame rates with timestamp
read uncertainty. It assumes unsigned wrap for those monotonic counters;
runtime resets cannot be distinguished from wrap. It counts budget decreases
without treating that counter as cumulative. Neither focus nor pause is
inferred from a measured rate. Path/current-file identity checks do not prove
that a launcher left process memory unpatched, or rule out a concurrent file
replacement; document any wrapper in the observation environment. Outputs in
the frozen `../froggy` tree are refused as well.

Validate the tools with `python -B tools/test_pc_timing.py`. Strict gameplay
script compilation and both repository test modes remain separate phase gates.
