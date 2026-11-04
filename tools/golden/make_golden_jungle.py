#!/usr/bin/env python3
"""Independent synthetic facts from frozen ent_jun.c/.h, ent_swp.c, COLLIDE.C, froguser.C, FROG.C and MR_ANIM.C."""
import argparse
import json
import math
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT
from tools.golden import make_golden_desert as desert
from tools.golden import make_golden_exe_tables as exe_tables

ROOT = REPO_ROOT
OUTPUT = ROOT / 'tests/golden/synthetic/jungle.json'
SOUND_CFG = ROOT / 'archive/third_party/froglord_cfg/sounds/1997-11-19-pc-retail.cfg'
SCRIPT_LIST = '1997-09-18-psx-build63'
U16 = 0xffff
SYSTEM_GRAVITY = 0x100000
NO_FROG = 9999999
SOUNDS = {'JUN_PLANT_SNAP': 93, 'GEN_FROG_HOP': 6}
PLANT_WAITING, PLANT_TO_SNAP, PLANT_SNAPPING, PLANT_DELAY = range(4)
PLANT_HIT_DISTANCE = 256 + 100
PLANT_SOUND_DISTANCE = 30
PLANT_SNAP_REPEAT = 15
BRIDGE_WAITING, BRIDGE_TO_FALL, BRIDGE_FALLING = range(3)
SQUARE_USABLE, SQUARE_WATER, SQUARE_CLIFF = 1 << 0, 1 << 3, 1 << 11
SQUARE_BOUNCE_WALL_N, SQUARE_BOUNCE_WALL_E = 1 << 14, 1 << 15
FROG_JUMP_TO_ENTITY, FROG_ON_ENTITY, FROG_JUMP_TO_LAND = 1 << 1, 1 << 2, 1 << 6
FROG_JUMP_FROM_COLLPRIM = 1 << 16
FROG_MODE_JUMPING, FROG_MODE_USER = 1, 0x100
FROGUSER_MODE_BOUNCY_COBWEB, FROGUSER_MODE_BOUNCE = FROG_MODE_USER + 5, FROG_MODE_USER + 12
FROG_JUMP_TIME = 6
FROG_JUMPUP_FORCED_DY = 0x7fff
FROG_JUMP_DOWN_DISTANCE = 0x100
BOUNCE_GRID_DELTA, BOUNCE_TIME = 2, 15
DOOR_COUNT = 6
CRUSHER_USER_COUNT = 4
DIRECTION_STEPS = ((0, 1), (1, 0), (0, -1), (-1, 0))
SUB_TURTLE_NOTDIVING = 1

s16, s32, c_div, finished, step_cel = desert.s16, desert.s32, desert.c_div, desert.finished, desert.step_cel


def sound_ids():
    """Confirm the PC flat sound order from FrogLord's retail name list."""
    names = []
    for line in SOUND_CFG.read_text(encoding='utf-8').splitlines():
        text = line.split('#', 1)[0].strip()
        if text and not text.startswith('['):
            names.append(text)
    for name, value in SOUNDS.items():
        if names.index(name) != value:
            raise ValueError(f'{name} is flat sound {names.index(name)}, not {value}')


def sound_gate(distance):
    """PlaySoundDistance(_, _, 30): play only when 30 > SquareRoot0(closest frog distance)."""
    return PLANT_SOUND_DISTANCE > math.isqrt(distance)


