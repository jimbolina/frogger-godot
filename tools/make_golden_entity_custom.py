"""Independent ent_org.c/ent_gen.c/ent_sub.c custom entity state-machine facts."""
import json
from pathlib import Path


def signed16(value):
    return (value + 32768) % 65536 - 32768


def crocodile(blocked, hit_tick, checkpoint_tick):
    mode, timer, selected, delay = 0, 0, -1, 0
    random, draws, covered, disabled, flags = 1, 0, 0, 0, 9
    matrix = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]
    hidden, moving = True, False
    rows = []
    for tick in range(245):
        death = -1
        if mode == 0:
            flags |= 8
            timer -= 1
            if timer == -1:
                random = (random * 1103515245 + 12345) & 0xffffffff
                draws += 1
                choice = ((random >> 16) & 32767) % 5
                timer = 60
                if not (blocked | covered) & (1 << choice):
                    selected = choice
                    matrix = [-3072, 0, 0, 0, 3072, 0, 0, 0, -3072, 1000 + choice * 256, signed16(-32760 - 100), signed16(32760 + 50)]
                    covered |= 1 << choice
                    flags &= ~1
                    hidden, mode, delay = False, 1, 20
        elif mode == 1:
            timer -= 1
            if tick == checkpoint_tick:
                flags |= 9
                mode, timer, hidden = 0, 60, True
                covered &= ~(1 << selected)
                disabled &= ~(1 << selected)
                selected = -1
            if timer == 0:
                matrix[:9] = [-4096, 0, 0, 0, 4096, 0, 0, 0, -4096]
                matrix[11] -= 100
                flags &= ~8
                disabled |= 1 << selected
                mode, timer = 2, 120
        elif mode == 2:
            timer -= 1
            if timer == -1:
                flags |= 9
                mode, timer, hidden = 0, 60, True
                covered &= ~(1 << selected)
                disabled &= ~(1 << selected)
                selected = -1
            else:
                delay -= 1
                if delay == 0:
                    delay, moving = 20, True
                if tick == hit_tick:
                    death, mode, timer = 10, 3, 60
        elif mode == 3:
            timer -= 1
            if timer == 0:
                flags |= 9
                mode, timer, hidden = 0, 60, True
                covered &= ~(1 << selected)
                disabled &= ~(1 << selected)
                selected = -1
        rows.append(dict(tick=tick, mode=mode, timer=timer, checkpoint=selected, delay=delay,
                         covered=covered, disabled=disabled, flags=flags, hidden=hidden,
                         matrix=matrix.copy(), rng=random, draws=draws, death=death, moving=moving))
    return dict(blocked=blocked, hit_tick=hit_tick, checkpoint_tick=checkpoint_tick, rows=rows)


def gold_frogs():
    cases = []
    for collected in [False, True]:
        mode, remaining, allocated, hidden = 0, 0, False, collected
        rows = []
        for tick in range(38):
            hit = not collected and tick in [1, 2, 20, 34]
            request = False
            if mode == 0 and hit:
                mode, remaining, allocated, hidden, request = 1, 32, True, True, True
            elif mode == 1 and allocated and remaining == 0:
                mode, allocated = 2, False
            remaining = max(0, remaining - 1)
            rows.append(dict(tick=tick, hit=hit, mode=mode, remaining=remaining,
                             allocated=allocated, hidden=hidden, request=request))
        cases.append(dict(collected=collected, rows=rows))
    return cases


