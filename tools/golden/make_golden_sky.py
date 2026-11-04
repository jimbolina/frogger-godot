#!/usr/bin/env python3
"""Independent synthetic facts from frozen ENTITY.C/ENTLIB.H triggers, PATH.H, mapdisp.c, gamesys.C and ent_sky.c."""
import argparse
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT
from tools.golden import make_golden_exe_tables as exe_tables
from tools.golden import make_golden_jungle as jungle
from tools.golden import make_golden_paths as paths
from tools.golden import make_golden_swamp as swamp

ROOT = REPO_ROOT
OUTPUT = ROOT / 'tests/golden/synthetic/sky.json'
U32 = 0xffffffff
SOUNDS = {'GEN_FROG_CROAK': 3, 'SKY_HELICOPTER_NOISE': 142, 'SKY_HELIUM_BALLOON_POP': 143,
          'SKY_RUBBER_BALLOON_FART': 148, 'SKY_RUBBER_BALLOON_SQUEAK': 149}
TRIGGER_FREEZE, TRIGGER_REVERSE, TRIGGER_START, TRIGGER_BEGIN = range(4)
TRIGGER_MAX_IDS = 10
TRIGGER_RECORD = 56
MATRIX_SIZE = 32
PATH_INFO_SIZE = 12
THEME_SWP, THEME_SKY, THEME_SUB, THEME_VOL = 7, 8, 9, 10
SKY_MAX_DRIFT = 0xb00
SKY_MAX_DRIFT_POSITION = 0x10000000
FRAME_MODES = ('single_start', 'trigger_collected', 'frog_died', 'play', 'fast_start')
MAX_LOGIC_LOOPS_PER_RENDER = 3
COORD_Y, NEG_COORD_Y = 1, 4
CALLBACK_ONCE, CALLBACK_1 = 0, 0
ENTITY_TYPE_PATH, ENTITY_TYPE_MATRIX = 0, 1
HIT_FROG, DEVIATED, SAFE_FROG, NO_SAFE_FROG = 0, 2, 4, 5
NEW_SCRIPT = 0
NO_REGISTERS, REGISTERS = 0, 1
REGISTER_0, REGISTER_1 = 0, 1
REGISTER_SLOTS = 6

s32 = swamp.s32
words = swamp.words


def sound_ids():
    """Confirm the PC flat sound order from FrogLord's retail name list."""
    names = []
    for line in swamp.SOUND_CFG.read_text(encoding='utf-8').splitlines():
        text = line.split('#', 1)[0].strip()
        if text and not text.startswith('['):
            names.append(text)
    for name, value in SOUNDS.items():
        if names.index(name) != value:
            raise ValueError(f'{name} is flat sound {names.index(name)}, not {value}')


def mr_rand(seed):
    """MR_SYS.H MRrand: u32 seed·0x41c64e6d + 0x3039, returning (seed>>16)&0x7fff."""
    seed = (seed * 0x41c64e6d + 0x3039) & U32
    return seed, (seed >> 16) & 0x7fff


def matrix_bytes(translation):
    """An identity MR_MAT (nine s16, pad, three s32) with the given translation."""
    data = bytearray(MATRIX_SIZE)
    for axis in range(3):
        struct.pack_into('<h', data, 2 * (axis * 3 + axis), 4096)
    struct.pack_into('<3i', data, 20, *translation)
    return data


def trigger_bytes(trigger_type, ids, size, translation=(0, 0, 0)):
    """ENTSTR_TRIGGER: MR_MAT, u32 et_type at 32, ten s16 et_unique_ids at 36..55, then any tail bytes."""
    data = matrix_bytes(translation) + bytearray(max(0, size - MATRIX_SIZE))
    struct.pack_into('<I', data, 32, trigger_type & U32)
    raw = bytearray(TRIGGER_RECORD - 36)
    for index, value in enumerate(ids):
        struct.pack_into('<H', raw, 2 * index, value & 0xffff)
    data[36:TRIGGER_RECORD] = raw
    if size > TRIGGER_RECORD:
        data[TRIGGER_RECORD:size] = bytes((index * 37 + 5) & 0xff for index in range(size - TRIGGER_RECORD))
    return list(data[:size])


