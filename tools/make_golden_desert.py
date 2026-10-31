#!/usr/bin/env python3
"""Independent synthetic facts from frozen ent_des.c/.h, ENTITY.C, GRID.C, PATH.C and MR_ANIM.C."""
import argparse
import json
import math
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_golden_paths as paths

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'tests/golden/synthetic/desert.json'
SOUND_CFG = ROOT / 'archive/third_party/froglord_cfg/sounds/1997-11-19-pc-retail.cfg'
U16, U32 = 0xffff, 0xffffffff
WORLD_GRAVITY = 0x2d800
SYSTEM_GRAVITY = 0x100000
ROCK_RADIUS = 0x80
GRID_ERROR = 0xbabe
IDENTITY = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096]
SOUNDS = {'CRACK': ('DES_CRACK', 48), 'ROCK_BOUNCE': ('DES_BOULDER_BOUNCE', 50),
          'ROCK_BREAK': ('DES_BOULDER_BREAK', 51), 'HOLE01': ('DES_HOLE01', 53),
          'SNAKE_RATTLE': ('DES_SNAKE_RATTLE', 59), 'VULTURE': ('DES_VULTURE', 60),
          'TUMBLEWEED': ('DES_TUMBLEWEED', 61), 'CROCODILE_SNAP': ('DES_CROCODILE_SNAP', 62),
          'FROG_CROC_MUNCH': ('DES_FROG_CROC_MUNCH', 63)}
SFX = {key: value for key, (_, value) in SOUNDS.items()}
ROCK_CHECKING, ROCK_DELAY, ROCK_TARGETS, ROCK_EXPLODE, ROCK_EXPLODING = 0, 1, 3, 4, 5
SNAKE_NORMAL, SNAKE_BITE, SNAKE_TURNING, SNAKE_RATTLE = 0, 1, 2, 3
CROC_PAUSE3, CROC_RISE, CROC_PAUSE1, CROC_SNAP, CROC_PAUSE2, CROC_FALL = range(6)
CRACK_WAITING, CRACK_TO_FALL, CRACK_FALLING, CRACK_FINISHED = range(4)
REPEATED = (1 << 18) | (1 << 19)
BOUNCED = (1 << 16) | (1 << 17)


def s16(value):
    """Narrow to MR_SHORT with two's-complement wrap."""
    value &= U16
    return value - 0x10000 if value & 0x8000 else value


def s32(value):
    """Narrow to MR_LONG with two's-complement wrap."""
    value &= U32
    return value - 0x100000000 if value & 0x80000000 else value


def c_div(numerator, denominator):
    """Signed C division truncating toward zero."""
    quotient = abs(numerator) // abs(denominator)
    return quotient if (numerator < 0) == (denominator < 0) else -quotient


def sound_ids():
    """Confirm the PC flat sound order from FrogLord's retail name list."""
    names = []
    for line in SOUND_CFG.read_text(encoding='utf-8').splitlines():
        text = line.split('#', 1)[0].strip()
        if text and not text.startswith('['):
            names.append(text)
    for key, (name, value) in SOUNDS.items():
        if names.index(name) != value:
            raise ValueError(f'{key} is flat sound {names.index(name)}, not {value}')


def outer12(a, b):
    """OuterProduct12 with arithmetic shifts."""
    return [s32(a[1] * b[2] - a[2] * b[1]) >> 12, s32(a[2] * b[0] - a[0] * b[2]) >> 12,
            s32(a[0] * b[1] - a[1] * b[0]) >> 12]


def axes_matrix(z):
    """Y-up cross products, VectorNormal and WriteAxesAsMatrix into MR_SHORT entries."""
    z = paths.normalised(z)
    x = paths.normalised(outer12([0, 4096, 0], z))
    y = outer12(z, x)
    return [s16(v) for row in range(3) for v in (x[row], y[row], z[row])]


def multiply(a, b):
    """MulMatrix (MRMulMatrixABA): A = A·B, each entry (Σ)>>12 stored as MR_SHORT."""
    return [s16(sum(a[row * 3 + k] * b[k * 3 + col] for k in range(3)) >> 12)
            for row in range(3) for col in range(3)]


def roll(matrix, angle):
    """MRRot_matrix_X (identity-initialised global) with rounded rcos/rsin, then M·Rot_X."""
    cosine, sine = paths.trig(angle)
    return multiply(matrix, [4096, 0, 0, 0, cosine, -sine, 0, sine, cosine])


def apply_sv(matrix, vector):
    """ApplyMatrixSV: rotation only, arithmetic >>12, MR_SHORT results."""
    return [s16(sum(matrix[row * 3 + k] * vector[k] for k in range(3)) >> 12) for row in range(3)]


