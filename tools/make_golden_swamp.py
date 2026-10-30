#!/usr/bin/env python3
"""Independent synthetic facts from frozen ent_swp.c/.h, scripter.c, ent_sub.c, ENTITY.C, MISC.C and FROG.C."""
import argparse
import json
import math
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_golden_desert as desert
import make_golden_exe_tables as exe_tables
import make_golden_jungle as jungle
import make_golden_paths as paths

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'tests/golden/synthetic/swamp.json'
SOUND_CFG = ROOT / 'third_party/froglord_cfg/sounds/1997-11-19-pc-retail.cfg'
SCRIPT_LIST = jungle.SCRIPT_LIST
U16 = 0xffff
NO_FROG = 9999999
SYSTEM_GRAVITY = 0x100000
WORLD_SHIFT = 8
SOUNDS = {'SWP_CRUSH_HIT': 105, 'SWP_NUCLEAR_BARREL_EXPLODE': 106, 'SWP_NUCLEAR_BARREL_GEIGER': 107,
          'SWP_ACID_DRIP': 114, 'SWP_CRUSH_AMB': 121, 'SWP_FROG_CRUSH': 123, 'SWP_MACHINE': 124,
          'GEN_FROG_DROWN1': 1}
SQUIRT_WAITING, SQUIRT_FALL_PREPARE, SQUIRT_FALLING = range(3)
SQUIRT_DISTANCE = PRESS_DISTANCE = 1536
CRUSHER_IN, CRUSHER_OUT = 0, 1
CRUSHER_NORTH, CRUSHER_EAST, CRUSHER_SOUTH, CRUSHER_WEST, CRUSHER_WAITING, CRUSHER_CRUSHING = range(6)
PRESS_MOVING_UP, PRESS_MOVING_DOWN = 0, 1
PRESS_UP, PRESS_DOWN, PRESS_WAITING, PRESS_CRUSHING = range(4)
CRUSHER_HIT_COUNT, CRUSHER_USER_COUNT = 5, 4
FROG_JUMP_TIME, CRUSHER_JUMP_COUNT = 6, 6
GRID_SQUARE_USABLE, GRID_SQUARE_DEADLY = 1 << 0, 1 << 2
FROG_JUMP_TO_LAND, FROG_JUMP_FROM_COLLPRIM = 1 << 6, 1 << 16
FROG_MODE_JUMPING, FROG_MODE_USER = 1, 0x100
FROGUSER_MODE_BOUNCE = FROG_MODE_USER + 12
FROG_DIRECTION_N, FROG_DIRECTION_E, FROG_DIRECTION_S, FROG_DIRECTION_W = range(4)
FROG_ANIMATION_SQUISHED, FROG_ANIMATION_DROWN = 2, 8
RAT_INIT_FIRST_JUMP, RAT_JUMP1, RAT_INIT_ROLL, RAT_ROLL, RAT_RUN, RAT_JUMP2, RAT_RESTART = range(7)
RAT_ANIM_RUN, RAT_ANIM_JUMP, RAT_ANIM_ROLL = range(3)
RAT_ROLL_TICKS = 24
RAT_SPLASH_Y = -0xff
SLUG_MOTION_CURVY, SLUG_ANIM_NORMAL, SLUG_ANIM_CURVY = 1, 0, 1
WEIR_ROTATION = 1024
ENTITY_TYPE_PATH, ENTITY_TYPE_MATRIX = 0, 1
REGISTER_SLOTS = 6
PATH_INFO_SIZE, MATRIX_SIZE = 12, 32
NO_REGISTERS, REGISTERS = 0, 1
COORD_X, COORD_Y, COORD_Z = 0, 1, 2
GOSUB_SCRIPT, SAFE_FROG, NO_CONDITION, CALLBACK_ALWAYS, CALLBACK_1 = 1, 4, 7, 1, 0
TIME_INFINITE = -1

s16, s32, c_div = desert.s16, desert.s32, desert.c_div
OPCODES = {name: index for index, (name, _) in enumerate(exe_tables.OPCODES)}
WIDTHS = {index: count + 1 for index, (_, count) in enumerate(exe_tables.OPCODES)}


def sound_ids():
    """Confirm the PC flat sound order from FrogLord's retail name list (sound.h SFX_SWP_CRUSHER is SWP_CRUSH_HIT)."""
    names = []
    for line in SOUND_CFG.read_text(encoding='utf-8').splitlines():
        text = line.split('#', 1)[0].strip()
        if text and not text.startswith('['):
            names.append(text)
    for name, value in SOUNDS.items():
        if names.index(name) != value:
            raise ValueError(f'{name} is flat sound {names.index(name)}, not {value}')


def rsin(angle):
    """The port's rounded sine table: round-half-away-from-zero of sin(angle·2π/4096)·4096."""
    return paths.trig(angle)[1]


def frog_distance(translation, frog):
    """DistanceToFrogger(live_entity, 0, 0): MR_SVEC_MOD of signed-short frog minus entity, or 9999999 without a frog."""
    if frog is None:
        return NO_FROG
    point = [s16(v) for v in translation]
    delta = [s16(frog[i] - point[i]) for i in range(3)]
    return min(NO_FROG, desert.isqrt_long(sum(d * d for d in delta)))


def squirt_timeline(case):
    """ENTSTRSwpCreateSquirt/UpdateSquirt: once-off s16 delay, then fall-prepare/fall cycles that snap back."""
    matrix, frog = case['matrix'], case['frog']
    delay, drop = s16(case['time_delay']), s16(case['drop_time'])
    target = [s16(v) for v in case['target']]
    if drop == 0:
        raise ValueError('a zero drop time divides by zero in the source')
    mode, timer, velocity, translation = SQUIRT_WAITING, delay, [0, 0, 0], list(matrix[9:12])

    def row(tick, sounds, distance):
        return dict(tick=tick, mode=mode, timer=timer, velocity=list(velocity), translation=list(translation),
                    sounds=sounds, distance=distance)

    rows = [row(0, [], -1)]
    for tick in range(1, case['ticks'] + 1):
        sounds, distance = [], -1
        if mode == SQUIRT_WAITING:
            if timer > 0:
                timer = s16(timer - 1)
            else:
                mode = SQUIRT_FALL_PREPARE
        elif mode == SQUIRT_FALL_PREPARE:
            position = [s32(v << 16) for v in translation]
            velocity = [c_div(s32((target[i] << 16) - position[i]), drop) for i in range(3)]
            timer, mode = drop, SQUIRT_FALLING
            distance = frog_distance(translation, frog)
            if distance < SQUIRT_DISTANCE:
                sounds.append(SOUNDS['SWP_ACID_DRIP'])
        else:
            translation = [s32(translation[i] + (velocity[i] >> 16)) for i in range(3)]
            previous, timer = timer, s16(timer - 1)
            if previous <= 0:
                mode, translation = SQUIRT_FALL_PREPARE, list(matrix[9:12])
        rows.append(row(tick, sounds, distance))
    return dict(rows=rows, sound_ticks=[r['tick'] for r in rows if r['sounds']],
                reset_ticks=[r['tick'] for r in rows[1:] if r['mode'] == SQUIRT_FALL_PREPARE
                             and rows[r['tick'] - 1]['mode'] == SQUIRT_FALLING])