def trigger_payload(case):
    """Type and target ids; -1 marks an unused slot and every other s16 reaches the u16 lookup parameter."""
    data = bytes(case['payload'])
    trigger_type = struct.unpack_from('<I', data, 32)[0] if len(data) >= 36 else -1
    defined = len(data) >= TRIGGER_RECORD and 0 <= trigger_type <= TRIGGER_BEGIN
    if not defined:
        return dict(source_defined=False)
    ids = [value if value == -1 else value & 0xffff for value in struct.unpack_from('<10h', data, 36)]
    return dict(source_defined=True, type=trigger_type, ids=ids, translation=list(struct.unpack_from('<3i', data, 20)))


def lookup_id(value):
    """GetNextLiveEntityWithUniqueId(MR_USHORT): the s16 id converts modulo 65536."""
    return value & 0xffff


def target_state(target):
    """Mapload: a path runner is ACTIVE exactly when the entity lacks ENTITY_NO_MOVEMENT."""
    return dict(unique_id=target['unique_id'], stopped=target['stopped'],
                active=(not target['stopped']) if target['has_path'] else None,
                backwards=target.get('backwards', False) if target['has_path'] else None)


def trigger_first_update(case):
    """ENTSTRUpdateTrigger: the first update pauses every listed live target once; absent ids are skipped."""
    live = {target['unique_id']: target_state(target) for target in case['targets']}
    skipped = []
    for value in case['ids']:
        if value == -1:
            continue
        found = live.get(lookup_id(value))
        if found is None:
            skipped.append(lookup_id(value))
            continue
        found['stopped'] = True
        if found['active'] is not None:
            found['active'] = False
    return dict(targets=[live[t['unique_id']] for t in case['targets']], skipped=skipped,
                second_update_unchanged=True)


def trigger_callback(case):
    """TriggerEntityCallback: per-type target changes, then forbid this entity and FROG_JUMP_FROM_COLLPRIM."""
    live = {target['unique_id']: target_state(target) for target in case['targets']}
    trigger_type = case['type']
    for value in case['ids']:
        if value == -1:
            continue
        found = live.get(lookup_id(value))
        if found is None:
            return dict(source_defined=False, reason='target_not_live')
        has_path = found['active'] is not None
        if trigger_type in (TRIGGER_FREEZE, TRIGGER_START):
            found['stopped'] = not found['stopped']
            if has_path:
                found['active'] = not found['stopped']
        elif trigger_type == TRIGGER_REVERSE:
            if not has_path:
                return dict(source_defined=False, reason='reverse_without_path')
            found['backwards'] = False
        elif trigger_type == TRIGGER_BEGIN:
            if found['stopped']:
                found['stopped'] = False
                if has_path:
                    found['active'] = True
    return dict(source_defined=True, targets=[live[t['unique_id']] for t in case['targets']],
                forbid=True, jump_from_collprim=True)


def platform_payload(case):
    """PATH_INFO's six u16 fields; Volcano's VOL_TRIGGERED_PLATFORM adds u32 initial movement at 12."""
    data = bytes(case['payload'])
    if len(data) < PATH_INFO_SIZE:
        return dict(source_defined=False)
    path_id, segment, distance, motion, speed, _ = struct.unpack_from('<6H', data, 0)
    initial = struct.unpack_from('<I', data, 12)[0] if len(data) >= 16 else 0
    return dict(source_defined=True, path_id=path_id, segment_id=segment, segment_dist=distance, motion_type=motion,
                speed=speed, initial_movement=initial, chain_sound=case['theme'] == THEME_VOL)


def normalise_shift(vector):
    """MRNormaliseVEC with the port's rounded float convention, then each axis <<= 3."""
    return [s32(value << 3) for value in paths.normalised(vector)]