def isqrt_long(value):
    """SquareRoot0 over a non-negative MR_LONG."""
    if value < 0 or value > 0x7fffffff:
        raise ValueError('squared distance leaves MR_LONG')
    return math.isqrt(value)


def finished(cel, total):
    """LiveEntityCheckAnimationFinished."""
    return cel >= total - 1


def step_cel(cel, total, one_shot=False):
    """One MRAnimUpdateEnvironments step with update period 1."""
    cel += 1
    if cel >= total:
        cel = total - 1 if one_shot else 0
    return cel


def grid_height(grid, x, y, z):
    """GetHeightFromWorldXYZ over corner heights given in mp_vertices order."""
    gx, gz = (x - grid['base_x']) >> 8, (z - grid['base_z']) >> 8
    if not (0 <= gx < grid['xnum'] and 0 <= gz < grid['znum']):
        raise ValueError('synthetic target leaves the grid')
    count, index = grid['stacks'][gz * grid['xnum'] + gx]
    if count == 0:
        return GRID_ERROR, True
    chosen = index
    for square in range(index + count - 1, index - 1, -1):
        chosen = square
        if any(corner >= y for corner in grid['squares'][square]):
            break
    y0, y1, y2, y3 = grid['squares'][chosen]
    dx, dz = x & 0xff, z & 0xff
    if dz >= dx:
        return y0 + ((dx * (y1 - y0)) >> 8) + (((0x100 - dz) * (y2 - y0)) >> 8), False
    return y3 + (((0x100 - dx) * (y2 - y3)) >> 8) + ((dz * (y1 - y3)) >> 8), False


def rock_targets(case):
    """ENTSTRDesCreateFallingRock's in-place target projection."""
    targets = [list(target) for target in case['targets']]
    errors = [False] * len(targets)
    flags = case['flags']
    bounces = case['bounces']
    if bounces > len(targets):
        raise ValueError('bounces exceed the target array')
    if flags != 1:
        remaining = bounces
        for index in range(bounces):
            remaining -= 1
            target = targets[index]
            target[0] = s16((target[0] & ~0xff) + 0x80)
            target[2] = s16((target[2] & ~0xff) + 0x80)
            height, errors[index] = grid_height(case['grid'], target[0], target[1], target[2])
            target[1] = s16(height)
            if remaining == bounces - 1:
                target[1] = s16(target[1] - ROCK_RADIUS)
        flags = 1
    return dict(flags=flags, targets=[dict(x=t[0], y=t[1], z=t[2], time=t[3], error=e)
                                      for t, e in zip(targets, errors)])


def rock_velocity(case):
    """ENTSTRDesFallingRockCalculateInitialVelocity with MR_LONG truncating division."""
    position, target, time = case['position'], case['target'], case['time']
    vx = c_div(s32((target[0] << 16) - position[0]), time)
    vz = c_div(s32((target[2] << 16) - position[2]), time)
    vy = s32(c_div(s32((target[1] << 16) - position[1]), time) - s32(WORLD_GRAVITY * (time >> 1)))
    return [s32(vx), vy, s32(vz)]


def rock_pose(case):
    """TARGETS-state axes from velocity, then the -0x60 roll about local X."""
    rotation = (case['rotation'] - 0x60) & 0xfff
    axes = axes_matrix([v >> 16 for v in case['velocity']])
    return dict(rotation=rotation, axes=axes, matrix=roll(axes, rotation))