def axis_move(translation, base, move, direction):
    """One crusher/press axis step: translation += sign·(speed>>8); past the bound the u16 direction flips (!dir)."""
    axis, sign, bound, greater = move
    translation[axis] = s32(translation[axis] + sign * (base['speed'] >> WORLD_SHIFT))
    limit = base['origin'][axis] + bound * base['distance']
    if (translation[axis] > limit) if greater else (translation[axis] < limit):
        return int(not direction)
    return direction


CRUSHER_MOVES = {
    CRUSHER_NORTH: ((2, 1, 1, True), (2, -1, 0, False)),
    CRUSHER_EAST: ((0, 1, 1, True), (0, -1, 0, False)),
    CRUSHER_SOUTH: ((2, -1, -1, False), (2, 1, 0, True)),
    CRUSHER_WEST: ((0, -1, -1, False), (0, 1, 0, True)),
}
PRESS_MOVES = {
    PRESS_UP: ((1, -1, -1, False), (1, 1, 0, True)),
    PRESS_DOWN: ((1, 1, 1, True), (1, -1, 0, False)),
}


def crusher_timeline(case):
    """ENTSTRSwpCreateCrusher/UpdateCrusher: u16 count decay, u16 post-decrement delay, then endless IN/OUT."""
    matrix = case['matrix']
    base = dict(speed=s16(case['speed']), distance=s16(case['distance']), origin=list(matrix[9:12]))
    authored_direction, delay = s16(case['direction']), s16(case['delay'])
    direction, timer, mode, count, translation = CRUSHER_IN, delay & U16, CRUSHER_WAITING, 0, list(matrix[9:12])

    def row(tick, hit):
        return dict(tick=tick, hit=hit, mode=mode, timer=timer, direction=direction, count=count,
                    translation=list(translation))

    rows = [row(0, False)]
    for tick in range(1, case['ticks'] + 1):
        hit = tick in case['callback_ticks']
        if hit:
            count = CRUSHER_HIT_COUNT
        if count:
            count = (count - 1) & U16
        if mode == CRUSHER_WAITING:
            previous, timer = timer, (timer - 1) & U16
            if previous == 0:
                mode = CRUSHER_CRUSHING
        elif authored_direction in CRUSHER_MOVES:
            direction = axis_move(translation, base, CRUSHER_MOVES[authored_direction][direction], direction)
        rows.append(row(tick, hit))
    return dict(moving_sound=[SOUNDS['SWP_CRUSH_AMB'], 768, 1280], rows=rows,
                flip_ticks=[r['tick'] for r in rows[1:] if r['direction'] != rows[r['tick'] - 1]['direction']])


def press_timeline(case):
    """ENTSTRSwpCreatePress/UpdatePress: the crusher timing on Y, with a sound on each return flip."""
    matrix, frog = case['matrix'], case['frog']
    base = dict(speed=s16(case['speed']), distance=s16(case['distance']), origin=list(matrix[9:12]))
    authored_direction, delay = s16(case['direction']), s16(case['delay'])
    direction, timer, mode, translation = PRESS_MOVING_UP, delay & U16, PRESS_WAITING, list(matrix[9:12])

    def row(tick, carried, sounds, distance):
        return dict(tick=tick, carried=carried, mode=mode, timer=timer, direction=direction,
                    translation=list(translation), sounds=sounds, distance=distance)

    rows = [row(0, False, [], -1)]
    for tick in range(1, case['ticks'] + 1):
        carried, sounds, distance = tick in case['carry_ticks'], [], -1
        if mode == PRESS_WAITING:
            previous, timer = timer, (timer - 1) & U16
            if previous == 0:
                mode = PRESS_CRUSHING
        elif authored_direction in PRESS_MOVES:
            returning = direction == PRESS_MOVING_DOWN
            flipped = axis_move(translation, base, PRESS_MOVES[authored_direction][direction], direction)
            if returning and flipped != direction:
                if carried:
                    sounds.append(SOUNDS['SWP_FROG_CRUSH'])
                else:
                    distance = frog_distance(translation, frog)
                    if distance < PRESS_DISTANCE:
                        sounds.append(SOUNDS['SWP_CRUSH_HIT'])
            direction = flipped
        rows.append(row(tick, carried, sounds, distance))
    return dict(moving_sound=[SOUNDS['SWP_MACHINE'], 768, 1280], rows=rows,
                sound_ticks=[r['tick'] for r in rows if r['sounds']])


def transpose_apply(matrix, vector):
    """MRTransposeMatrix then MRApplyMatrix: (Σ m[k][row]·v[k])>>12 into MR_LONG."""
    return [s32(sum(matrix[k * 3 + row] * vector[k] for k in range(3))) >> 12 for row in range(3)]