def plant_timeline(case):
    """ENTSTRJunUpdatePlant with s16 post-decrement timers and a cyclic single action."""
    cels = case['cels']
    snap_time, snap_delay = s16(case['snap_time']), s16(case['snap_delay'])
    mode, timer, snap_timer, stepping, cel = PLANT_WAITING, 0, 0, True, 0

    def row(tick, distance, sounds):
        return dict(tick=tick, distance=distance, mode=mode, timer=timer, snap_timer=snap_timer,
                    stepping=stepping, cel=cel, sounds=sounds)

    rows = [row(0, -1, [])]
    for tick, distance in enumerate(case['distances'], 1):
        sounds = []

        def snap_sound():
            if sound_gate(distance):
                sounds.append(SOUNDS['JUN_PLANT_SNAP'])

        def repeat_sound():
            nonlocal snap_timer
            if snap_timer == 0:
                snap_sound()
                snap_timer = PLANT_SNAP_REPEAT
            else:
                snap_timer = s32(snap_timer - 1)

        if mode == PLANT_WAITING:
            stepping = False
            if distance < PLANT_HIT_DISTANCE:
                mode, timer = PLANT_TO_SNAP, snap_time
        elif mode == PLANT_TO_SNAP:
            previous, timer = timer, s16(timer - 1)
            if previous == 0:
                stepping, mode = True, PLANT_SNAPPING
                snap_sound()
                snap_timer = PLANT_SNAP_REPEAT
        elif mode == PLANT_SNAPPING:
            if finished(cel, cels):
                mode, timer = PLANT_DELAY, snap_delay
            repeat_sound()
        elif mode == PLANT_DELAY:
            previous, timer = timer, s16(timer - 1)
            if previous == 0:
                cel, stepping, mode = 0, False, PLANT_WAITING
            repeat_sound()
        if stepping:
            cel = step_cel(cel, cels)
        rows.append(row(tick, distance, sounds))
    snaps = [r['tick'] for r in rows[1:] if r['mode'] == PLANT_SNAPPING and rows[r['tick'] - 1]['mode'] == PLANT_TO_SNAP]
    resets = [r['tick'] for r in rows[1:] if r['mode'] == PLANT_WAITING and rows[r['tick'] - 1]['mode'] == PLANT_DELAY]
    return dict(rows=rows, snap_ticks=snaps, reset_ticks=resets,
                sound_ticks=[r['tick'] for r in rows if r['sounds']])


def rope_bridge_timeline(case):
    """ENTSTRJunUpdateRopeBridge: u8 hits, u16 post-decrement wait compared <= 0, one-shot fall."""
    hops, delay, cels = case['hops_before'] & U16, case['fall_delay'] & U16, case['cels']
    state, hits, wait, no_collision, stepping, cel = BRIDGE_WAITING, 0, 0, False, False, 0

    def row(tick, hit, fall):
        return dict(tick=tick, hit=hit, state=state, hits=hits, current_wait=wait, no_collision=no_collision,
                    stepping=stepping, frog_fall=fall, cel=cel)

    rows = [row(0, False, False)]
    for tick in range(1, case['ticks'] + 1):
        hit, fall = tick in case['hit_ticks'], False
        if state == BRIDGE_WAITING:
            if hit:
                hits = (hits + 1) & 0xff
                if hits >= hops:
                    wait, state = delay, BRIDGE_TO_FALL
        elif state == BRIDGE_TO_FALL:
            previous, wait = wait, (wait - 1) & U16
            if previous <= 0:
                state, stepping, no_collision, fall = BRIDGE_FALLING, True, True, case['rider']
        if stepping:
            cel = step_cel(cel, cels, one_shot=True)
        rows.append(row(tick, hit, fall))
    falls = [r['tick'] for r in rows if r['state'] == BRIDGE_FALLING and rows[r['tick'] - 1]['state'] == BRIDGE_TO_FALL]
    return dict(rows=rows, fall_tick=falls[0] if falls else -1)


def square_height(grid, index):
    """GetGridSquareHeight: the four map-poly corner Y values summed, arithmetic >>2."""
    return sum(grid['squares'][index]['corners']) >> 2


def stack(grid, x, z):
    """GetGridStack for an in-range cell: [count, first square index]."""
    if not (0 <= x < grid['xnum'] and 0 <= z < grid['znum']):
        raise ValueError('synthetic stack lookup leaves the grid')
    return grid['stacks'][z * grid['xnum'] + x]