def rock_arc(case):
    """ENTSTRDesUpdateFallingRock ticks followed by the anim-environment step."""
    origin = case['matrix'][9:12]
    targets, bounces, cels = case['targets'], case['bounces'], case['explosion_cels']
    position = [s32(v << 16) for v in origin]
    velocity = [0, 0, 0]
    state, bounce, timer, rotation = ROCK_CHECKING, 0, 0, 0
    matrix, translation = list(case['matrix'][:9]), list(origin)
    hidden, shadow, overlay = False, False, None

    def launch():
        target = targets[bounce]
        return rock_velocity(dict(position=position, target=target[:3], time=target[3])), target[3]

    def row(tick, sounds):
        return dict(tick=tick, state=state, t=list(translation), matrix=list(matrix), rotation=rotation,
                    bounce_index=bounce, timer=timer, velocity=list(velocity), sounds=sounds,
                    model_hidden=hidden, shadow_visible=shadow, overlay_cel=-1 if overlay is None else overlay)

    rows = [row(0, [])]
    for tick in range(1, case['ticks'] + 1):
        sounds = []
        if state == ROCK_CHECKING:
            timer, state, shadow = case['delay'], ROCK_DELAY, True
        elif state == ROCK_DELAY:
            previous, timer = timer, (timer - 1) & U16
            if previous == 0:
                velocity, timer = launch()
                state, hidden, shadow = ROCK_TARGETS, False, True
        elif state == ROCK_TARGETS:
            velocity[1] = s32(velocity[1] + WORLD_GRAVITY)
            position = [s32(p + v) for p, v in zip(position, velocity)]
            translation = [p >> 16 for p in position]
            translation[1] = s32(translation[1] - ROCK_RADIUS)
            pose = rock_pose(dict(velocity=velocity, rotation=rotation))
            rotation, matrix = pose['rotation'], pose['matrix']
            previous, timer = timer, (timer - 1) & U16
            if previous <= 0:
                bounce += 1
                if bounce < bounces:
                    position[0] = s32(targets[bounce - 1][0] << 16)
                    position[2] = s32(targets[bounce - 1][2] << 16)
                    velocity, timer = launch()
                    sounds.append(SFX['ROCK_BOUNCE'])
                else:
                    state = ROCK_EXPLODE
                    sounds.append(SFX['ROCK_BREAK'])
            shadow = True
        elif state == ROCK_EXPLODE:
            overlay, matrix, hidden = -1, list(IDENTITY), True
            state, shadow = ROCK_EXPLODING, False
        elif state == ROCK_EXPLODING and overlay >= cels - 1:
            timer, state, bounce, overlay = 0, ROCK_DELAY, 0, None
            position = [s32(v << 16) for v in origin]
            translation = list(origin)
        if overlay is not None:
            overlay = step_cel(overlay, cels)
        rows.append(row(tick, sounds))
    explode = [r['tick'] for r in rows if r['state'] == ROCK_EXPLODING and rows[r['tick'] - 1]['state'] == ROCK_EXPLODE]
    resets = [r['tick'] for r in rows[1:] if r['state'] == ROCK_DELAY and rows[r['tick'] - 1]['state'] == ROCK_EXPLODING]
    return dict(rows=rows, explode_ticks=explode, reset_ticks=resets)


def path_step(state, segments):
    """UpdatePathRunners for one runner, as interpreted in make_golden_paths."""
    state['flags'] &= ~0x3f0000
    if not state['flags'] & 1:
        return
    length = segments[state['index']]['length']
    if state['flags'] & 2:
        state['distance'] = s32(state['distance'] - state['speed'])
        if state['distance'] < 0:
            state['index'] -= 1
            if state['index'] < 0:
                if not state['flags'] & 8:
                    raise ValueError('synthetic rolling path must repeat')
                state['index'] = len(segments) - 1
                state['flags'] |= 1 << 18
            state['distance'] = s32(state['distance'] + segments[state['index']]['length'])
    else:
        state['distance'] = s32(state['distance'] + state['speed'])
        if state['distance'] >= length:
            state['index'] += 1
            if state['index'] == len(segments):
                if not state['flags'] & 8:
                    raise ValueError('synthetic rolling path must repeat')
                state['index'] = 0
                state['flags'] |= 1 << 19
            state['distance'] = s32(state['distance'] - length)


def rolling_rock_cycle(case):
    """ENTSTRDesUpdateRollingRock over a repeating line path with the slot-1 explosion."""
    segments, cels = case['segments'], case['explosion_cels']
    runner = dict(index=case['start']['segment_index'], distance=case['start']['distance'],
                  speed=case['start']['speed'], flags=case['start']['flags'])
    _, position, tangent = paths.sample(segments[runner['index']], runner['distance'], bool(runner['flags'] & 2))
    translation, matrix = list(position), axes_matrix(tangent)
    saved = None
    mode, rotation, no_collision, hidden, overlay, explosion = 0, 0, False, False, None, None
    rows = [dict(tick=0, mode=mode, t=translation, matrix=matrix, rotation=rotation,
                 segment_index=runner['index'], distance=runner['distance'], path_active=True,
                 just_repeated=False, no_collision=False, hidden=False, explosion_t=None, overlay_cel=-1)]
    for tick in range(1, case['ticks'] + 1):
        path_step(runner, segments)
        repeated = bool(runner['flags'] & REPEATED)
        _, position, tangent = paths.sample(segments[runner['index']], runner['distance'], bool(runner['flags'] & 2))
        translation, matrix = list(position), axes_matrix(tangent)
        if mode == 0:
            rotation = (rotation - 0x40) & 0xfff
            matrix = roll(matrix, rotation)
            if repeated:
                if saved is None:
                    raise ValueError('synthetic path repeats before the first copied position')
                mode, overlay, explosion = 1, -1, list(saved)
                runner['flags'] &= ~1
                no_collision, hidden = True, True
            else:
                saved = list(translation)
        elif overlay >= cels - 1:
            mode, rotation, overlay, explosion = 0, 0, None, None
            runner['flags'] |= 1
            no_collision, hidden = False, False
        if overlay is not None:
            overlay = step_cel(overlay, cels)
        rows.append(dict(tick=tick, mode=mode, t=translation, matrix=matrix, rotation=rotation,
                         segment_index=runner['index'], distance=runner['distance'],
                         path_active=bool(runner['flags'] & 1), just_repeated=repeated,
                         no_collision=no_collision, hidden=hidden, explosion_t=explosion,
                         overlay_cel=-1 if overlay is None else overlay))
    wraps = [r['tick'] for r in rows if r['just_repeated']]
    resumes = [r['tick'] for r in rows[1:] if r['mode'] == 0 and rows[r['tick'] - 1]['mode'] == 1]
    return dict(rows=rows, explode_ticks=wraps, resume_ticks=resumes)