def crusher_callback(case):
    """SwpCrusherCallback with Game_map_theme == THEME_SWP: debounce, velocity-directed bounce, deadly FORM test."""
    grid, form = case['grid'], case['form']
    count = case['count'] & U16
    unchanged = dict(debounced=True, branch='none', happened=False, bounce='none', grid=None, direction=None,
                     square=None, flags_added=0, mode=None, frog_count=None, target=None, velocity=None,
                     velocity_after=list(case['velocity']),
                     translation=list(case['frog_t']), old_y=None, forbid=False, cr_count=count,
                     local=None, inside=False, square_flags=-1, killed=False)
    if count:
        return unchanged
    count = CRUSHER_HIT_COUNT
    vx, _, vz = case['velocity']
    if vx or vz:
        branch = 'velocity'
        grid_x = (case['frog_t'][0] - grid['base_x']) >> 8
        grid_z = (case['frog_t'][2] - grid['base_z']) >> 8
        if abs(vx) > abs(vz):
            dx, dz, direction = (-1, 0, FROG_DIRECTION_W) if vx > 0 else (1, 0, FROG_DIRECTION_E)
        else:
            dx, dz, direction = (0, -1, FROG_DIRECTION_S) if vz > 0 else (0, 1, FROG_DIRECTION_N)
    else:
        branch = 'default'
        grid_x, grid_z = case['grid_cell']
        reverse = {FROG_DIRECTION_N: (0, -1, FROG_DIRECTION_S), FROG_DIRECTION_E: (-1, 0, FROG_DIRECTION_W),
                   FROG_DIRECTION_S: (0, 1, FROG_DIRECTION_N), FROG_DIRECTION_W: (1, 0, FROG_DIRECTION_E)}
        dx, dz, direction = reverse.get(case['direction'], (0, 0, case['direction']))
    x, z = grid_x + dx, grid_z + dz
    stack_count, index = jungle.stack(grid, x, z)
    out = dict(unchanged, debounced=False, branch=branch, cr_count=count)
    translation = list(case['frog_t'])
    if stack_count and grid['squares'][index]['flags'] & GRID_SQUARE_USABLE:
        height = jungle.square_height(grid, index)
        target_x, target_z = (x << 8) + grid['base_x'] + 0x80, (z << 8) + grid['base_z'] + 0x80
        position = case['fr_pos']
        if case['mode'] >= FROG_MODE_USER:
            target = [target_x, height, target_z]
            velocity = [c_div(s32((target[i] << 16) - position[i]), FROG_JUMP_TIME) for i in range(3)]
            out.update(happened=True, bounce='user', grid=[x, z], direction=case['direction'], square=index,
                       mode=case['mode'], frog_count=FROG_JUMP_TIME, target=target, velocity=velocity,
                       cr_count=CRUSHER_USER_COUNT)
        else:
            fall = (SYSTEM_GRAVITY * (CRUSHER_JUMP_COUNT + 1)) >> 1
            vy = s32(c_div(s32((case['fr_y'] - translation[1]) << 16), CRUSHER_JUMP_COUNT + 1) - fall)
            new_vx = c_div(s32((target_x << 16) - position[0]), CRUSHER_JUMP_COUNT)
            new_vz = c_div(s32((target_z << 16) - position[2]), CRUSHER_JUMP_COUNT)
            translation[0] = s32(translation[0] + (new_vx >> 15))
            translation[2] = s32(translation[2] + (new_vz >> 15))
            out.update(happened=True, bounce='normal', grid=[x, z], direction=direction, square=index,
                       flags_added=FROG_JUMP_TO_LAND | FROG_JUMP_FROM_COLLPRIM, mode=FROG_MODE_JUMPING,
                       frog_count=CRUSHER_JUMP_COUNT, target=[target_x, None, target_z],
                       velocity=[new_vx, vy, new_vz], old_y=case['fr_y'], forbid=True)
    out['translation'] = list(translation)
    out['velocity_after'] = list(out['velocity'] if out['velocity'] is not None else case['velocity'])
    if form['datas']:
        entity = case['entity_matrix']
        svec = [s16(translation[i] - entity[9 + i]) for i in range(3)]
        local = transpose_apply(entity, svec)
        x_end = form['xofs'] + (form['xnum'] << 8)
        z_end = form['zofs'] + (form['znum'] << 8)
        inside = (local[0] > form['xofs'] and x_end > local[0] and local[2] > form['zofs'] and z_end > local[2]
                  and form['height'] <= local[1] <= form['max_y'])
        out.update(local=local, inside=inside)
        if inside:
            flags = form['grid_flags'][((local[2] - form['zofs']) >> 8) * form['xnum'] + ((local[0] - form['xofs']) >> 8)]
            out.update(square_flags=flags, killed=bool(flags & GRID_SQUARE_DEADLY))
    if out['killed']:
        mode = out['mode'] if out['mode'] is not None else case['mode']
        if mode != FROG_MODE_JUMPING or not (case['frog_flags'] | out['flags_added']) & FROG_JUMP_TO_LAND:
            out['velocity_after'] = [0, 0, 0]
    return out


def rat_timing(speed, targets):
    """ENTSTRSwpCreateRat: per-frame speed, floor-sqrt phase times, <<4 velocities, XZ distances and sine steps."""
    speed = s16(speed)
    targets = [[s16(v) for v in t] for t in targets]

    def phase(a, b, divisor):
        squares = [(b[i] - a[i]) * (b[i] - a[i]) for i in range(3)]
        time = c_div(desert.isqrt_long(s32(sum(squares))), divisor)
        if time == 0:
            raise ValueError('rat phase with zero duration')
        velocity = [c_div(s32((b[i] - a[i]) << 4), time) for i in range(3)]
        return time, velocity, desert.isqrt_long(s32(squares[0] + squares[2]))

    run_speed = c_div(speed, 30)
    if run_speed == 0:
        raise ValueError('rat run speed of zero divides by zero')
    jump1_time, jump1_velocity, jump1_dist = phase(targets[0], targets[1], 30)
    run_time, run_velocity, _ = phase(targets[1], targets[2], run_speed)
    jump2_time, jump2_velocity, jump2_dist = phase(targets[2], targets[3], 30)
    return dict(run_speed=run_speed, jump1_time=jump1_time, jump1_velocity_4=jump1_velocity,
                jump1_sine_step=c_div(2048, jump1_time), jump1_dist=jump1_dist, run_time=run_time,
                run_velocity_4=run_velocity, jump2_time=jump2_time, jump2_velocity_4=jump2_velocity,
                jump2_sine_step=c_div(2048, jump2_time), jump2_dist=jump2_dist)


