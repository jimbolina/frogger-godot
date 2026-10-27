#!/usr/bin/env python3
"""Independent synthetic facts from frozen ent_vol.c/.h, ent_des.h and ENTITY.C."""
import argparse
import itertools
import json
from pathlib import Path

OUTPUT = Path(__file__).resolve().parents[1] / 'tests/golden/synthetic/volcano.json'


def falling(case):
    """Interpret unsigned hit/countdown boundaries and the source fall transition."""
    mode, hits, timer = case['mode'], case['hits'], case['timer']
    paused, enabled, one_shot = case['paused'], case['enabled'], case['one_shot']
    disabled, detach, sound = case['disabled'], False, False
    if mode == 0:
        if case['hit']:
            hits = (hits + 1) & 255
            if hits >= case['hops']:
                timer, mode = case['delay'], 1
        else:
            paused = True
    elif mode == 1:
        timer = (timer - 1) & 65535
        if case['timer'] == 0:
            mode, enabled, one_shot, disabled = 2, True, True, True
            detach, sound = case['attached'], True
    return dict(mode=mode, hits=hits, timer=timer, paused=paused,
                enabled=enabled, one_shot=one_shot, disabled=disabled,
                detach=detach, sound=sound)


def switch_update(case):
    """Interpret debounce before release and first-visit flag consumption."""
    mode, timer, flags, action = case['mode'], case['timer'], case['flags'], case['action']
    initialize = bool(flags & 1)
    if timer:
        timer -= 1
    flags &= ~1
    sound = False
    if timer == 0 and flags & 2 and mode in (0, 2):
        mode += 1
        timer, action, sound = 6, 1, True
    flags |= 2
    return dict(mode=mode, timer=timer, flags=flags, action=action,
                initialize=initialize, sound=sound)


def switch_contact(case):
    """Interpret four switch states; frozen FREEZE and START both toggle."""
    mode, timer, flags = case['mode'], case['timer'], case['flags'] & ~2
    action, cell, enabled = case['action'], case['cell'], case['enabled']
    nudge, activate = False, False
    stopped, active, backwards = case['stopped'], case['active'], case['backwards']
    if timer == 0:
        if mode in (0, 2):
            nudge = True
        else:
            mode = 2 if mode == 1 else 0
            action, cell, timer, enabled, activate = 0, int(mode == 0), 4, True, True
            if case['type'] == 1:
                backwards = not backwards
            else:
                stopped = not stopped
                if case['path']:
                    active = not stopped
    return dict(mode=mode, timer=timer, flags=flags, action=action, cell=cell,
                enabled=enabled, nudge=nudge, activate=activate,
                stopped=stopped, active=active, backwards=backwards,
                matrix_y=case['target_y'] - 32 if nudge else case['matrix_y'])


def allocation(case):
    """Model mapdisp.c's 128 allocation slots, expansion walk and render expiry."""
    pool = [(group, timer) for group, timer in enumerate(case['timers']) if timer]
    pool.extend([None] * (128 - len(pool)))
    remaining, visited = 2500, []
    for group in case['selected']:
        if remaining <= 0:
            break
        visited.append(group)
        count = case['counts'][group]
        slot = next((index for index, value in enumerate(pool) if value and value[0] == group), None)
        if slot is not None:
            if pool[slot][1] >= 2:
                pool[slot] = (group, 3)
            remaining -= count
        elif count and None in pool and count <= remaining:
            pool[pool.index(None)] = (group, 3)
            remaining -= count
    timers = [0] * len(case['counts'])
    for value in pool:
        if value:
            group, timer = value
            timers[group] = timer - 1
    return dict(groups=visited, timers=timers)


def allocation_cases():
    """Exercise budget equality, rejected allocations, expiry and pool pressure."""
    cases = []
    for counts in ([2000,600,500,1], [2500,1,0,1], [2501,1,2499,0], [0,0,0,0]):
        for timers in ([0,0,0,0], [2,0,2,0], [1,0,1,0], [3,2,1,0]):
            for selected in ([0,1,2,3], [3,2,1,0], [0,0,1,2], []):
                case = dict(counts=counts,timers=timers,selected=selected)
                cases.append(dict(input=case,expected=allocation(case)))
    for timer in (1,2):
        case = dict(counts=[1]*130,timers=[timer]*128+[0,0],selected=[128,129,0])
        cases.append(dict(input=case,expected=allocation(case)))
    return cases