def tumbleweed_hops(case):
    """ENTSTRDesUpdateTumbleWeed shadow cell test, roll and rand()-driven hop."""
    seed, count, velocity, height, rotation = case['seed'] & U32, 0, 0, 0, 0
    grid = case['grid']
    rows = []
    for tick in range(1, case['ticks'] + 1):
        x = case['start'][0] + case['step'][0] * tick
        z = case['start'][1] + case['step'][1] * tick
        y = case['path_y']
        gx, gz = (x - grid['base_x']) >> 8, (z - grid['base_z']) >> 8
        shadow = not (gx < 1 or gx >= grid['xnum'] - 1 or gz < 1 or gz >= grid['znum'] - 1)
        rotation = (rotation - 0x60) & 0xfff
        drawn = -1
        previous, count = count, count - 1
        if previous == 0:
            seed = (seed * 0x41c64e6d + 0x3039) & U32
            drawn = ((seed >> 16) & 0x7fff) % 4 + 6
            count = drawn
            velocity = s32(-((SYSTEM_GRAVITY * (count + 1)) >> 1))
            height = y
        else:
            velocity = s32(velocity + SYSTEM_GRAVITY)
            height = s32(height + (velocity >> 16))
            y = height
        rows.append(dict(tick=tick, x=x, z=z, y=y, count=count, drawn=drawn, vy=velocity, height=height,
                         rotation=rotation, shadow_visible=shadow, seed=seed))
    return dict(create_sound=[SFX['TUMBLEWEED'], 512, 1024], rows=rows)


def snake_distance(case):
    """DistanceToFrogger(ENTSCR_COORD_Z, 512) for one active frog, else the 9999999 sentinel."""
    if not case['frog_active']:
        return 9999999
    matrix, frog = case['matrix'], case['frog']
    point = [s16(v + t) for v, t in zip(apply_sv(matrix[:9], [0, 0, 512]), matrix[9:12])]
    delta = [s16(f - p) for f, p in zip(frog, point)]
    return isqrt_long(sum(v * v for v in delta))


def snake_switch(action, distance, lane, anim_finished):
    """The ENTSTRDesUpdateSnake action switch: new request (or -1) and SNAKE_RATTLE count."""
    made, rattles = -1, 0
    if action == SNAKE_NORMAL:
        if distance < 256 and lane:
            made = SNAKE_BITE
        if 256 < distance < 512:
            made = SNAKE_RATTLE
    elif action == SNAKE_RATTLE:
        if distance < 256:
            rattles += 1
            if lane:
                made = SNAKE_BITE
        if distance > 512:
            made = SNAKE_NORMAL
        elif anim_finished:
            rattles += 1
    elif action == SNAKE_BITE and distance > 256:
        made = SNAKE_NORMAL
    return made, rattles


def snake_range(case):
    """One ENTSTRDesUpdateSnake action switch and request application, ignoring path ends."""
    distance = snake_distance(case)
    matrix, frog = case['matrix'], case['frog']
    if abs(matrix[2]) > abs(matrix[8]):
        lane = matrix[11] - 64 < frog[2] < matrix[11] + 64
    else:
        lane = matrix[9] - 64 < frog[0] < matrix[9] + 64
    made, rattles = snake_switch(case['action'], distance, lane, case['anim_finished'])
    request, requested = case['pending'], case['requested']
    if made >= 0:
        request, requested = True, made
    set_action = -1
    if request and case['anim_finished']:
        set_action, request = requested, False
    return dict(distance=distance, lane=lane, made_request=made, request=request, requested=requested,
                rattle_sounds=[SFX['SNAKE_RATTLE']] * rattles, set_action=set_action)