def drift_step(state, timer):
    """UpdateSkyLand for THEME_SKY at one Game_timer value; returns the number of rand() draws."""
    position, velocity = state['position'], state['velocity']
    draws = 0
    if not timer & 0x7f:
        if any(abs(position[axis] >> 16) > SKY_MAX_DRIFT for axis in (0, 2)):
            acceleration = [s32(-value) >> 16 for value in position]
        else:
            state['seed'], x = mr_rand(state['seed'])
            state['seed'], z = mr_rand(state['seed'])
            acceleration = [x & 0x3ff, 0, z & 0x3ff]
            draws = 2
        state['acceleration'] = normalise_shift(acceleration)
    elif (timer & 0xff) < 0x60:
        state['velocity'] = [s32(velocity[i] + state['acceleration'][i]) for i in range(3)]
    else:
        state['velocity'] = [s32((value >> 5) * 31) for value in velocity]
    state['position'] = [s32(position[i] + state['velocity'][i]) for i in range(3)]
    for axis in (0, 2):
        state['position'][axis] = min(SKY_MAX_DRIFT_POSITION, max(-SKY_MAX_DRIFT_POSITION, state['position'][axis]))
    return draws


def sky_drift_timeline(case):
    """One UpdateSkyLand per logic tick; plain play advances the timer once per tick unless explicit timers are given.

    A listed clear tick zeroes the drift (LevelStart) before that tick's update.
    """
    state = dict(seed=case['seed'] & U32, position=list(case.get('position', [0, 0, 0])),
                 velocity=list(case.get('velocity', [0, 0, 0])), acceleration=list(case.get('acceleration', [0, 0, 0])))
    rows, total = [], 0
    timers = case.get('timers') or [(case['game_timer_start'] + tick) & U32 for tick in range(case['ticks'])]
    for tick, timer in enumerate(timers):
        cleared = tick in case.get('clear_ticks', [])
        if cleared:
            state.update(position=[0, 0, 0], velocity=[0, 0, 0], acceleration=[0, 0, 0])
        draws = drift_step(state, timer)
        total += draws
        rows.append(dict(tick=tick, game_timer=timer, cleared=cleared, draws=draws,
                         acceleration=list(state['acceleration']), velocity=list(state['velocity']),
                         position=list(state['position']), translation=[value >> 16 for value in state['position']]))
    return dict(rows=rows, rng_state=state['seed'], draw_count=total)


def game_timer_cadence(case):
    """GameMainloopPlayUpdate is the only Game_timer++, once per main-loop frame after its logic updates."""
    timer, seen = case['game_timer_start'] & U32, []
    for frame in case['frames']:
        if frame['mode'] not in FRAME_MODES or not 1 <= frame['logic_ticks'] <= MAX_LOGIC_LOOPS_PER_RENDER:
            raise ValueError(f'unsupported frame {frame}')
        seen.append([timer] * frame['logic_ticks'])
        if frame['mode'] == 'play':
            timer = (timer + 1) & U32
    return dict(per_frame=seen, final_game_timer=timer)


def register_setup(case):
    """ENTSCR_PREPARE_REGISTERS(sizeof(MR_MAT), count): s32 words following the 32-byte matrix."""
    count, payload = case['count'], case['payload']
    defined = 1 <= count <= REGISTER_SLOTS and len(payload) >= MATRIX_SIZE + 4 * count
    registers = list(struct.unpack_from(f'<{count}i', bytes(payload), MATRIX_SIZE)) if defined else []
    return dict(source_defined=defined, count=count, registers=registers)