def rat_cycle(case):
    """ENTSTRSwpCreateRat/UpdateRat: <<4 positions, sine-arc jumps, a 24-tick roll, the run and the splash."""
    targets = [[s16(v) for v in t] for t in case['targets']]
    lengths = case['lengths']
    resolved = rat_timing(case['speed'], targets)
    jump1_time, jump1_velocity, jump1_sine = resolved['jump1_time'], resolved['jump1_velocity_4'], resolved['jump1_sine_step']
    run_time, run_velocity = resolved['run_time'], resolved['run_velocity_4']
    jump2_time, jump2_velocity, jump2_sine = resolved['jump2_time'], resolved['jump2_velocity_4'], resolved['jump2_sine_step']
    position = [s32(v << 4) for v in targets[0]]
    previous_y, mode, count, sines, splashed = targets[0][1], RAT_RESTART, 0, [0, 0], False
    action, one_shot, cel = RAT_ANIM_RUN, False, -1
    colour, ambient = None, None

    def set_action(next_action, single):
        nonlocal action, one_shot, cel
        action, one_shot, cel = next_action, single, -1

    def row(tick, splash):
        return dict(tick=tick, mode=mode, count=count, position_4=list(position), previous_y=previous_y,
                    sine_positions=list(sines), splashed=splashed, splash=splash, action=action, one_shot=one_shot,
                    cel=cel, translation=[v >> 4 for v in position], colour_scale=colour, ambient=ambient)

    rows = [row(0, False)]
    for tick in range(1, case['ticks'] + 1):
        splash = False
        if mode == RAT_INIT_FIRST_JUMP:
            set_action(RAT_ANIM_JUMP, True)
            count, sines, previous_y, mode = 0, [0, 0], position[1], RAT_JUMP1
        elif mode == RAT_JUMP1:
            position[0] = s32(position[0] + jump1_velocity[0])
            position[1] = s32(previous_y + jump1_velocity[1])
            position[2] = s32(position[2] + jump1_velocity[2])
            previous_y = position[1]
            position[1] = s32(position[1] - (((rsin(sines[0]) * 250) >> 12) << 4))
            sines[0] = s32(sines[0] + jump1_sine)
            count = (count + 1) & U16
            if count == jump1_time:
                mode = RAT_INIT_ROLL
        elif mode == RAT_INIT_ROLL:
            set_action(RAT_ANIM_ROLL, True)
            count, mode = 0, RAT_ROLL
        elif mode == RAT_ROLL:
            count = (count + 1) & U16
            if count == RAT_ROLL_TICKS:
                set_action(RAT_ANIM_RUN, False)
                count, mode = 0, RAT_RUN
        elif mode == RAT_RUN:
            position = [s32(position[i] + run_velocity[i]) for i in range(3)]
            count = (count + 1) & U16
            if count == run_time:
                set_action(RAT_ANIM_JUMP, True)
                count, previous_y, mode = 0, position[1], RAT_JUMP2
        elif mode == RAT_JUMP2:
            position[0] = s32(position[0] + jump2_velocity[0])
            position[1] = s32(previous_y + jump2_velocity[1])
            position[2] = s32(position[2] + jump2_velocity[2])
            previous_y = position[1]
            position[1] = s32(position[1] - (((rsin(sines[1]) * 250) >> 12) << 4))
            if (position[1] >> 4) >= RAT_SPLASH_Y and not splashed:
                splashed, splash = True, True
                colour, ambient = [0x80, 0x80, 0x80], [0xff, 0, 0xff]
            sines[1] = s32(sines[1] + jump2_sine)
            count = (count + 1) & U16
            if count == jump2_time:
                mode = RAT_RESTART
        elif mode == RAT_RESTART:
            position = [s32(v << 4) for v in targets[0]]
            colour, ambient, splashed = [0x80, 0x80, 0x80], [0xff, 0xff, 0xff], False
            previous_y, mode = position[1], RAT_INIT_FIRST_JUMP
        cel = desert.step_cel(cel, lengths[action], one_shot)
        rows.append(row(tick, splash))
    return dict(resolved=resolved, rows=rows,
                restart_ticks=[r['tick'] for r in rows[1:] if rows[r['tick'] - 1]['mode'] == RAT_RESTART],
                splash_ticks=[r['tick'] for r in rows if r['splash']])


def slug_action(case):
    """ENTSTRSwpCreateSlug: only sl_motion_type == SWAMP_SLUG_MOTION_TYPE_CURVY selects the bend action."""
    if case['motion_type'] == SLUG_MOTION_CURVY and len(case['lengths']) < 2:
        raise ValueError('a curvy slug needs its bend action')
    return dict(action=SLUG_ANIM_CURVY if (case['motion_type'] & 0xffffffff) == SLUG_MOTION_CURVY else SLUG_ANIM_NORMAL)


def rot_matrix(angles):
    """RotMatrix for the single-axis angle sets used here: one rounded axis rotation."""
    nonzero = [axis for axis in range(3) if angles[axis] & 0xfff]
    if len(nonzero) > 1:
        raise ValueError('only single-axis rotations are modelled')
    if not nonzero:
        return list(desert.IDENTITY)
    axis = nonzero[0]
    cosine, sine = paths.trig(angles[axis])
    if axis == 0:
        return [4096, 0, 0, 0, cosine, -sine, 0, sine, cosine]
    if axis == 1:
        return [cosine, 0, sine, 0, 4096, 0, -sine, 0, cosine]
    return [cosine, -sine, 0, sine, cosine, 0, 0, 0, 4096]


def weir_matrix(matrix):
    """ENTSTRSwpCreateWeir: MRRotMatrix(0, 0, SWP_WEIR_ROTATION) overwrites the authored rotation, not t."""
    return [s16(v) for v in rot_matrix([0, 0, WEIR_ROTATION])] + list(matrix[9:12])