def snake_turn(case):
    """Path-end TURNING selection, 19-count hold and resume with distant frogs."""
    lengths = case['lengths']
    action, cel, frame_count = SNAKE_NORMAL, 0, 0
    active, no_movement = True, False
    request, requested = case['pending'] >= 0, max(case['pending'], 0)
    rows = []
    for tick in range(1, case['ticks'] + 1):
        bounced = tick in case['bounce_ticks']
        if bounced and not active:
            raise ValueError('a paused runner cannot bounce')
        unpaused = False
        if action == SNAKE_TURNING:
            if frame_count == 0:
                request, requested, no_movement, active, unpaused = True, SNAKE_NORMAL, False, True, True
            else:
                frame_count -= 1
        else:
            made, _ = snake_switch(action, case['distance'], False, finished(cel, lengths[action]))
            if made >= 0:
                request, requested = True, made
        if bounced:
            action, cel, frame_count, no_movement, active = SNAKE_TURNING, -1, 19, True, False
        set_action = -1
        if request and finished(cel, lengths[action]):
            action, cel, request, set_action = requested, -1, False, requested
        cel = step_cel(cel, lengths[action])
        rows.append(dict(tick=tick, bounced=bounced, action=action, cel=cel, frame_count=frame_count,
                         path_active=active, no_movement=no_movement, unpaused=unpaused,
                         request=request, requested=requested, set_action=set_action))
    return dict(rows=rows, unpause_ticks=[r['tick'] for r in rows if r['unpaused']],
                set_ticks=[[r['tick'], r['set_action']] for r in rows if r['set_action'] >= 0])


def vulture_tangent(case):
    """ENTSTRDesUpdateVulture: switch on the requested animation, apply when the action ends."""
    lengths = case['lengths']
    action, cel, request, requested = 0, 0, False, 0
    rows = []
    for tick, tangent_y in enumerate(case['tangent_y'], 1):
        sound = -1
        if requested == 0 and tangent_y > -128:
            request, requested = True, 1
            sound = SFX['VULTURE'] if case['moving_sound_free'] else -1
        elif requested == 1 and tangent_y < -128:
            request, requested = True, 0
        set_action = -1
        if request and finished(cel, lengths[action]):
            action, cel, request, set_action = requested, -1, False, requested
        cel = step_cel(cel, lengths[action])
        rows.append(dict(tick=tick, tangent_y=tangent_y, requested=requested, request=request,
                         action=action, cel=cel, set_action=set_action, sound=sound))
    return dict(moving_sound=[SFX['VULTURE'], 1024, 2048], rows=rows)


def croc_timeline(case):
    """ENTSTRDesUpdateCrocHead modes, u16 start height, == waits and rider kills."""
    y = case['start_y']
    start = y & U16
    mode, wait, deadly = CROC_PAUSE3, 0, True
    rows, kills = [], []
    for tick in range(1, case['ticks'] + 1):
        snap_action, snap_sound = False, -1
        if mode == CROC_PAUSE3:
            wait = (wait + 1) & U32
            if wait == case['submerged_delay']:
                wait, mode, deadly = 0, CROC_RISE, False
        elif mode == CROC_RISE:
            y = s32(y - case['rise_speed'])
            if y < start - case['rise_height']:
                y, wait, mode = start - case['rise_height'], 0, CROC_PAUSE1
        elif mode == CROC_PAUSE1:
            wait = (wait + 1) & U32
            if wait == case['snap_delay']:
                wait = 0
                if case['snap_flag'] == 1:
                    mode, deadly = CROC_SNAP, True
                else:
                    mode = CROC_PAUSE2
        elif mode == CROC_SNAP:
            wait = (wait + 1) & U32
            if wait == 1:
                snap_action = True
            if wait == 10:
                wait, mode, deadly = 0, CROC_PAUSE2, False
                if case['moving_sound_free']:
                    snap_sound = SFX['CROCODILE_SNAP']
        elif mode == CROC_PAUSE2:
            wait = (wait + 1) & U32
            if wait == case['pause_delay']:
                wait, mode = 0, CROC_FALL
        elif mode == CROC_FALL:
            y = s32(y + case['rise_speed'])
            if y > start:
                mode, deadly = CROC_PAUSE3, True
        carried = tick in case['carry_ticks']
        kill = deadly and carried
        if kill:
            kills.append(tick)
        rows.append(dict(tick=tick, mode=mode, y=y, wait=wait, deadly=deadly, carried=carried,
                         kill=kill, munch=[SFX['FROG_CROC_MUNCH']] if kill else [],
                         snap_action=snap_action, snap_sound=snap_sound))
    return dict(start_position=start, rows=rows, kill_tick=kills[0] if kills else -1,
                kill_animation='BITTEN', munch_count=len(kills),
                snap_sound_ticks=[r['tick'] for r in rows if r['snap_sound'] >= 0])