def frozen_programs(script_names, callback_names):
    """ent_sky.c helicopter, homing bird and both balloon script families, by FrogLord opcode and script names."""
    ids = {name: script_names.index(name) for name in (
        'SCRIPT_SKY_HELICOPTER', 'SCRIPT_SKY_BIRD', 'SCRIPT_SKY_BIRD_HIT_FROG',
        'SCRIPT_SKY_RUBBER_BALLOON_WAITING', 'SCRIPT_SKY_RUBBER_BALLOON_RISING',
        'SCRIPT_SKY_RUBBER_BALLOON_SINKING', 'SCRIPT_SKY_RUBBER_BALLOON_POPPING',
        'SCRIPT_SKY_HELIUM_BALLOON_WAITING', 'SCRIPT_SKY_HELIUM_BALLOON_RISING',
        'SCRIPT_SKY_HELIUM_BALLOON_SINKING', 'SCRIPT_SKY_HELIUM_BALLOON_POPPING')}
    cb = {name: callback_names.index(name) for name in (
        'SCRIPT_CB_SKY_FROG_HELICOPTER', 'SCRIPT_CB_SKY_HOMING_BIRD', 'SCRIPT_CB_SKY_HELIUM_BALLOON')}
    helicopter = words(('REGISTER_CALLBACK', CALLBACK_1, cb['SCRIPT_CB_SKY_FROG_HELICOPTER'], HIT_FROG, CALLBACK_ONCE),
                       ('PREPARE_REGISTERS', MATRIX_SIZE, 2), ('SET_ENTITY_TYPE', ENTITY_TYPE_MATRIX),
                       ('PLAY_MOVING_SOUND', SOUNDS['SKY_HELICOPTER_NOISE'], NO_REGISTERS, 1024, 3072), ('SETLOOP',),
                       ('DEVIATE', REGISTERS, COORD_Y, REGISTER_0, REGISTER_1, -1), ('WAIT_DEVIATED',),
                       ('RETURN_DEVIATE', REGISTERS, NEG_COORD_Y, REGISTER_1), ('WAIT_DEVIATED',),
                       ('ENDLOOP',), ('RESTART',))
    hawk = words(('REGISTER_CALLBACK', CALLBACK_1, cb['SCRIPT_CB_SKY_HOMING_BIRD'], HIT_FROG, CALLBACK_ONCE),
                 ('SET_ENTITY_TYPE', ENTITY_TYPE_PATH), ('PREPARE_REGISTERS', MATRIX_SIZE, 2), ('SET_ACTION', 1),
                 ('SETLOOP',), ('HOME_IN_ON_FROG', REGISTERS, REGISTER_0, REGISTER_1), ('ENDLOOP',), ('RESTART',))
    rubber_popping = words(('POP',), ('PLAY_SOUND', SOUNDS['SKY_RUBBER_BALLOON_FART']), ('EJECT_FROG', NO_REGISTERS, 0, 0),
                           ('NO_COLLISION',), ('END',))
    rubber_rising = words(('RETURN_DEVIATE', NO_REGISTERS, COORD_Y, -0x10 << 8), ('SETLOOP',),
                          ('SCRIPT_IF', NEW_SCRIPT, DEVIATED, ids['SCRIPT_SKY_RUBBER_BALLOON_WAITING'], 0),
                          ('SCRIPT_IF', NEW_SCRIPT, SAFE_FROG, ids['SCRIPT_SKY_RUBBER_BALLOON_SINKING'], 0),
                          ('ENDLOOP',), ('RESTART',))
    rubber_sinking = words(('PLAY_SOUND', SOUNDS['SKY_RUBBER_BALLOON_SQUEAK']),
                           ('DEVIATE', NO_REGISTERS, COORD_Y, 0x400, 0x10 << 8, -1), ('SETLOOP',),
                           ('SCRIPT_IF', NEW_SCRIPT, DEVIATED, ids['SCRIPT_SKY_RUBBER_BALLOON_POPPING'], 0),
                           ('SCRIPT_IF', NEW_SCRIPT, NO_SAFE_FROG, ids['SCRIPT_SKY_RUBBER_BALLOON_RISING'], 0),
                           ('ENDLOOP',), ('RESTART',))
    rubber_waiting = words(('PREPARE_REGISTERS', MATRIX_SIZE, 3), ('SET_ENTITY_TYPE', ENTITY_TYPE_MATRIX),
                           ('APPEAR_ENTITY',), ('CLEAR_DEVIATE',), ('SETLOOP',),
                           ('SCRIPT_IF', NEW_SCRIPT, SAFE_FROG, ids['SCRIPT_SKY_RUBBER_BALLOON_SINKING'], 0),
                           ('ENDLOOP',), ('RESTART',))
    helium_popping = words(('POP',), ('PLAY_SOUND', SOUNDS['GEN_FROG_CROAK']), ('PLAY_SOUND', SOUNDS['SKY_HELIUM_BALLOON_POP']),
                           ('EJECT_FROG', NO_REGISTERS, 0, 0), ('NO_COLLISION',), ('END',))
    helium_rising = words(('CLEAR_DEVIATE',), ('DEVIATE', NO_REGISTERS, COORD_Y, -0x600, -0x10 << 8, -1), ('SETLOOP',),
                          ('SCRIPT_IF', NEW_SCRIPT, DEVIATED, ids['SCRIPT_SKY_HELIUM_BALLOON_POPPING'], 0),
                          ('ENDLOOP',), ('RESTART',))
    helium_sinking = words(('RESTART',))
    helium_waiting = words(('PREPARE_REGISTERS', MATRIX_SIZE, 2), ('SET_ENTITY_TYPE', ENTITY_TYPE_MATRIX),
                           ('REGISTER_CALLBACK', CALLBACK_1, cb['SCRIPT_CB_SKY_HELIUM_BALLOON'], HIT_FROG, CALLBACK_ONCE),
                           ('APPEAR_ENTITY',), ('CLEAR_DEVIATE',), ('SETLOOP',),
                           ('DEVIATE', NO_REGISTERS, COORD_Y, 0, 0x5 << 8, 10), ('WAIT_DEVIATED',),
                           ('DEVIATE', NO_REGISTERS, COORD_Y, 0, -0x5 << 8, 10), ('WAIT_DEVIATED',),
                           ('ENDLOOP',), ('RESTART',))
    programs = {ids['SCRIPT_SKY_HELICOPTER']: helicopter, ids['SCRIPT_SKY_BIRD']: hawk,
                ids['SCRIPT_SKY_RUBBER_BALLOON_WAITING']: rubber_waiting,
                ids['SCRIPT_SKY_RUBBER_BALLOON_RISING']: rubber_rising,
                ids['SCRIPT_SKY_RUBBER_BALLOON_SINKING']: rubber_sinking,
                ids['SCRIPT_SKY_RUBBER_BALLOON_POPPING']: rubber_popping,
                ids['SCRIPT_SKY_HELIUM_BALLOON_WAITING']: helium_waiting,
                ids['SCRIPT_SKY_HELIUM_BALLOON_RISING']: helium_rising,
                ids['SCRIPT_SKY_HELIUM_BALLOON_SINKING']: helium_sinking,
                ids['SCRIPT_SKY_HELIUM_BALLOON_POPPING']: helium_popping}
    return ids, programs