class Script:
    """The frozen UpdateScriptInfo loop for the instructions the Swamp barrels and weir use."""

    def __init__(self, programs, root, payload, entity_type, authored):
        self.programs, self.program, self.cursor = programs, root, 0
        self.root, self.payload, self.entity_type = root, payload, entity_type
        self.authored = list(authored)
        self.matrix = list(authored)
        self.registers = [0] * REGISTER_SLOTS
        self.loop = None
        self.saved = None
        self.timer = 0
        self.offsets, self.deltas, self.destinations, self.counts = [0] * 3, [0] * 3, [0] * 3, [0] * 3
        self.angles, self.angular_deltas, self.angular_destinations, self.angular_counts = [0] * 3, [0] * 3, [0] * 3, [0] * 3
        self.callbacks = {}
        self.moving_sound = []
        self.pop_allocated = False
        self.colours, self.ambient, self.no_fade = None, None, False
        self.active = True

    def update(self, carried):
        """One source update: instructions, deviation, rotation, transform, callbacks and timer."""
        out = dict(sounds=[], ejections=[], pop=False, deaths=[])
        ended = False
        for _ in range(4096):
            words = self.programs[self.program]
            opcode = words[self.cursor]
            args = words[self.cursor + 1:self.cursor + WIDTHS[opcode]]
            following = self.cursor + WIDTHS[opcode]
            name = exe_tables.OPCODES[opcode][0]
            stop = False

            def value(mode, operand):
                return self.registers[operand] if mode == REGISTERS else operand

            if name == 'REGISTER_CALLBACK':
                self.callbacks[args[0]] = (args[1], args[2], args[3])
            elif name == 'PREPARE_REGISTERS':
                offset, count = args
                for index in range(count):
                    self.registers[index] = int.from_bytes(self.payload[offset + 4 * index:offset + 4 * index + 4],
                                                           'little', signed=True)
            elif name == 'SET_ENTITY_TYPE':
                self.entity_type = args[0]
            elif name == 'SET_TIMER':
                self.timer = value(*args) & U16
            elif name == 'WAIT_UNTIL_TIMER':
                if not self.timer >= value(*args):
                    following, stop = self.cursor, True
            elif name == 'SETLOOP':
                self.loop = following
            elif name == 'ENDLOOP':
                following, stop = self.loop, True
            elif name == 'RESTART':
                self.program, following = self.root, 0
            elif name == 'END':
                following, stop, ended = self.cursor, True, True
            elif name == 'DEVIATE':
                registers, coord, dest, delta, count = args
                sign = 1
                if coord > COORD_Z:
                    coord, sign = coord - 3, -1
                if registers == REGISTERS:
                    dest, delta = self.registers[dest], self.registers[delta]
                self.destinations[coord], self.deltas[coord], self.counts[coord] = dest, sign * delta, count
            elif name == 'RETURN_DEVIATE':
                registers, coord, delta = args
                sign = 1
                if coord > COORD_Z:
                    coord, sign = coord - 3, -1
                if registers == REGISTERS:
                    delta = self.registers[delta]
                self.destinations[coord], self.deltas[coord], self.counts[coord] = 0, sign * delta, TIME_INFINITE
            elif name == 'WAIT_DEVIATED':
                if any(self.counts):
                    following, stop = self.cursor, True
            elif name == 'ROTATE':
                coord, dest, delta, count = args
                self.angular_destinations[coord], self.angular_deltas[coord], self.angular_counts[coord] = dest, delta, count
            elif name == 'WAIT_UNTIL_ROTATED':
                if any(self.angular_counts):
                    following, stop = self.cursor, True
            elif name == 'SCRIPT_IF':
                branch, condition, target, _ = args
                if condition != SAFE_FROG:
                    raise ValueError('only the SAFE_FROG condition is modelled')
                if carried:
                    if branch == GOSUB_SCRIPT:
                        self.saved = (self.program, following, self.loop)
                    self.program, following, self.loop = target, 0, None
            elif name == 'PLAY_MOVING_SOUND':
                if not self.moving_sound:
                    self.moving_sound = [args[0], value(args[1], args[2]), value(args[1], args[3])]
            elif name == 'PLAY_SOUND':
                out['sounds'].append(s16(args[0]))
            elif name == 'EJECT_FROG':
                if carried:
                    out['ejections'].append([value(args[0], args[1]), value(args[0], args[2])])
            elif name == 'POP':
                if not self.pop_allocated:
                    self.pop_allocated, out['pop'] = True, True
            elif name == 'KILL_SAFE_FROG':
                if carried:
                    out['deaths'].append(args[0])
                    if args[1]:
                        out['sounds'].append(s16(args[1]))
            else:
                raise ValueError(f'unmodelled instruction {name}')
            self.cursor = following
            if stop:
                break
        else:
            raise ValueError('non-yielding script')
        for axis in range(3):
            self.offsets[axis], self.deltas[axis], self.counts[axis] = self._advance(
                self.offsets[axis], self.deltas[axis], self.counts[axis], self.destinations[axis], False)
            self.angles[axis], self.angular_deltas[axis], self.angular_counts[axis] = self._advance(
                self.angles[axis], self.angular_deltas[axis], self.angular_counts[axis],
                self.angular_destinations[axis], True)
        if self.entity_type == ENTITY_TYPE_MATRIX:
            if any(self.angles):
                self.matrix[:9] = desert.multiply(rot_matrix(self.angles), self.authored[:9])
            for axis in range(3):
                self.matrix[9 + axis] = s32(self.authored[9 + axis] + self.offsets[axis])
        for slot in sorted(self.callbacks):
            callback, condition, kind = self.callbacks[slot]
            if callback != 2 or condition != NO_CONDITION or kind != CALLBACK_ALWAYS or self.entity_type != ENTITY_TYPE_MATRIX:
                raise ValueError('only the static SCRIPT_CB_DIVE_COLOUR_CHANGE branch is modelled')
            height = s32(self.matrix[10] - self.authored[10]) >> 2
            self.colours = [max(0, 0x40 - height), max(0, 0x40 - height), max(0, 0x60 - height)]
            self.ambient, self.no_fade = [0x20, 0xf0, 0xa0], True
        self.timer = (self.timer + 1) & U16
        if ended:
            if self.saved is not None:
                self.program, self.cursor, self.loop = self.saved
                self.saved = None
            else:
                self.active = False
        return out

    @staticmethod
    def _advance(value, delta, count, destination, angular):
        if not count:
            return value, delta, count
        value = s16(value + (delta if angular else delta >> WORLD_SHIFT))
        if count < 0:
            if (delta > 0 and value >= destination) or (delta < 0 and value <= destination):
                return (destination & 0xfff) if angular else destination, 0, 0
            return value, delta, count
        if angular:
            value &= 0xfff
        count = s16(count - 1)
        return value, (0 if count == 0 else delta), count


def words(*instructions):
    """Assemble frozen-source instructions by FrogLord opcode name."""
    out = []
    for name, *args in instructions:
        opcode = OPCODES[name]
        if len(args) + 1 != WIDTHS[opcode]:
            raise ValueError(f'{name} takes {WIDTHS[opcode] - 1} operands')
        out += [opcode, *args]
    return out


def frozen_programs(script_names, callback_names):
    """ent_swp.c script_swp_nuclear_barrel_waiting/ejecting, script_swp_bobbing_waste_barrel and script_swp_weir_rotate."""
    ids = {name: script_names.index(name) for name in (
        'SCRIPT_SWP_NUCLEAR_BARLLEL_WAITING', 'SCRIPT_SWP_NUCLEAR_BARLLEL_EJECTING',
        'SCRIPT_SWP_BOBBING_WASTE_BARREL', 'SCRIPT_SWP_WEIR_ROTATE')}
    dive = callback_names.index('SCRIPT_CB_DIVE_COLOUR_CHANGE')
    waiting = words(('PREPARE_REGISTERS', PATH_INFO_SIZE, 2), ('SETLOOP',),
                    ('SCRIPT_IF', GOSUB_SCRIPT, SAFE_FROG, ids['SCRIPT_SWP_NUCLEAR_BARLLEL_EJECTING'], 0),
                    ('PLAY_MOVING_SOUND', SOUNDS['SWP_NUCLEAR_BARREL_GEIGER'], NO_REGISTERS, 512, 1536),
                    ('ENDLOOP',), ('RESTART',))
    ejecting = words(('PLAY_SOUND', SOUNDS['SWP_NUCLEAR_BARREL_EXPLODE']), ('EJECT_FROG', REGISTERS, 0, 1),
                     ('POP',), ('END',))
    bobbing = words(('REGISTER_CALLBACK', CALLBACK_1, dive, NO_CONDITION, CALLBACK_ALWAYS),
                    ('PREPARE_REGISTERS', MATRIX_SIZE, 1), ('SET_ENTITY_TYPE', ENTITY_TYPE_MATRIX),
                    ('SET_TIMER', NO_REGISTERS, 0), ('WAIT_UNTIL_TIMER', REGISTERS, 0), ('SETLOOP',),
                    ('DEVIATE', NO_REGISTERS, COORD_Y, 0x120, 0x8 << 8, TIME_INFINITE), ('WAIT_DEVIATED',),
                    ('KILL_SAFE_FROG', FROG_ANIMATION_DROWN, SOUNDS['GEN_FROG_DROWN1']),
                    ('RETURN_DEVIATE', NO_REGISTERS, COORD_Y, -0x8 << 8), ('WAIT_DEVIATED',),
                    ('ENDLOOP',), ('RESTART',))
    weir = words(('SET_ENTITY_TYPE', ENTITY_TYPE_MATRIX), ('SETLOOP',),
                 ('ROTATE', COORD_X, 0x1000, 0x20, TIME_INFINITE), ('WAIT_UNTIL_ROTATED',), ('ENDLOOP',), ('RESTART',))
    return ids, {ids['SCRIPT_SWP_NUCLEAR_BARLLEL_WAITING']: waiting, ids['SCRIPT_SWP_NUCLEAR_BARLLEL_EJECTING']: ejecting,
                 ids['SCRIPT_SWP_BOBBING_WASTE_BARREL']: bobbing, ids['SCRIPT_SWP_WEIR_ROTATE']: weir}