def crack_timeline(case):
    """ENTSTRDesUpdateCrack hit cels, delayed one-shot, rider fall and sinking colour."""
    hops, cels, origin = case['hops_before'], case['cels'], case['y']
    state, hits, wait, velocity, fixed, y = CRACK_WAITING, 0, 0, 0, 0, origin
    cel, stepping, no_collision = 0, False, False
    rows = []
    for tick in range(1, case['ticks'] + 1):
        entry, sounds, fall, colour = -1, [], False, -1
        if state == CRACK_WAITING:
            if tick in case['hit_ticks']:
                entry = (3 - (hops - hits)) & U16
                hits = (hits + 1) & 0xff
                sounds.append(SFX['CRACK'])
                if hits >= hops:
                    wait, state = 2, CRACK_TO_FALL
        elif state == CRACK_TO_FALL:
            wait = (wait - 1) & U16
            if wait:
                stepping = True
                sounds.append(SFX['HOLE01'])
                state, fixed = CRACK_FALLING, s32(y << 16)
        elif state == CRACK_FALLING and finished(cel, cels):
            if wait > 0:
                wait -= 1
                if wait == 0:
                    no_collision, fall = True, True
            else:
                velocity = s32(velocity + (SYSTEM_GRAVITY * 5) // 4)
                if y < 1024:
                    fixed = s32(fixed + velocity)
                    y = fixed >> 16
                else:
                    state = CRACK_FINISHED
                colour = max(0, ((origin - y) >> 3) + 0x80)
        if stepping:
            cel = step_cel(cel, cels, one_shot=True)
        rows.append(dict(tick=tick, state=state, hits=hits, cel_entry=entry, sounds=sounds, anim_cel=cel,
                         wait=wait, no_collision=no_collision, frog_fall=fall, y=y, colour=colour))
    start = [r['tick'] for r in rows if SFX['HOLE01'] in r['sounds']]
    falls = [r['tick'] for r in rows if r['frog_fall']]
    done = [r['tick'] for r in rows if r['state'] == CRACK_FINISHED]
    return dict(rows=rows, flipbook_start_tick=start[0] if start else -1,
                fall_tick=falls[0] if falls else -1, finished_tick=done[0] if done else -1)


def target_grid():
    """A 4x4 grid: flat, sloped, two-layer and empty stacks; corners in mp_vertices order."""
    squares = [[0, 0, 0, 0], [-40, -81, 3, -40], [0, 0, 0, 0], [-256, -256, -256, -256],
               [100, 100, 100, 100], [-17, 33, -5, 61]]
    stacks = [[1, 0], [1, 1], [2, 2], [0, 0],
              [1, 4], [1, 5], [1, 0], [1, 1],
              [2, 2], [1, 4], [0, 0], [1, 5],
              [1, 0], [1, 0], [1, 0], [1, 0]]
    return dict(base_x=-512, base_z=-512, xnum=4, znum=4, stacks=stacks, squares=squares)


def target_cases():
    grid = target_grid()
    pad = [[0, 0, 0, 30]] * 12
    def targets(*items):
        return [list(t) for t in items] + [list(t) for t in pad[len(items):]]
    first = ([-500, 0, -500, 30], [-200, -10, -460, 31], [100, -100, -400, 15], [100, -300, -300, 60])
    sets = [
        (4, 0, targets(*first)),
        (2, 0, targets([100, -256, -511, 4], [100, 1, -257, 5])),
        (1, 0, targets([300, 0, -512, 9])),
        (4, 0, targets([-512, 0, -256, 2], [-1, 0, -1, 2], [-256, 50, 0, 3], [10, 0, 10, 1])),
        (12, 0, targets(*[[-512 + 85 * i, -300 + 60 * i, -512 + 91 * i, 10 + i] for i in range(12)])),
        (0, 0, targets([-500, 7, -500, 30])),
        (4, 1, targets(*first)),
        (2, 2, targets([-129, 0, -511, 4], [255, 0, -512, 9])),
    ]
    return [dict(input=dict(grid=grid, bounces=b, flags=f, targets=t), expected=rock_targets(dict(grid=grid, bounces=b, flags=f, targets=t)))
            for b, f, t in sets]


def velocity_cases():
    out = []
    positions = ([0, 0, 0], [-2176 << 16, -5120 << 16, 1408 << 16], [5 << 16 | 0x8000, -(3 << 16) - 1, 7],
                 [0x7fff0000, -0x80000000, 0x12345])
    targets = ([-1920, -128, 1408], [128, 0, -1], [-32768, 32767, 0], [0, 0, 0])
    for position in positions:
        for target in targets:
            for time in (1, 2, 3, 15, 30, 31, 60, 65535):
                case = dict(position=position, target=target, time=time)
                out.append(dict(input=case, expected=rock_velocity(case)))
    return out


def arc_cases():
    base = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096]
    sets = [
        dict(matrix=base + [-2176, -1024, 1408], delay=2, bounces=2, explosion_cels=16, ticks=50,
             targets=[[-1920, -128, 1408, 3], [-896, 0, 1408, 4]]),
        dict(matrix=[0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 128, -600, -128], delay=0, bounces=1, explosion_cels=16,
             ticks=24, targets=[[384, -128, -128, 1]]),
        dict(matrix=base + [2176, -5120, -1152], delay=60, bounces=4, explosion_cels=16, ticks=210,
             targets=[[1920, -128, -1152, 30], [896, 0, -1152, 30], [-128, 0, -1152, 30], [-1152, -141, -1152, 30]]),
    ]
    return [dict(input=case, expected=rock_arc(case)) for case in sets]