def mushroom_bounce(case):
    """COLLIDE.C BOUNCY centring, then FroguserBounceSetup's forced JumpFrog(dir - N, FORCED, 2, 15)."""
    grid = case['grid']
    if case['frog_flags'] & FROG_ON_ENTITY:
        raise ValueError('the synthetic bounce covers a frog that is not carried by an entity')
    position = list(case['frog_pos'])
    position[0], position[2] = s32(case['entity_t'][0] << 16), s32(case['entity_t'][1] << 16)
    lw = [position[0] >> 16, position[1] >> 16, position[2] >> 16]
    grid_x, grid_z = (lw[0] - grid['base_x']) >> 8, (lw[2] - grid['base_z']) >> 8
    centred = dict(fr_pos=list(position), lw=list(lw), grid=[grid_x, grid_z], forbid=True)
    controller = [(case['controller_n'] + i) & 3 for i in range(4)]
    jump_direction = case['direction'] - case['controller_n']
    direction = controller[jump_direction & 3]
    x_dir, z_dir = DIRECTION_STEPS[direction]
    x, z = x_dir * BOUNCE_GRID_DELTA + grid_x, z_dir * BOUNCE_GRID_DELTA + grid_z
    remaining = BOUNCE_GRID_DELTA
    while True:
        previous, remaining = remaining, remaining - 1
        if previous == 0:
            break
        if x < 0 or x >= grid['xnum'] or z < 0 or z >= grid['znum']:
            x, z = x + x_dir, z + z_dir
        else:
            break
    flags, square, inside = case['frog_flags'], None, remaining >= 0
    if inside:
        count, index = stack(grid, x, z)
        target_flags = [grid['squares'][index + k]['flags'] for k in range(count)]
        current = case['current_square_flags']
        if ((z_dir == 1 and current & SQUARE_BOUNCE_WALL_N)
                or (z_dir == -1 and any(f & SQUARE_BOUNCE_WALL_N for f in target_flags))
                or (z_dir == 0 and x_dir == 1 and current & SQUARE_BOUNCE_WALL_E)
                or (z_dir == 0 and x_dir == -1 and any(f & SQUARE_BOUNCE_WALL_E for f in target_flags))):
            return dict(centred=centred, jump_direction=jump_direction, result='cobweb', direction=direction,
                        user_data=[x, z], mode=FROGUSER_MODE_BOUNCE, sounds=[])
        y = lw[1]
        found = False
        for k in range(count):
            if not target_flags[k] & SQUARE_USABLE:
                continue
            if target_flags[k] & SQUARE_CLIFF:
                raise ValueError('cliff squares are outside the synthetic bounce scope')
            y1 = square_height(grid, index + k)
            if (y >= y1 and FROG_JUMPUP_FORCED_DY >= y - y1) or (y1 >= y and FROG_JUMP_DOWN_DISTANCE >= y1 - y):
                flags, square, found = flags | FROG_JUMP_TO_LAND, index + k, True
                break
        if not found:
            for k in range(count - 1, -1, -1):
                if target_flags[k] & SQUARE_USABLE and square_height(grid, index + k) >= y:
                    flags, square, found = flags & ~(FROG_JUMP_TO_LAND | FROG_JUMP_TO_ENTITY), index + k, True
                    break
        if not found:
            flags = flags & ~(FROG_JUMP_TO_LAND | FROG_JUMP_TO_ENTITY)
            square = index - 1 if count else None
    else:
        flags &= ~(FROG_JUMP_TO_LAND | FROG_JUMP_TO_ENTITY)
    target = [(x << 8) + grid['base_x'] + 0x80, (z << 8) + grid['base_z'] + 0x80]
    fall = (SYSTEM_GRAVITY * (BOUNCE_TIME + 1)) >> 1
    if flags & FROG_JUMP_TO_LAND:
        fr_y = square_height(grid, square)
        vy = s32(c_div(s32((fr_y - lw[1]) << 16), BOUNCE_TIME + 1) - fall)
    else:
        fr_y, vy = lw[1], -fall
    velocity = [c_div(s32((target[0] << 16) - position[0]), BOUNCE_TIME), vy,
                c_div(s32((target[1] << 16) - position[2]), BOUNCE_TIME)]
    return dict(centred=centred, jump_direction=jump_direction, result='jump', direction=direction,
                inside=inside, grid=[x, z], square=square, flags=flags, to_land=bool(flags & FROG_JUMP_TO_LAND),
                target=target, fr_y=fr_y, old_y=case['fr_y'], count=BOUNCE_TIME, velocity=velocity,
                mode=FROGUSER_MODE_BOUNCE, sounds=[SOUNDS['GEN_FROG_HOP']])