def payload_bytes(size, words_at):
    data = bytearray(size)
    for offset, value in words_at:
        data[offset:offset + 4] = (value & 0xffffffff).to_bytes(4, 'little')
    return list(data)


def register_setup(case):
    """ENTSCR_PREPARE_REGISTERS: si_registers[i] = MR_LONG at entity data + offset, for count words."""
    offset, count, payload = case['offset'], case['count'], case['payload']
    defined = 1 <= count <= REGISTER_SLOTS and len(payload) >= offset + 4 * count
    registers = [int.from_bytes(bytes(payload[offset + 4 * i:offset + 4 * i + 4]), 'little', signed=True)
                 for i in range(count)] if defined else []
    return dict(source_defined=defined, registers=registers)


def script_timeline(case, programs):
    script = Script({k: programs[k] for k in case['programs']}, case['root'], bytes(case['payload']),
                    case['entity_type'], case['authored'])
    rows = []
    for tick in range(1, case['ticks'] + 1):
        carried = tick in case['carry_ticks']
        result = script.update(carried)
        rows.append(dict(tick=tick, carried=carried, program=script.program, cursor=script.cursor, timer=script.timer,
                         registers=list(script.registers), deviation=list(script.offsets), remaining=list(script.counts),
                         angles=list(script.angles), angle_counts=list(script.angular_counts),
                         matrix=list(script.matrix), moving_sound=list(script.moving_sound), colours=script.colours,
                         ambient=script.ambient, no_fade=script.no_fade, **result))
    return dict(rows=rows)


def local_align(case):
    """ENTSTRUpdateMovingMOF ENTITY_LOCAL_ALIGN: X from the previous m[2][0], normalised, Y = Z × X."""
    z = list(case['tangent'])
    x = [0, 0, 4096] if abs(case['previous'][6]) > 0x800 else [4096, 0, 0]
    x = paths.normalised(x)
    y = desert.outer12(z, x)
    rotation = [s16(v) for row in range(3) for v in (x[row], y[row], z[row])]
    return dict(x_axis=x, matrix=rotation + list(case['position']))


def squirt_cases():
    near = [-100, -2000, 140]
    sets = [
        dict(matrix=desert.IDENTITY + near, time_delay=3, drop_time=7, target=[-100, -760, 140],
             frog=[near[0], near[1], near[2] + 1535], ticks=40),
        dict(matrix=desert.IDENTITY + near, time_delay=3, drop_time=7, target=[-100, -760, 140],
             frog=[near[0], near[1], near[2] + 1536], ticks=20),
        dict(matrix=desert.IDENTITY + [200, -1000, -100], time_delay=0, drop_time=1, target=[-300, -50, -260],
             frog=None, ticks=12),
        dict(matrix=[0, 0, 4096, 0, 4096, 0, -4096, 0, 0, -640, -1500, 900], time_delay=-2, drop_time=7,
             target=[-650, -300, -900], frog=[-600, -900, 300], ticks=36),
        dict(matrix=desert.IDENTITY + [50, -900, 75], time_delay=5, drop_time=-3, target=[50, -100, 75],
             frog=[50, -900, 75], ticks=16),
        dict(matrix=desert.IDENTITY + [10, -1200, -30], time_delay=1, drop_time=45, target=[10, -400, -30],
             frog=[0, -900, -20], ticks=100),
    ]
    return [dict(input=case, expected=squirt_timeline(case)) for case in sets]


def crusher_cases():
    turn = [0, 0, -4096, 0, 4096, 0, 4096, 0, 0]
    sets = [
        dict(matrix=turn + [512, -400, 2800], speed=512, distance=20, direction=CRUSHER_NORTH, delay=3,
             callback_ticks=[2, 9], ticks=50),
        dict(matrix=desert.IDENTITY + [-300, -800, 100], speed=767, distance=9, direction=CRUSHER_EAST, delay=0,
             callback_ticks=[1], ticks=30),
        dict(matrix=desert.IDENTITY + [100, -600, -100], speed=-600, distance=12, direction=CRUSHER_SOUTH, delay=2,
             callback_ticks=[], ticks=20),
        dict(matrix=desert.IDENTITY + [0, 0, 0], speed=300, distance=5, direction=CRUSHER_WEST, delay=0,
             callback_ticks=[4, 6], ticks=40),
        dict(matrix=desert.IDENTITY + [7, 8, 9], speed=1024, distance=40, direction=4, delay=1,
             callback_ticks=[3], ticks=12),
        dict(matrix=desert.IDENTITY + [1000, -200, -1000], speed=2000, distance=-30, direction=CRUSHER_SOUTH, delay=-1,
             callback_ticks=[], ticks=6),
        dict(matrix=desert.IDENTITY + [0, 0, 0], speed=255, distance=0, direction=CRUSHER_EAST, delay=0,
             callback_ticks=[], ticks=6),
    ]
    return [dict(input=case, expected=crusher_timeline(case)) for case in sets]


def press_cases():
    sets = [
        dict(matrix=desert.IDENTITY + [600, -2700, 300], speed=1024, distance=30, direction=PRESS_UP, delay=2,
             frog=[600, 0, 300], carry_ticks=[], ticks=50),
        dict(matrix=desert.IDENTITY + [600, -2700, 300], speed=1024, distance=30, direction=PRESS_UP, delay=2,
             frog=[600, -2000, 300], carry_ticks=[], ticks=50),
        dict(matrix=desert.IDENTITY + [-40, -500, 80], speed=-768, distance=12, direction=PRESS_DOWN, delay=0,
             frog=None, carry_ticks=[], ticks=12),
        dict(matrix=desert.IDENTITY + [-40, -500, 80], speed=768, distance=12, direction=PRESS_DOWN, delay=0,
             frog=[-40, -500, 80], carry_ticks=[11, 12, 13, 14], ticks=30),
        dict(matrix=desert.IDENTITY + [0, -100, 0], speed=4369, distance=1024, direction=PRESS_UP, delay=1200,
             frog=[0, -100, 1400], carry_ticks=[], ticks=1330),
        dict(matrix=desert.IDENTITY + [3, 4, 5], speed=512, distance=4, direction=2, delay=0,
             frog=[3, 4, 5], carry_ticks=[], ticks=6),
    ]
    return [dict(input=case, expected=press_timeline(case)) for case in sets]