def pose_cases():
    out = []
    velocities = ([0, 0, 1 << 16], [1 << 16, 0, 0], [3 << 16, -(5 << 16), 2 << 16], [0, 7 << 16, 0], [-1, -1, -1],
                  [0x7fff0000, 0x12340000, -0x7fff0000], [0, 0, 0], [-(1 << 16), 0x2d800, 1 << 16], [0x80000, -0x28000, -0x8000])
    for velocity in velocities:
        for rotation in (0, 0x30, 0x60, 1024, 2048, 4000, 4095):
            case = dict(velocity=velocity, rotation=rotation)
            out.append(dict(input=case, expected=rock_pose(case)))
    return out


def rolling_cases():
    line = [dict(segment_type=2, length=512, start=[0, -64, 0], end=[512, -64, 0]),
            dict(segment_type=2, length=512, start=[512, -64, 0], end=[512, -64, 512])]
    sets = [dict(segments=line, start=dict(segment_index=0, distance=0, speed=64, flags=9), explosion_cels=16, ticks=60),
            dict(segments=line, start=dict(segment_index=1, distance=448, speed=96, flags=11), explosion_cels=16, ticks=48),
            dict(segments=line[:1], start=dict(segment_index=0, distance=300, speed=100, flags=9), explosion_cels=3, ticks=20)]
    return [dict(input=case, expected=rolling_rock_cycle(case)) for case in sets]


def tumbleweed_cases():
    grid = dict(base_x=-1024, base_z=-1024, xnum=8, znum=8)
    sets = [dict(seed=0, start=[-1000, 0], step=[40, 0], path_y=-20, ticks=50, grid=grid),
            dict(seed=0x12345678, start=[700, 700], step=[-48, -32], path_y=0, ticks=40, grid=grid),
            dict(seed=0xffffffff, start=[-770, -1000], step=[0, 64], path_y=-300, ticks=36, grid=grid)]
    return [dict(input=case, expected=tumbleweed_hops(case)) for case in sets]


def snake_cases():
    out = []
    facings = {'z_north': [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 1000, 0, 2000],
               'z_east': [0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 1000, 0, 2000]}
    for name, matrix in facings.items():
        ahead = [s16(v + t) for v, t in zip(apply_sv(matrix[:9], [0, 0, 512]), matrix[9:12])]
        offsets = []
        for d in (0, 255, 256, 257, 511, 512, 513):
            offsets.append([d, 0, 0])
            offsets.append([0, 0, d])
        offsets += [[63, 0, 63], [64, 0, 0], [-64, 0, -64], [0, -255, 0], [200, 100, 100]]
        frogs = [[ahead[i] + o[i] for i in range(3)] for o in offsets]
        frogs += [[1000 + 63, 0, 2000 + 200], [1000 + 64, 0, 2000 + 200], [1000 - 64, 0, 2000],
                  [1000 + 200, 0, 2000 + 63], [1000 + 200, 0, 2000 - 64]]
        for frog in frogs:
            for action in (SNAKE_NORMAL, SNAKE_RATTLE, SNAKE_BITE):
                for anim_finished in (False, True):
                    case = dict(facing=name, matrix=matrix, frog=frog, frog_active=True, action=action,
                                anim_finished=anim_finished, pending=False, requested=0)
                    out.append(dict(input=case, expected=snake_range(case)))
    for pending, requested in ((True, SNAKE_RATTLE), (True, SNAKE_BITE)):
        for anim_finished in (False, True):
            case = dict(facing='z_north', matrix=facings['z_north'], frog=[0, 0, 0], frog_active=False,
                        action=SNAKE_NORMAL, anim_finished=anim_finished, pending=pending, requested=requested)
            out.append(dict(input=case, expected=snake_range(case)))
    return out