def door_bounce_back(case):
    """SwpCrusherCallback outside THEME_SWP: default_handler reversal into the first square of the stack."""
    grid = case['grid']
    grid_x, grid_z = case['grid_cell']
    reverse = {0: (0, -1, 2), 1: (-1, 0, 3), 2: (0, 1, 0), 3: (1, 0, 1)}
    dx, dz, direction = reverse.get(case['direction'], (0, 0, case['direction']))
    x, z = grid_x + dx, grid_z + dz
    count, index = stack(grid, x, z)
    unchanged = dict(happened=False, branch='none', grid=None, direction=None, square=None, flags_added=0,
                     mode=None, count=None, target=None, velocity=None, translation=None, old_y=None,
                     forbid=False, runtime_count=-1)
    if count == 0 or not grid['squares'][index]['flags'] & SQUARE_USABLE:
        return unchanged
    height = square_height(grid, index)
    target_x, target_z = (x << 8) + grid['base_x'] + 0x80, (z << 8) + grid['base_z'] + 0x80
    position = case['fr_pos']
    if case['mode'] >= FROG_MODE_USER:
        target = [target_x, height, target_z]
        velocity = [c_div(s32((target[i] << 16) - position[i]), FROG_JUMP_TIME) for i in range(3)]
        return dict(unchanged, happened=True, branch='user', grid=[x, z], direction=case['direction'], square=index,
                    mode=case['mode'], count=FROG_JUMP_TIME, target=target, velocity=velocity,
                    translation=list(case['frog_t']), runtime_count=CRUSHER_USER_COUNT)
    fall = (SYSTEM_GRAVITY * (DOOR_COUNT + 1)) >> 1
    vy = s32(c_div(s32((case['fr_y'] - case['frog_t'][1]) << 16), DOOR_COUNT + 1) - fall)
    vx = c_div(s32((target_x << 16) - position[0]), DOOR_COUNT)
    vz = c_div(s32((target_z << 16) - position[2]), DOOR_COUNT)
    translation = [s32(case['frog_t'][0] + (vx >> 15)), case['frog_t'][1], s32(case['frog_t'][2] + (vz >> 15))]
    return dict(unchanged, happened=True, branch='normal', grid=[x, z], direction=direction, square=index,
                flags_added=FROG_JUMP_TO_LAND | FROG_JUMP_FROM_COLLPRIM, mode=FROG_MODE_JUMPING,
                count=DOOR_COUNT, target=[target_x, None, target_z], velocity=[vx, vy, vz],
                translation=translation, old_y=case['fr_y'], forbid=True)


def hippo_no_dive(case, script_names):
    """ENTSTRJunCreateHippo: SUB_TURTLE_NOTDIVING restarts the root script as SCRIPT_JUN_HIPPO_NO_DIVE."""
    name = 'SCRIPT_JUN_HIPPO_NO_DIVE' if (case['turtle_type'] & 0xffffffff) == SUB_TURTLE_NOTDIVING else 'SCRIPT_JUN_HIPPO'
    return dict(script=name, script_id=script_names.index(name))


def plant_cases():
    def hold(*spans):
        out = []
        for value, length in spans:
            out.extend([value] * length)
        return out
    sets = [
        dict(snap_time=6, snap_delay=30, cels=20, distances=hold((NO_FROG, 2), (300, 118))),
        dict(snap_time=0, snap_delay=0, cels=20, distances=hold((355, 60))),
        dict(snap_time=6, snap_delay=30, cels=20, distances=hold((200, 30), (NO_FROG, 60))),
        dict(snap_time=3, snap_delay=5, cels=20,
             distances=hold((356, 3), (355, 1), (899, 6), (900, 20), (899, 10), (1000, 20))),
        dict(snap_time=1, snap_delay=2, cels=1, distances=hold((0, 12))),
        dict(snap_time=2, snap_delay=40, cels=4, distances=hold((100, 5), (NO_FROG, 55))),
    ]
    return [dict(input=case, expected=plant_timeline(case)) for case in sets]