def prepared_count(program):
    """The PREPARE_REGISTERS operands of an assembled program."""
    at = 0
    while at < len(program):
        opcode = program[at]
        if exe_tables.OPCODES[opcode][0] == 'PREPARE_REGISTERS':
            return program[at + 1], program[at + 2]
        at += swamp.WIDTHS[opcode]
    return None


def trigger_cases():
    sets = [
        (TRIGGER_BEGIN, [1632, -1, -1, -1, -1, -1, -1, -1, -1, -1], TRIGGER_RECORD),
        (TRIGGER_FREEZE, [0, 1632, -2, -1, 7, -1, -1, -1, -1, 300], TRIGGER_RECORD),
        (TRIGGER_REVERSE, [-1] * TRIGGER_MAX_IDS, TRIGGER_RECORD),
        (TRIGGER_START, [-32768, 32767, -1, 1, 2, 3, 4, 5, 6, -1], 60),
        (4, [1632] + [-1] * 9, TRIGGER_RECORD),
        (TRIGGER_BEGIN, [1632] + [-1] * 9, TRIGGER_RECORD - 1),
    ]
    cases = []
    for index, (trigger_type, ids, size) in enumerate(sets):
        case = dict(payload=trigger_bytes(trigger_type, ids, size, (100 * index, -200, 300 + index)))
        cases.append(dict(input=case, expected=trigger_payload(case)))
    return cases


def target(unique_id, stopped, has_path, backwards=False):
    return dict(unique_id=unique_id, stopped=stopped, has_path=has_path, backwards=backwards)


