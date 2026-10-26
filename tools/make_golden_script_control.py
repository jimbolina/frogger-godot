#!/usr/bin/env python3
"""Independent text facts for frozen scripter.c control-flow and sound semantics."""
import argparse
import json
from pathlib import Path

from org1_script_state import Script

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'tests/golden/synthetic/script_control.json'
IDENTITY = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]


def cases():
    """Invented instruction streams; no player executable bytes or programs."""
    def case(name, words, ticks=6, **extra):
        return dict(name=name, programs={'1': words}, inputs=[{} for _ in range(ticks)], **extra)
    result = [
        case('animation_end', [3, 1, 1, 4, 65549, 6], 9),
        case('loop_break', [11, 14, 0, 3, 4, 14, 12, 4, 15, 6]),
        case('register_break', [31, 12, 3, 11, 14, 1, 0, 12, 6], registers=[2, 4, 0]),
        case('end_callback_once_more', [34, 0, 1, 7, 1, 6]),
        case('gosub_restore', [11, 13, 1, 9, 2, 0, 4, 14, 12, 6], child=[4, 13, 6]),
        case('gosub_conditional_return', [13, 1, 9, 2, 0, 4, 14, 6], child=[11, 20, 4, 4, 15, 12, 6]),
        case('nested_single_return_slot', [13, 1, 9, 2, 0, 4, 14, 6], child=[13, 1, 9, 3, 0, 4, 15, 6], grandchild=[4, 16, 6]),
        case('stop_deviation', [8, 0, 1, 128, 2048, -1, 0, 0, 2, 30, 6]),
        case('clear_deviation', [8, 0, 1, 128, 2048, -1, 0, 0, 2, 32, 6]),
        case('random_sound', [11, 10, 65549, 65539, 12, 5], 12),
        case('negative_sound_divisor', [11, 10, 13, -3, 12, 5], 12),
        case('path_wait_pause_resume', [2, 15, 0, 0, 3, 16, 6]),
    ]
    result[5]['inputs'][2]['carry'] = True
    result[9]['inputs'][0]['allocation'] = False
    result[9]['inputs'][4]['allocation'] = False
    result[-1]['inputs'][1]['path_flags'] = 1 << 20
    result[-1]['inputs'][2]['path_flags'] = 1 << 17
    for mode in range(10):
        item = case(f'branch_condition_{mode}', [13, 0, mode, 2, 2, 4, 14, 6], 3, child=[4, 15, 6])
        item['inputs'][0] = dict(hit=True, carry=True, path_flags=1 << 18)
        result.append(item)
    for mode in (0, 1, 2, 3, 4, 5, 7, 8, 9):
        item = case(f'return_condition_{mode}', [20, mode, 4, 14, 6], 3)
        item['inputs'][0] = dict(hit=True, carry=True, path_flags=1 << 18)
        result.append(item)
    return result


def facts():
    result = []
    for fixture in cases():
        programs = {int(key): value for key, value in fixture['programs'].items()}
        if 'child' in fixture:
            programs[2] = fixture.pop('child')
        if 'grandchild' in fixture:
            programs[3] = fixture.pop('grandchild')
        fixture['programs'] = {str(key): value for key, value in programs.items()}
        registers = fixture.get('registers', [])
        script = Script(programs, 1, registers, [3, 4])
        seed = 1
        rows = []
        for supplied in fixture['inputs']:
            seed, _, _, _ = script.update(seed, IDENTITY, [0, 0, 0], **supplied)
            script.advance_animation()
            rows.append(dict(active=script.active, program=script.program, cursor=script.cursor,
                             loop_start=script.start, loop_end=script.end, timer=script.timer,
                             deviation=script.deviation, delta=script.delta, destination=script.destination,
                             remaining=script.remaining, action=script.action, cel=script.cel, rng=seed,
                             return_frame=list(script.return_frame) if script.return_frame else [],
                             path_active_request=script.path_active_request, requests=list(script.requests)))
        fixture['expected'] = rows
        result.append(fixture)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(facts(), indent=2) + '\n'
    if args.write:
        OUTPUT.write_text(text, encoding='utf-8')
    elif OUTPUT.read_text(encoding='utf-8') != text:
        raise ValueError('Script control golden differs from independent source model')
    print('Script control facts verified against independent Python source model.')


if __name__ == '__main__':
    main()