def bridge_cases():
    sets = [
        dict(fall_delay=90, hops_before=1, hit_ticks=[5], rider=True, cels=25, ticks=125),
        dict(fall_delay=10, hops_before=3, hit_ticks=[2, 6, 9, 12], rider=False, cels=25, ticks=50),
        dict(fall_delay=0, hops_before=1, hit_ticks=[1], rider=True, cels=25, ticks=30),
        dict(fall_delay=3, hops_before=1, hit_ticks=[2, 6], rider=True, cels=25, ticks=12),
        dict(fall_delay=2, hops_before=0, hit_ticks=[4, 5], rider=False, cels=3, ticks=12),
        dict(fall_delay=1, hops_before=2, hit_ticks=[3, 4, 5], rider=True, cels=25, ticks=10),
    ]
    return [dict(input=case, expected=rope_bridge_timeline(case)) for case in sets]


def bounce_grid():
    """A 6x6 grid: flat land, raised and sunken squares, two-layer, water, wall, unusable and empty stacks."""
    def square(flags, *corners):
        return dict(flags=flags, corners=list(corners))
    usable = SQUARE_USABLE
    squares = [square(usable, 0, 0, 0, 0), square(usable, -200, -200, -200, -201),
               square(usable, 300, 300, 300, 300), square(usable, 256, 256, 256, 257),
               square(usable, -600, -600, -600, -600), square(usable | SQUARE_WATER, 64, 64, 64, 64),
               square(0, -50, -50, -50, -50), square(usable | SQUARE_BOUNCE_WALL_N, 0, 0, 0, 0),
               square(usable | SQUARE_BOUNCE_WALL_E, 0, 0, 0, 0), square(usable, 3, 2, 1, -9)]
    stacks = [[1, 0] for _ in range(36)]
    layout = {(2, 4): [1, 1], (4, 2): [1, 2], (2, 0): [2, 3], (0, 2): [1, 6],
              (2, 5): [2, 5], (5, 2): [0, 0], (3, 1): [1, 7], (1, 3): [1, 8],
              (3, 5): [1, 9], (5, 3): [2, 2], (1, 1): [0, 0], (4, 4): [1, 4], (0, 4): [2, 6]}
    for (x, z), value in layout.items():
        stacks[z * 6 + x] = value
    return dict(base_x=-768, base_z=-768, xnum=6, znum=6, stacks=stacks, squares=squares)


def mushroom_cases():
    grid = bounce_grid()
    centre = [-768 + 2 * 256 + 0x80, -768 + 2 * 256 + 0x80]
    base = dict(grid=grid, frog_pos=[centre[0] << 16 | 0x1234, -(20 << 16) - 7, (centre[1] << 16) - 0x8000],
                entity_t=centre, fr_y=-20, frog_flags=FROG_JUMP_TO_LAND | (1 << 4), current_square_flags=0)
    sets = []
    for direction in range(4):
        for controller_n in range(4):
            sets.append(dict(base, direction=direction, controller_n=controller_n))
    sets += [
        dict(base, direction=0, controller_n=0, frog_pos=[0, 120 << 16, 0], entity_t=[centre[0] + 33, centre[1] - 70]),
        dict(base, direction=2, controller_n=0, frog_pos=[0, -400 << 16, 0], fr_y=-400),
        dict(base, direction=0, controller_n=0, entity_t=[-768 + 2 * 256 + 0x80, -768 + 4 * 256 + 0x80]),
        dict(base, direction=1, controller_n=3, entity_t=[-768 + 4 * 256 + 0x80, -768 + 3 * 256 + 0x80]),
        dict(base, direction=1, controller_n=0, entity_t=[-768 + 3 * 256 + 0x80, -768 + 2 * 256 + 0x80]),
        dict(base, direction=0, controller_n=0, entity_t=[-768 + 2 * 256 + 0x80, -768 + 3 * 256 + 0x80]),
        dict(base, direction=0, controller_n=0, current_square_flags=SQUARE_BOUNCE_WALL_N),
        dict(base, direction=0, controller_n=2, entity_t=[-768 + 3 * 256 + 0x80, -768 + 3 * 256 + 0x80]),
        dict(base, direction=3, controller_n=0, entity_t=[-768 + 3 * 256 + 0x80, -768 + 3 * 256 + 0x80]),
        dict(base, direction=2, controller_n=0, entity_t=[-768 + 3 * 256 + 0x80, -768 + 3 * 256 + 0x80]),
        dict(base, direction=1, controller_n=0, entity_t=[-768 + 3 * 256 + 0x80, -768 + 1 * 256 + 0x80],
             current_square_flags=SQUARE_BOUNCE_WALL_E),
        dict(base, direction=2, controller_n=0, entity_t=[-768 + 1 * 256 + 0x80, -768 + 3 * 256 + 0x80]),
        dict(base, direction=0, controller_n=1, entity_t=[-768 + 3 * 256 + 0x80, -768 + 3 * 256 + 0x80],
             frog_pos=[0, -2 << 16, 0], frog_flags=0),
    ]
    return [dict(input=case, expected=mushroom_bounce(case)) for case in sets]