def turn_cases():
    far = 9999999
    sets = [dict(lengths=[20, 16, 20, 20], bounce_ticks=[30, 75], pending=-1, distance=far, ticks=110),
            dict(lengths=[20, 16, 20, 20], bounce_ticks=[5], pending=SNAKE_RATTLE, distance=far, ticks=40),
            dict(lengths=[20, 16, 12, 20], bounce_ticks=[5], pending=SNAKE_BITE, distance=far, ticks=60),
            dict(lengths=[20, 16, 20, 20], bounce_ticks=[12], pending=-1, distance=300, ticks=50)]
    return [dict(input=case, expected=snake_turn(case)) for case in sets]


def vulture_cases():
    sequence = [-200, -129, -128, -127, -127, -128, -129, -200] + [-128] * 20 + [-127] * 8 + [-129] * 30 + [4096] * 10
    sets = [dict(lengths=[28, 12], tangent_y=sequence, moving_sound_free=True),
            dict(lengths=[28, 12], tangent_y=[-127] * 5 + [-129] * 40 + [0] * 30, moving_sound_free=False)]
    return [dict(input=case, expected=vulture_tangent(case)) for case in sets]


def croc_cases():
    sets = [dict(start_y=256, rise_height=256, rise_speed=50, snap_delay=50, pause_delay=50, snap_flag=1,
                 submerged_delay=50, ticks=260, carry_ticks=[3, 60, 61, 115, 116, 124, 125, 175, 176],
                 moving_sound_free=True),
            dict(start_y=256, rise_height=256, rise_speed=20, snap_delay=20, pause_delay=20, snap_flag=0,
                 submerged_delay=10, ticks=120, carry_ticks=[5, 20, 45, 80, 95], moving_sound_free=True),
            dict(start_y=255, rise_height=256, rise_speed=50, snap_delay=65535, pause_delay=50, snap_flag=1,
                 submerged_delay=50, ticks=80, carry_ticks=[50, 51, 70], moving_sound_free=True),
            dict(start_y=256, rise_height=256, rise_speed=50, snap_delay=30, pause_delay=20, snap_flag=1,
                 submerged_delay=20, ticks=90, carry_ticks=[], moving_sound_free=False),
            dict(start_y=-40, rise_height=60, rise_speed=7, snap_delay=5, pause_delay=5, snap_flag=1,
                 submerged_delay=3, ticks=40, carry_ticks=[1, 4], moving_sound_free=True),
            dict(start_y=100, rise_height=60, rise_speed=0, snap_delay=5, pause_delay=5, snap_flag=1,
                 submerged_delay=0, ticks=20, carry_ticks=[2], moving_sound_free=True)]
    return [dict(input=case, expected=croc_timeline(case)) for case in sets]


def crack_cases():
    sets = [dict(hops_before=hops, hit_ticks=hits, y=-1633, cels=19, ticks=ticks)
            for hops, hits, ticks in ((0, [3], 60), (1, [2, 5], 60), (2, [2, 8, 9], 64),
                                      (3, [1, 4, 7, 8], 66), (5, [1, 2, 3, 4, 5, 6], 64))]
    sets.append(dict(hops_before=1, hit_ticks=[1], y=900, cels=1, ticks=12))
    sets.append(dict(hops_before=1, hit_ticks=[1], y=-100, cels=2, ticks=30))
    return [dict(input=case, expected=crack_timeline(case)) for case in sets]


def cases():
    """Invent source-boundary inputs; no retail data or game outputs are consumed."""
    sound_ids()
    return dict(rock_targets=target_cases(), rock_velocity=velocity_cases(), rock_arc=arc_cases(),
                rock_pose=pose_cases(), rolling_rock_cycle=rolling_cases(), tumbleweed_hops=tumbleweed_cases(),
                snake_range=snake_cases(), snake_turn=turn_cases(), vulture_tangent=vulture_cases(),
                croc_timeline=croc_cases(), crack_timeline=crack_cases())


def main():
    """Verify reproducibility by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(cases(), indent=1) + '\n'
    if args.write:
        OUTPUT.write_text(text)
    elif OUTPUT.read_text() != text:
        raise SystemExit('Desert facts differ; use --write only to deliberately regenerate')
    print('Desert facts verified')


if __name__ == '__main__':
    main()
