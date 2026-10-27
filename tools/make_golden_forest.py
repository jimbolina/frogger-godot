#!/usr/bin/env python3
"""Independent synthetic ent_for.c/ent_for.h and COLLIDE.C transition facts."""
import argparse
import copy
import json
import math
from pathlib import Path

OUTPUT = Path(__file__).resolve().parents[1] / 'tests/golden/synthetic/forest.json'


def squirrel(case):
    """Interpret the frozen running/turning switch; authored delay is unused."""
    mode = case['mode']
    active = -1
    action = mode
    if mode == 0 and case['bounce']:
        mode, action, active = 1, 1, 0
    elif mode == 1 and case['cel'] >= case['length'] - 1:
        mode, action, active = 0, 0, 1
    return dict(mode=mode, action=action, active=active)


def hedgehog(case):
    """Interpret unsigned clocks and rolling-only repeat precedence."""
    mode, timer, action = case['mode'], case['timer'], case['action']
    speed = -1
    if mode in (0, 1):
        timer = (timer - 1) & 65535
        if case['timer'] == 0:
            mode = 2 if mode == 0 else 3
        if case['mode'] == 1 and case['repeat']:
            mode, timer, action, speed = 0, 2, 0, 256
    elif case['cel'] >= case['length'] - 1:
        if mode == 2:
            mode, timer, action, speed = 1, 3, 1, 768
        else:
            mode, timer, action, speed = 0, 2, 0, 256
    return dict(mode=mode, timer=timer, action=action, speed=speed)


def branch(case):
    """Interpret branch clocks and vertical fall independently of model rotation."""
    mode, timer, y, speed = case['mode'], case['timer'], case['y'], case['speed']
    sounds, disabled, detach, pop = 0, case['disabled'], False, False
    if mode == 0 and case['hit']:
        mode, sounds = 1, 1
    elif mode == 1:
        timer = (timer - 1) & 65535
        if case['timer'] == 0:
            mode, speed, sounds, disabled, detach = 2, 0, 1, True, case['attached']
    elif mode == 2:
        if y < case['floor']:
            speed += 0x100000 >> 2
            y += speed >> 16
        else:
            y, pop = case['floor'] - 20, not case['effect']
    return dict(mode=mode, timer=timer, y=y, speed=speed, sounds=sounds,
                disabled=disabled, detach=detach, pop=pop)


def hive(case):
    """Axis-aligned source hive transition facts avoid a shared normalization oracle."""
    mode, speed, delay = case['mode'], case['speed'], case['delay']
    x, visible, active = case['x'], case['visible'], case['active']
    death = False
    early = False
    if mode == 0:
        if case['eligible'] and abs(case['frog_x']) < case['release']:
            mode, speed, active, x = 1, 0, active + 1, 0
    elif mode in (1, 2) and case['stopped']:
        mode, early = 3, True
    elif mode == 1:
        if speed < case['maximum']:
            speed += 128
        x += (speed >> 8) * (1 if case['frog_x'] > x else -1)
        if abs(case['frog_x'] - x) <= 100:
            death, mode = True, 3
        if case['first_hit'] == 2:
            mode, delay = 2, 0
        visible = True
    elif mode == 2:
        speed = 0 if speed < 512 else speed - 256
        delay = (delay + 1) & 0xffffffff
        if case['delay'] > 60:
            mode = 3
        else:
            x += speed >> 8
            if case['first_hit'] == 1:
                mode = 1
            visible = True
    elif mode == 3:
        if speed < case['maximum'] << 8:
            speed += 256
        x -= (speed >> 8) * (1 if x > 0 else -1)
        if abs(case['x']) < 128:
            mode, visible, active = 0, False, max(0, active - 1) if active < 0 else active - 1
    return dict(mode=mode, speed=speed, delay=delay, x=x, visible=visible,
                active=active, death=death, early=early)


def visibility(case):
    """Frozen axis-aligned stepping, C division, frog-first and FORM gates."""
    for step in range(abs(case['direction']) >> 4):
        x = case['start'] + (step + 1) * (16 if case['direction'] > 0 else -16)
        group = abs(x) // 1024 * (1 if x >= 0 else -1)
        if group < 0 or group >= 2:
            return 0
        if case['frog_active'] and (case['frog_x'] - x) ** 2 <= 10000:
            return 1
        local = ((x - case['entity_x'] + 32768) % 65536) - 32768
        if (case['live'] and not case['disabled'] and case['form'] in (9,13,14,35)
                and case['has_form'] and local ** 2 < case['radius2']
                and case['offset'] <= local <= case['offset'] + 256):
            return 2
    return 0


def visibility_cases():
    """Invent independent form/radius/group/short-distance boundary examples."""
    base = dict(start=0,direction=16,frog_active=False,frog_x=1000,entity_x=0,
                live=True,disabled=False,form=9,has_form=True,radius2=1000000,offset=0)
    variants = [dict(direction=15), dict(direction=16), dict(offset=16),
                dict(offset=17),dict(offset=-240),dict(offset=-241),
                dict(radius2=256),dict(radius2=257),dict(frog_active=True,frog_x=116),
                dict(frog_active=True,frog_x=117),dict(live=False),dict(disabled=True),
                dict(form=8),dict(form=35),dict(has_form=False),dict(entity_x=65536),
                dict(start=-32,direction=16,offset=-32),
                dict(start=-1040,direction=16,offset=-2048),dict(start=2032)]
    result = []
    for variant in variants:
        case = dict(base, **variant)
        result.append(dict(input=case,expected=visibility(case)))
    return result