def snakes():
    cases = []
    for snake_radius, log_radius, height, speed in [(20, 50, -32, 2048), (0, 40000, 40000, 8388608), (0, 0, -32769, -256)]:
        offset, direction, movement_range, initialized, moving = 0, 0, 0, False, False
        matrix = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]
        rows = []
        for tick in range(16):
            recreate = tick == 9
            if recreate:
                offset, direction, movement_range, initialized, moving = 0, 0, 0, False, False
                matrix = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]
            live = tick not in [3, 4, 9, 10]
            if not initialized:
                initialized, direction = True, 1
                movement_range = signed16(abs(snake_radius - log_radius))
                matrix[9:] = [100, 200, 300]
            if direction == 1:
                if offset >= movement_range:
                    direction = 0
            elif offset <= -movement_range:
                direction = 1
            offset = signed16(offset + (speed >> 8) * (1 if direction else -1))
            sign = 1 if direction else -1
            matrix[:9] = [sign * 4096, 0, 0, 0, 4096, 0, 0, 0, sign * 4096]
            if live:
                matrix[:9] = [0, 0, sign * 4096, 0, 4096, 0, -sign * 4096, 0, 0]
                matrix[9:] = [100 + offset, 200 + signed16(height), 300]
            request = not moving
            moving = True
            rows.append(dict(tick=tick, recreate=recreate, live=live, direction=direction,
                             range=movement_range, offset=offset, height=signed16(height),
                             hidden=not live, request=request, matrix=matrix.copy()))
        cases.append(dict(snake_radius=snake_radius, log_radius=log_radius,
                          height=height, speed=speed, rows=rows))
    return cases


def beavers():
    specifications = [
        dict(name='authored_order', mode=1, positions=[[0, 0, 0], [0, 0, 0]], order=[9, 5], ticks=2),
        dict(name='signed16_distance', mode=1, positions=[[65536, 0, 0], [1000, 0, 0]], ticks=2),
        dict(name='strict_radius', mode=1, positions=[[10, 0, 30], [1000, 0, 0]], ticks=2),
        dict(name='wait_end', mode=2, positions=[[1000, 0, 0], [1000, 0, 0]], ticks=5),
        dict(name='gap_other_log', mode=3, delay=2, positions=[[1000, 0, 0], [0, 0, 0]], ticks=3),
        dict(name='gap_unsigned_wrap', mode=3, delay=0, positions=[[1000, 0, 0], [1000, 0, 0]], ticks=3),
        dict(name='bite', mode=0, count=48, frog=261, positions=[[0, 0, 0], [1000, 0, 0]], ticks=24),
        dict(name='dive_boundary', mode=0, frog=262, positions=[[0, 0, 0], [1000, 0, 0]], ticks=35),
        dict(name='retired_parent', mode=0, live=False, positions=[[0, 0, 0], [1000, 0, 0]], ticks=3),
    ]
    for spec in specifications:
        mode, delay, timer, count, parent = spec['mode'], spec.get('delay', 0), 60, spec.get('count', 0), 5
        hidden, moving, action, one_shot, colour, ambient, faded = False, False, 0, False, [0, 0, 0], [0, 0, 0], False
        matrix_y = 0
        rows = []
        for tick in range(spec['ticks']):
            hit = -1
            reset, active, death, request = False, -1, -1, False
            if mode in [0, 4, 5]:
                matrix_y = 0
            if mode in [0, 1, 2, 3]:
                for identity in spec.get('order', [5, 9]):
                    position = spec['positions'][[5, 9].index(identity)]
                    delta = [signed16(-position[0]), signed16(matrix_y - position[1]), signed16(-position[2])]
                    squared = (sum(v * v for v in delta) + 2147483648) % 4294967296 - 2147483648
                    if squared < 1000:
                        hit = identity
                        break
            if mode == 1:
                active, hidden = 0, True
                if hit >= 0:
                    parent, mode = hit, 2
            elif mode == 2:
                if hit < 0:
                    delay, mode = 1, 3
            elif mode == 3:
                old_delay, delay = delay, (delay - 1) & 65535
                if old_delay:
                    if hit >= 0 and hit != parent:
                        mode = 1
                else:
                    mode, action, one_shot, active = 0, 0, False, 1
                    request, moving = not moving, True
            elif mode == 0:
                hidden = False
                if not spec.get('live', True):
                    mode, reset = 1, True
                elif hit == parent:
                    mode, delay = 5, 30
                    if spec.get('frog', 1000) < 262:
                        action, one_shot, death, timer, mode = 1, True, 10, 20, 4
                    else:
                        count = 0
            elif mode == 4:
                timer = (timer - 1) & 65535
                if timer == 0:
                    mode, reset = 1, True
            elif mode == 5:
                old_delay, delay = delay, (delay - 1) & 65535
                if old_delay == 0:
                    mode, reset, faded = 1, True, False
                else:
                    count = (count + 4) & 65535
                    matrix_y += count
                    height = -count
                    colour = [max(0, 128 + height) & 255, max(0, 128 - (height >> 1)) & 255, max(0, 128 - (height << 1)) & 255]
                    ambient, faded = [64, 64, 192], True
            rows.append(dict(tick=tick, mode=mode, delay=delay, timer=timer, count=count,
                             parent=parent, hidden=hidden, moving=moving, action=action,
                             one_shot=one_shot, colour=colour.copy(), ambient=ambient.copy(),
                             faded=faded, y=matrix_y, reset=reset, active=active, death=death, request=request))
        spec['rows'] = rows
    return specifications