def first_update_cases():
    sets = [
        dict(ids=[1632] + [-1] * 9, targets=[target(1632, True, True)]),
        dict(ids=[1632] + [-1] * 9, targets=[target(1632, False, True), target(1633, False, True)]),
        dict(ids=[5, -2, 9, -1, 6, -1, -1, -1, -1, 77],
             targets=[target(5, False, True, True), target(65534, False, False), target(6, True, False),
                      target(8, False, True)]),
        dict(ids=[-1] * TRIGGER_MAX_IDS, targets=[target(1, False, True)]),
        dict(ids=[3, 3, -1, -1, -1, -1, -1, -1, -1, 4], targets=[target(3, False, True), target(4, False, False)]),
    ]
    return [dict(input=case, expected=trigger_first_update(case)) for case in sets]


def callback_cases():
    states = [target(10, False, True), target(11, True, True), target(12, False, True, True), target(13, True, True, True),
              target(14, False, False), target(15, True, False)]
    path_states = states[:4]
    every = [10, 11, 12, 13, 14, 15, -1, -1, -1, -1]
    paths_only = [10, 11, 12, 13, -1, -1, -1, -1, -1, -1]
    sets = [
        dict(type=TRIGGER_FREEZE, ids=every, targets=states),
        dict(type=TRIGGER_START, ids=every, targets=states),
        dict(type=TRIGGER_BEGIN, ids=every, targets=states),
        dict(type=TRIGGER_REVERSE, ids=paths_only, targets=path_states),
        dict(type=TRIGGER_REVERSE, ids=[10, 14] + [-1] * 8, targets=[states[0], states[4]]),
        dict(type=TRIGGER_FREEZE, ids=[10, 10, 11, -1, -1, -1, -1, -1, -1, -1], targets=path_states),
        dict(type=TRIGGER_BEGIN, ids=[-1, -1, 11, -1, -1, -1, -1, -1, -1, 99], targets=path_states),
        dict(type=TRIGGER_BEGIN, ids=[-1] * TRIGGER_MAX_IDS, targets=path_states),
        dict(type=TRIGGER_START, ids=[-2, -1, -1, -1, -1, -1, -1, -1, -1, -1],
             targets=[target(65534, True, True, True)]),
    ]
    return [dict(input=case, expected=trigger_callback(case)) for case in sets]


def path_info(path_id, segment, distance, motion, speed, pad=0, initial=None, size=PATH_INFO_SIZE):
    data = bytearray(struct.pack('<6H', path_id, segment, distance, motion, speed, pad))
    if initial is not None:
        data += struct.pack('<I', initial & U32)
    data += bytes(max(0, size - len(data)))
    return list(data[:size])


def platform_cases():
    sets = [
        dict(theme=THEME_SKY, payload=path_info(0, 0, 0, 0, 16)),
        dict(theme=THEME_SKY, payload=path_info(0, 1, 40, 2, 0x20)),
        dict(theme=THEME_VOL, payload=path_info(0, 0, 10, 8, 24, 0, 1, 16)),
        dict(theme=THEME_VOL, payload=path_info(0, 1, 0, 4, 65535, 0, 0, 16)),
        dict(theme=THEME_VOL, payload=path_info(0, 0, 5, 6, 12)),
        dict(theme=THEME_SWP, payload=path_info(0, 0, 0, 0, 8, 0, 0x80000001, 16)),
        dict(theme=THEME_SUB, payload=path_info(0, 1, 100, 10, 1, 0, None, 14)),
        dict(theme=THEME_SKY, payload=path_info(0, 0, 0, 0, 16, 0, None, 11)),
    ]
    return dict(path=dict(segments=2, length=1024),
                cases=[dict(input=case, expected=platform_payload(case)) for case in sets])