def normalized(vector):
    """Source fixed-12 vector normalization, independently rounded."""
    length = math.sqrt(sum(value * value for value in vector))
    if length == 0:
        return [0, 0, 0]
    values = [value * 4096 / length for value in vector]
    return [math.floor(value + .5) if value >= 0 else math.ceil(value - .5) for value in values]


def land_projection(case):
    """Frozen ENTITY.C update projection composed with GRID.C first-layer triangles."""
    x, y, z = case['position']
    if case['world_align']:
        return [4096,0,0,0,4096,0,0,0,4096,x,y,z]
    y0,y1,y2,y3 = case['heights']
    dx,dz = x & 255,z & 255
    if dz >= dx:
        y = y0 + ((dx*(y1-y0)) >> 8) + (((256-dz)*(y2-y0)) >> 8)
        xs,zs = normalized([256,y1-y0,0]),normalized([0,y0-y2,256])
    else:
        y = y3 + (((256-dx)*(y2-y3)) >> 8) + ((dz*(y1-y3)) >> 8)
        xs,zs = normalized([256,y3-y2,0]),normalized([0,y1-y3,256])
    dx = sum(a*b for a,b in zip(xs,case['tangent'])) >> 12
    dz = sum(a*b for a,b in zip(zs,case['tangent'])) >> 12
    forward = [(xs[i]*dx+zs[i]*dz) >> 12 for i in range(3)]
    right = normalized([forward[2],0,-forward[0]])
    up = [(forward[1]*right[2]-forward[2]*right[1]) >> 12,
          (forward[2]*right[0]-forward[0]*right[2]) >> 12,
          (forward[0]*right[1]-forward[1]*right[0]) >> 12]
    return [component for i in range(3) for component in (right[i],up[i],forward[i])] + [x,y,z]


def projection_cases():
    """Non-planar triangles and a tilted tangent expose incorrect normalization."""
    result = []
    for heights in ([0,0,0,0],[-80,48,-16,112],[-256,0,0,256]):
        for position in ([32,777,192],[192,777,32],[128,777,128]):
            for tangent in ([0,0,4096],[2458,0,3277],[0,4096,0]):
                case = dict(heights=heights,position=position,tangent=tangent,world_align=False)
                result.append(dict(input=case,expected=land_projection(case)))
    case = dict(heights=[-80,48,-16,112],position=[32,777,192],tangent=[2458,0,3277],world_align=True)
    result.append(dict(input=case,expected=land_projection(case)))
    return result


def cases():
    """Invent boundary stimuli; no retail bytes or gameplay output are inputs."""
    out = dict(squirrels=[], hedgehogs=[], branches=[], hives=[], visibility=visibility_cases(), projection=projection_cases())
    for mode in range(2):
        for bounce in (False, True):
            for cel in (2, 3, 4):
                case = dict(mode=mode, bounce=bounce, cel=cel, length=4)
                out['squirrels'].append(dict(input=case, expected=squirrel(case)))
    for mode in range(4):
        for timer in (0, 1, 65535):
            for repeat in (False, True):
                for cel in (2, 3):
                    case = dict(mode=mode, timer=timer, repeat=repeat, cel=cel,
                                length=4, action=1 if mode in (1, 3) else 0)
                    out['hedgehogs'].append(dict(input=case, expected=hedgehog(case)))
    for mode in range(3):
        for timer in (0, 1, 65535):
            for y in (-1, 0, 1):
                case = dict(mode=mode, timer=timer, y=y, floor=0, speed=0,
                            disabled=mode==2, hit=True, attached=True, effect=False)
                out['branches'].append(dict(input=case, expected=branch(case)))
    base = dict(mode=0, speed=0, delay=0, x=0, frog_x=1000, release=1000,
                maximum=257, visible=False, active=0, eligible=True,
                stopped=False, first_hit=0)
    variants = [dict(frog_x=x) for x in (999,1000,1001)]
    variants += [dict(frog_x=999,eligible=False)]
    variants += [dict(mode=1,speed=s,first_hit=h,active=1) for s in (0,256,257) for h in (0,1,2)]
    variants += [dict(mode=1,frog_x=x,active=1) for x in (100,101)]
    variants += [dict(mode=m,stopped=True,active=1) for m in (1,2)]
    variants += [dict(mode=2,speed=s,delay=d,first_hit=h,active=1) for s in (511,512) for d in (60,61,0xffffffff) for h in (0,1,2)]
    variants += [dict(mode=3,x=x,active=a) for x in (127,128) for a in (-1,0,1)]
    for variant in variants:
        case = copy.deepcopy(base)
        case.update(variant)
        out['hives'].append(dict(input=case,expected=hive(case)))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(cases(), indent=2) + '\n'
    if args.write:
        OUTPUT.write_text(text)
    elif OUTPUT.read_text() != text:
        raise SystemExit('Forest facts differ; use --write only to deliberately regenerate')
    print('Forest facts verified')


if __name__ == '__main__':
    main()