def door_cases():
    grid = bounce_grid()
    cell = [2, 2]
    centre = [-768 + 2 * 256 + 0x80, -768 + 2 * 256 + 0x80]
    base = dict(grid=grid, grid_cell=cell, mode=FROG_MODE_JUMPING, fr_y=-40, frog_t=[centre[0] + 9, -61, centre[1] - 13],
                fr_pos=[(centre[0] + 9) << 16 | 0x4000, -(61 << 16) + 5, ((centre[1] - 13) << 16) - 0x123])
    sets = [dict(base, direction=d) for d in range(4)]
    sets += [dict(base, direction=d, mode=FROGUSER_MODE_BOUNCE) for d in range(4)]
    sets += [
        dict(base, direction=0, grid_cell=[2, 1], fr_y=-200, frog_t=[-170, -199, -400]),
        dict(base, direction=2, grid_cell=[0, 1], fr_y=0, frog_t=[-630, 1, -381], fr_pos=[-630 << 16, 1 << 16, -381 << 16]),
        dict(base, direction=1, grid_cell=[1, 1], fr_y=300, frog_t=[-382, 3, -380]),
        dict(base, direction=3, grid_cell=[1, 2]),
        dict(base, direction=0, grid_cell=[1, 2]),
        dict(base, direction=2, grid_cell=[5, 4], mode=FROGUSER_MODE_BOUNCE),
        dict(base, direction=1, grid_cell=[3, 3], fr_y=-1, frog_t=[0, -1, 0], fr_pos=[-1, -1 << 16, 7]),
        dict(base, direction=0, grid_cell=[0, 5]),
        dict(base, direction=0, grid_cell=[2, 1], mode=FROGUSER_MODE_BOUNCE),
    ]
    return [dict(input=case, expected=door_bounce_back(case)) for case in sets]


def hippo_cases(script_names):
    return [dict(input=dict(turtle_type=t), expected=hippo_no_dive(dict(turtle_type=t), script_names))
            for t in (0, 1, 2, 0xffffffff)]


def cases():
    """Invent source-boundary inputs; no retail data or game outputs are consumed."""
    sound_ids()
    script_names, _, _ = exe_tables.name_list('scripts', SCRIPT_LIST, False)
    return dict(plant_timeline=plant_cases(), rope_bridge_timeline=bridge_cases(),
                mushroom_bounce=mushroom_cases(), door_bounce_back=door_cases(),
                hippo_no_dive=hippo_cases(script_names))


def main():
    """Verify reproducibility by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(cases(), indent=1) + '\n'
    if args.write:
        OUTPUT.write_text(text)
    elif OUTPUT.read_text() != text:
        raise SystemExit('Jungle facts differ; use --write only to deliberately regenerate')
    print('Jungle facts verified')


if __name__ == '__main__':
    main()