def drift_cases():
    sets = [
        dict(name='plain', seed=0, game_timer_start=0, ticks=300),
        dict(name='timer_0x7f', seed=12345, game_timer_start=0x7f, ticks=270),
        dict(name='pull_back', seed=777, game_timer_start=0, ticks=260, position=[0xb01 << 16, 0, 0]),
        dict(name='pull_back_negative_z', seed=4, game_timer_start=0x100, ticks=130, position=[-5 << 16, 0, -(0xb01 << 16) - 1]),
        dict(name='clamped', seed=99, game_timer_start=0x180, ticks=40, position=[SKY_MAX_DRIFT_POSITION - 10, 0, -SKY_MAX_DRIFT_POSITION + 3],
             velocity=[1 << 20, 0, -(1 << 20)]),
        dict(name='clear_mid_run', seed=0xdeadbeef, game_timer_start=0x1f0, ticks=300, clear_ticks=[140]),
        dict(name='wrap', seed=1, game_timer_start=0xffffff80, ticks=200),
        dict(name='held_timer', seed=31337, game_timer_start=0xfe, ticks=10,
             timers=[0xfe, 0xff, 0x100, 0x100, 0x100, 0x101, 0x101, 0x15f, 0x160, 0x160]),
    ]
    return [dict(input=case, expected=sky_drift_timeline(case)) for case in sets]


def cadence_cases():
    """Single-start frames before play, plain play frames, an unsigned wrap and catch-up frames of up to three ticks."""
    def frames(*items):
        return [dict(mode=mode, logic_ticks=ticks) for mode, ticks in items]
    sets = [
        dict(game_timer_start=0, frames=frames(('single_start', 1), ('single_start', 1), ('single_start', 1), ('single_start', 1))),
        dict(game_timer_start=0x7e, frames=frames(('play', 1), ('play', 1), ('play', 1), ('play', 1))),
        dict(game_timer_start=U32, frames=frames(('play', 1), ('play', 1), ('play', 1))),
        dict(game_timer_start=10, frames=frames(('play', 1), ('play', 3), ('play', 1), ('play', 2), ('play', 1))),
    ]
    return [dict(input=case, expected=game_timer_cadence(case)) for case in sets]


def register_cases(script_names, callback_names):
    ids, programs = frozen_programs(script_names, callback_names)
    roots = (('helicopter', 'SCRIPT_SKY_HELICOPTER', 'DYNAMIC'), ('helium_balloon', 'SCRIPT_SKY_HELIUM_BALLOON_WAITING', 'DYNAMIC'),
             ('rubber_balloon', 'SCRIPT_SKY_RUBBER_BALLOON_WAITING', 'DYNAMIC'), ('hawk', 'SCRIPT_SKY_BIRD', 'DYNAMIC'))
    setups = []
    for name, script, entity in roots:
        offset, count = prepared_count(programs[ids[script]])
        if offset != MATRIX_SIZE:
            raise ValueError(f'{script} prepares registers at {offset}')
        values = [(-1) ** i * (0x120 + 300 * i) for i in range(count)]
        full = list(matrix_bytes((7, -8, 9))) + list(struct.pack(f'<{count}i', *values))
        setups.append(dict(name=name, root=ids[script], entity=entity, count=count, payload=full))
        setups.append(dict(name=name + '_extended', root=ids[script], entity=entity, count=count,
                           payload=full + list(struct.pack('<i', -123456))))
        setups.append(dict(name=name + '_short', root=ids[script], entity=entity, count=count, payload=full[:-1]))
    return dict(setup=[dict(input=case, expected=register_setup(case)) for case in setups],
                programs={str(k): v for k, v in sorted(programs.items())})


def cases():
    """Invent source-boundary inputs; no retail data or game outputs are consumed."""
    sound_ids()
    script_names, subs, _ = exe_tables.name_list('scripts', jungle.SCRIPT_LIST, False)
    return dict(trigger_payload=trigger_cases(), trigger_first_update=first_update_cases(),
                trigger_callback=callback_cases(), platform_payload=platform_cases(),
                sky_drift_timeline=drift_cases(), game_timer_cadence=cadence_cases(),
                sky_script_registers=register_cases(script_names, subs['CallbackNames']))


def main():
    """Verify reproducibility by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = swamp.encode(cases()) + '\n'
    if args.write:
        OUTPUT.write_text(text)
    elif OUTPUT.read_text() != text:
        raise SystemExit('Sky facts differ; use --write only to deliberately regenerate')
    print('Sky facts verified')


if __name__ == '__main__':
    main()