def callback_grid():
    """Jungle's 6x6 bounce grid; its stacks hold flat, raised, sunken, water, unusable and empty squares."""
    return jungle.bounce_grid()


def callback_cases():
    grid = callback_grid()
    centre = [-768 + 2 * 256 + 0x80, -768 + 2 * 256 + 0x80]
    deadly = [GRID_SQUARE_USABLE, GRID_SQUARE_DEADLY | GRID_SQUARE_USABLE, GRID_SQUARE_DEADLY, GRID_SQUARE_USABLE,
              GRID_SQUARE_DEADLY, GRID_SQUARE_USABLE]
    form = dict(datas=1, xofs=-256, zofs=-384, xnum=2, znum=3, max_y=50, height=-200, grid_flags=deadly)
    entity = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, centre[0], -60, centre[1]]
    base = dict(grid=grid, form=form, entity_matrix=entity, count=0, mode=FROG_MODE_JUMPING, frog_flags=0, direction=0,
                grid_cell=[1, 4], fr_y=-40, frog_t=[centre[0] + 9, -61, centre[1] - 13],
                fr_pos=[(centre[0] + 9) << 16 | 0x4000, -(61 << 16) + 5, ((centre[1] - 13) << 16) - 0x123],
                velocity=[0, 0, 0])
    still = dict(base, velocity=[0, 0, 0], direction=FROG_DIRECTION_N, grid_cell=[5, 3])

    def at(local, **extra):
        t = [entity[9] + local[0], entity[10] + local[1], entity[11] + local[2]]
        return dict(still, frog_t=t, fr_pos=[t[0] << 16, t[1] << 16, t[2] << 16], **extra)

    turned = [0, 0, 4096, 0, 4096, 0, -4096, 0, 0, centre[0], -60, centre[1]]
    sets = [
        dict(base, velocity=[0x30000, 0x1000, 0x1000]),
        dict(base, velocity=[-0x30000, 0, 0x2ffff]),
        dict(base, velocity=[0x1000, -5, 0x30000]),
        dict(base, velocity=[0x1000, 0, -0x30000]),
        dict(base, velocity=[0x20000, 0, -0x20000]),
        dict(base, velocity=[-7, 0, 7]),
        dict(base, velocity=[0, 0x50000, 0], direction=FROG_DIRECTION_E, grid_cell=[3, 2]),
        dict(base, direction=FROG_DIRECTION_N, grid_cell=[2, 3]),
        dict(base, direction=7, grid_cell=[2, 2]),
        dict(base, velocity=[0x30000, 0, 0], mode=FROGUSER_MODE_BOUNCE),
        dict(base, velocity=[0, 0, -0x30000], mode=FROGUSER_MODE_BOUNCE, frog_t=[centre[0], -61, centre[1] - 256]),
        dict(base, velocity=[0, 0, 0x10000], frog_t=[-768 + 0 * 256 + 0x80, -61, -768 + 3 * 256 + 0x80]),
        dict(base, velocity=[0, 0, 0x10000], frog_t=[-768 + 1 * 256 + 0x80, -61, -768 + 2 * 256 + 0x80]),
        dict(base, velocity=[-0x10000, 0, 0], frog_t=[-768 + 4 * 256 + 0x80, 0, -768 + 2 * 256 + 0x80]),
        dict(base, count=3, velocity=[0x30000, 0, 0]),
        dict(base, count=5),
        at([-100, -1, 100], count=1),
        at([-100, -1, 100]),
        at([100, -1, 100]),
        at([-256, -1, 0]),
        at([-255, -1, 0]),
        at([255, -1, -384]),
        at([255, -1, 383]),
        at([0, 50, -300]),
        at([0, 51, -300]),
        at([0, -200, -300]),
        at([0, -201, -300]),
        at([100, -1, 200], entity_matrix=turned),
        at([-100, -1, 100], form=dict(form, datas=0)),
        dict(base, velocity=[0, 0, 0x10000], frog_t=[-400, -61, -100], fr_pos=[-400 << 16, -61 << 16, -100 << 16],
             entity_matrix=list(desert.IDENTITY) + [-300, -60, -200]),
        dict(base, velocity=[0, 0, 0x10000], frog_t=[-400, -61, -100], fr_pos=[-400 << 16, -61 << 16, -100 << 16],
             entity_matrix=list(desert.IDENTITY) + [-300, -60, -200], frog_flags=FROG_JUMP_TO_LAND),
    ]
    out = []
    for case in sets:
        if 'fr_pos' in case and case['frog_t'] != base['frog_t']:
            case = dict(case, fr_pos=[case['frog_t'][0] << 16, case['frog_t'][1] << 16, case['frog_t'][2] << 16])
        out.append(dict(input=case, expected=crusher_callback(case)))
    return out


def rat_cases():
    sets = [
        dict(speed=256, targets=[[-1000, -1700, -2000], [-1000, -1200, -650], [-1000, -1200, 500], [-998, 200, 1300]],
             lengths=[12, 18, 24], ticks=545),
        dict(speed=320, targets=[[500, -1500, 300], [520, -1100, -800], [520, -1100, -1800], [530, 150, -2400]],
             lengths=[10, 16, 20], ticks=430),
        dict(speed=-95, targets=[[0, -600, 0], [0, -600, 1170], [-90, -600, 1170], [-90, -300, 3000]],
             lengths=[4, 30, 6], ticks=150),
    ]
    return [dict(input=case, expected=rat_cycle(case)) for case in sets]


def slug_cases():
    sets = [dict(motion_type=0, lengths=[6, 9]), dict(motion_type=1, lengths=[6, 9]), dict(motion_type=2, lengths=[6, 9]),
            dict(motion_type=0, lengths=[6])]
    return [dict(input=case, expected=slug_action(case)) for case in sets]