def bounding_radius(case):
    """Interpret mapload.C static bbox plus unsigned primitive expansion."""
    if case['explicit']:
        return case['explicit']
    value = sum(component * component for component in case['corner']) & 0xffffffff
    if value >= 0x80000000:
        value -= 0x100000000
    value = max(0, value)
    for primitive in case['primitives']:
        shape, size = primitive['shape'], primitive['size']
        if shape == 0:
            extent = sum(length * length for length in size)
        elif shape in (1, 2, 3):
            extent = size[shape - 1] ** 2 + primitive['radius2']
        elif shape == 4:
            extent = primitive['radius2']
        else:
            extent = 0
        distance = sum(component * component for component in primitive['offset'])
        value = max(value & 0xffffffff, (distance + extent) & 0xffffffff)
    value = (value + 100) & 0xffffffff
    return value - 0x100000000 if value >= 0x80000000 else value


def radius_cases():
    """Cover every source primitive shape, explicit override and 32-bit wrap."""
    result = []
    for shape, explicit in itertools.product(range(5), (0, 19024)):
        case = dict(corner=[0,20,0], explicit=explicit,
                    primitives=[dict(shape=shape, offset=[0,-115,4], size=[128,64,32], radius2=25000)])
        result.append(dict(input=case,expected=bounding_radius(case)))
    for size in ([128,128,128], [65535,65535,65535], [0,0,0]):
        case = dict(corner=[0,20,0], explicit=0,
                    primitives=[dict(shape=0, offset=[0,-115,4], size=size, radius2=0)])
        result.append(dict(input=case,expected=bounding_radius(case)))
    case = dict(corner=[32767,32767,32767], explicit=0, primitives=[])
    result.append(dict(input=case,expected=bounding_radius(case)))
    return result


def cases():
    """Invent source-boundary inputs; no retail data or game outputs are consumed."""
    out = dict(falling=[], switch_updates=[], switch_contacts=[], initial_targets=[], moving=[], allocation=allocation_cases(), radius=radius_cases())
    for mode, hits, timer, hit, attached in itertools.product(range(3), (0, 1, 254, 255), (0, 1, 65535), (False, True), (False, True)):
        case = dict(mode=mode, hits=hits, timer=timer, hit=hit, attached=attached,
                    hops=2, delay=3, paused=False, enabled=False, one_shot=False,
                    disabled=mode == 2)
        out['falling'].append(dict(input=case, expected=falling(case)))
    for hops in (0, 255, 256, 65535):
        case = dict(mode=0, hits=254, timer=0, hit=True, attached=False,
                    hops=hops, delay=65535, paused=True, enabled=False,
                    one_shot=False, disabled=False)
        out['falling'].append(dict(input=case, expected=falling(case)))
    for mode, timer, flags in itertools.product(range(4), (0, 1, 2, 6, 4294967295), range(4)):
        case = dict(mode=mode, timer=timer, flags=flags, action=0 if mode in (0, 2) else 1)
        out['switch_updates'].append(dict(input=case, expected=switch_update(case)))
    for mode, timer, kind, stopped, active, backwards in itertools.product(range(4), (0, 1, 4), range(3), (False, True), (False, True), (False, True)):
        case = dict(mode=mode, timer=timer, flags=2, type=kind, stopped=stopped,
                    active=active, backwards=backwards, path=True,
                    action=1, cell=0, enabled=False, target_y=-100,
                    world_y=-250, matrix_y=-300)
        out['switch_contacts'].append(dict(input=case, expected=switch_contact(case)))
    for initial, path in itertools.product((0, 1, 2, 4294967295), (False, True)):
        out['initial_targets'].append(dict(input=dict(initial=initial, path=path),
                                          expected=dict(stopped=initial == 1, active=initial != 1 if path else False)))
    for volcano, stopped in itertools.product((False, True), repeat=2):
        out['moving'].append(dict(input=dict(volcano=volcano, stopped=stopped),
                                  expected=dict(play=volcano and not stopped, stop=volcano and stopped)))
    return out


def main():
    """Verify reproducibility by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(cases(), indent=2) + '\n'
    if args.write:
        OUTPUT.write_text(text)
    elif OUTPUT.read_text() != text:
        raise SystemExit('Volcano facts differ; use --write only to deliberately regenerate')
    print('Volcano facts verified')


if __name__ == '__main__':
    main()