def dogs():
    specifications = [
        dict(name='wait_postdecrement', mode=0, timer=2, ticks=3),
        dict(name='bark_strict_radius', mode=0, timer=0, distance=1024),
        dict(name='inactive_frog', mode=0, timer=0, frog_active=False),
        dict(name='unsigned_wait_wrap', mode=0, timer=0xffffffff),
        dict(name='bounce_then_random', mode=1, bounce=True),
        dict(name='bounce_then_fall', mode=1, bounce=True, seed=101),
        dict(name='fall_then_bite', mode=1, seed=101, hit=True),
        dict(name='fall_expiry_then_bite', mode=2, timer=1, hit=True),
        dict(name='fall_expiry', mode=2, timer=1),
        dict(name='bite_refresh', mode=3, count=1, hit=True),
        dict(name='bite_expiry', mode=3, count=1),
        dict(name='bite_unsigned_wrap', mode=3, count=0),
    ]
    for spec in specifications:
        mode, timer, count = spec['mode'], spec.get('timer', 2), spec.get('count', 0)
        rng, draws, action = spec.get('seed', 1), 0, spec.get('action', 0)
        rows = []
        for tick in range(spec.get('ticks', 1)):
            active, sounds, pose = -1, [], []
            hit = spec.get('hit', False)
            if mode == 0:
                old = timer
                timer = (timer - 1) & 0xffffffff
                if old == 0:
                    mode, active = 1, 1
                    if spec.get('frog_active', True) and spec.get('distance', 0) < 1024:
                        sounds.append(153)
            elif mode == 1:
                if spec.get('bounce', False):
                    mode, timer, active = 0, 2, 0
                rng = (rng * 1103515245 + 12345) & 0xffffffff
                draws += 1
                if ((rng >> 16) & 32767) % 500 == 1:
                    mode, timer, active, action = 2, 50, 0, 1
                if hit:
                    mode, active, action = 3, 0, 2
            elif mode == 2:
                timer = (timer - 1) & 0xffffffff
                if timer == 0:
                    mode, active, action = 1, 1, 0
                if hit:
                    mode, active, action = 3, 0, 2
            if mode == 3:
                if hit:
                    count = 50
                    sounds.append(154)
                    pose = [0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 0, 0, 192]
                else:
                    count = (count - 1) & 0xffffffff
                    if count == 0:
                        mode, active, action = 1, 1, 0
            rows.append(dict(tick=tick, mode=mode, timer=timer, count=count, rng=rng,
                             draws=draws, action=action, active=active, sounds=sounds, pose=pose))
        spec['rows'] = rows
    return specifications


if __name__ == '__main__':
    value = dict(schema='entity-custom-v1', crocodiles=[crocodile(0,-1,-1), crocodile(0,81,-1), crocodile(0,-1,30), crocodile(31,-1,-1)], gold_frogs=gold_frogs(), snakes=snakes(), beavers=beavers(), dogs=dogs())
    path = Path(__file__).resolve().parents[1] / 'tests/golden/synthetic/entity_custom.json'
    path.write_text(json.dumps(value, indent=2) + '\n')