def weir_cases(programs, ids):
    overrides = []
    for matrix in ([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 10, -20, 30],
                   [4096, 0, 0, 0, 0, -4096, 0, 4096, 0, -1000, -500, 2000],
                   [0, 4096, 0, 0, 0, -4096, -4096, 0, 0, 70000, -1, -70000]):
        overrides.append(dict(input=dict(matrix=matrix), expected=dict(matrix=weir_matrix(matrix))))
    authored = weir_matrix([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -1600, -1000, 2900])
    root = ids['SCRIPT_SWP_WEIR_ROTATE']
    case = dict(programs=[root], root=root, payload=[0] * 32, entity_type=ENTITY_TYPE_PATH, authored=authored,
                carry_ticks=[], ticks=262)
    return dict(overrides=overrides, rotation=[dict(input=case, expected=script_timeline(case, programs))])


def register_cases(programs, ids):
    path = PATH_INFO_SIZE
    setups = []
    for layout, offset in (('path', PATH_INFO_SIZE), ('matrix', MATRIX_SIZE)):
        for count in range(1, REGISTER_SLOTS + 1):
            payload = payload_bytes(offset + 4 * count, [(offset + 4 * i, (-1) ** i * (1000 * i + 17) - 3) for i in range(count)])
            setups.append(dict(layout=layout, offset=offset, count=count, payload=payload))
        setups.append(dict(layout=layout, offset=offset, count=2, payload=payload_bytes(offset + 7, [(offset, 5)])))
        setups.append(dict(layout=layout, offset=offset, count=7, payload=payload_bytes(offset + 28, [(offset, 5)])))
    setup_cases = [dict(input=case, expected=register_setup(case)) for case in setups]
    nuclear = ids['SCRIPT_SWP_NUCLEAR_BARLLEL_WAITING']
    bobbing = ids['SCRIPT_SWP_BOBBING_WASTE_BARREL']
    timelines = [
        dict(name='nuclear_barrel', behavior='NUCLEAR_BARREL', programs=[nuclear, ids['SCRIPT_SWP_NUCLEAR_BARLLEL_EJECTING']],
             root=nuclear, payload=payload_bytes(path + 8, [(path, 2), (path + 4, 10)]), entity_type=ENTITY_TYPE_PATH,
             authored=list(desert.IDENTITY) + [0, 0, 0], carry_ticks=[4, 5, 9], ticks=12),
        dict(name='nuclear_barrel_negative', behavior='NUCLEAR_BARREL',
             programs=[nuclear, ids['SCRIPT_SWP_NUCLEAR_BARLLEL_EJECTING']], root=nuclear,
             payload=payload_bytes(path + 8, [(path, -3), (path + 4, 15)]), entity_type=ENTITY_TYPE_PATH,
             authored=list(desert.IDENTITY) + [0, 0, 0], carry_ticks=[1], ticks=3),
        dict(name='bobbing_barrel', behavior='DYNAMIC', programs=[bobbing], root=bobbing,
             payload=payload_bytes(MATRIX_SIZE + 4, [(MATRIX_SIZE, 5)]), entity_type=ENTITY_TYPE_PATH,
             authored=[0, 0, 4096, 0, 4096, 0, -4096, 0, 0, -2600, -1000, 2100],
             carry_ticks=[20, 40, 41, 42, 43, 60], ticks=160),
        dict(name='bobbing_barrel_no_delay', behavior='DYNAMIC', programs=[bobbing], root=bobbing,
             payload=payload_bytes(MATRIX_SIZE + 4, [(MATRIX_SIZE, 0)]), entity_type=ENTITY_TYPE_PATH,
             authored=list(desert.IDENTITY) + [0, 0, 0], carry_ticks=[], ticks=40),
    ]
    return dict(setup=setup_cases,
                timeline=[dict(input=case, expected=script_timeline(case, programs)) for case in timelines],
                programs={str(k): v for k, v in sorted(programs.items())})


def local_align_cases():
    sets = [
        dict(tangent=[4096, 0, 0], position=[10, 0, 0], previous=[4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]),
        dict(tangent=[4096, 0, 0], position=[10, 0, 0], previous=[0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 0, 0, 0]),
        dict(tangent=[0, 0, 4096], position=[-5, 7, 300], previous=[4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]),
        dict(tangent=[0, 0, 4096], position=[-5, 7, 300], previous=[0, 0, 4096, 0, 4096, 0, 0x800, 0, 0, 0, 0, 0]),
        dict(tangent=[0, 0, -4096], position=[0, 0, 0], previous=[0, 0, 4096, 0, 4096, 0, 0x801, 0, 0, 0, 0, 0]),
        dict(tangent=[2896, 0, 2896], position=[100, -50, 100], previous=[2896, 0, 2896, 0, 4096, 0, -2896, 0, 2896, 0, 0, 0]),
        dict(tangent=[2896, 0, -2896], position=[100, -50, 100], previous=[2896, 0, 2896, 0, 4096, 0, -0x801, 0, 2896, 0, 0, 0]),
        dict(tangent=[1200, -3000, 2500], position=[70000, -70000, 3], previous=[4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]),
        dict(tangent=[0, 4096, 0], position=[1, 2, 3], previous=[4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]),
        dict(tangent=[0, 0, 4096], position=[1, 2, 3], previous=[0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 0, 0, 0]),
    ]
    return [dict(input=case, expected=local_align(case)) for case in sets]


def cases():
    """Invent source-boundary inputs; no retail data or game outputs are consumed."""
    sound_ids()
    script_names, subs, _ = exe_tables.name_list('scripts', SCRIPT_LIST, False)
    ids, programs = frozen_programs(script_names, subs['CallbackNames'])
    return dict(squirt_timeline=squirt_cases(), crusher_timeline=crusher_cases(), press_timeline=press_cases(),
                swamp_crusher_callback=callback_cases(), rat_cycle=rat_cases(), slug_action=slug_cases(),
                weir_matrix=weir_cases(programs, ids), script_registers=register_cases(programs, ids),
                local_align=local_align_cases())


def encode(value, depth=0):
    """Indented JSON with each per-tick row, number list and short record on one line."""
    compact = json.dumps(value, separators=(',', ':'))
    if not isinstance(value, (dict, list)) or len(compact) <= 100 or (isinstance(value, dict) and 'tick' in value):
        return compact
    pad, inner = ' ' * depth, ' ' * (depth + 1)
    if isinstance(value, list):
        if all(not isinstance(v, (dict, list)) for v in value):
            return compact
        return '[\n' + ',\n'.join(inner + encode(v, depth + 1) for v in value) + '\n' + pad + ']'
    items = [inner + json.dumps(k) + ':' + encode(v, depth + 1) for k, v in value.items()]
    return '{\n' + ',\n'.join(items) + '\n' + pad + '}'


def main():
    """Verify reproducibility by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = encode(cases()) + '\n'
    if args.write:
        OUTPUT.write_text(text)
    elif OUTPUT.read_text() != text:
        raise SystemExit('Swamp facts differ; use --write only to deliberately regenerate')
    print('Swamp facts verified')


if __name__ == '__main__':
    main()
