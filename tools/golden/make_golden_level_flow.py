"""Independent gamesys.C/HUD.C single-start sprite and timer clocks."""
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT


def facts():
    cases = []
    for seconds in [5, 6, 20, 75, 99]:
        groups = [[[0, delay, duration] for delay in (5, 10, 15, 20, 25)] for duration in (30, 20)]
        enabled = [True, False]
        finished = [False, False, False]
        timer = 180
        rows = []
        while not all(finished):
            for group in range(2):
                if not enabled[group] or finished[group]:
                    continue
                all_done = True
                for sprite in groups[group]:
                    mode, counter, duration = sprite
                    if mode == 0:
                        counter -= 1
                        if counter == -1:
                            mode, counter = 1, duration
                        all_done = False
                    elif mode == 1:
                        counter -= 1
                        if counter == -1:
                            mode = 2
                        else:
                            all_done = False
                    sprite[:] = mode, counter, duration
                if all_done:
                    finished[group] = True
                    if group == 0:
                        enabled[1] = True
            if finished[0] and not finished[2]:
                if timer > seconds * 30:
                    timer, finished[2] = seconds * 30, True
                else:
                    timer += 30
            rows.append(dict(tick=len(rows) + 1, timer=timer, timer_finished=finished[2], playing=all(finished)))
        cases.append(dict(seconds=seconds, rows=rows))
    checkpoints = []
    for remaining, skips in [(value, []) for value in [0, 29, 30, 31, 750]] + [(750, [1]), (750, [32]), (750, [120]), (750, [1, 2, 3]), (30, [35])]:
        timer = remaining - remaining % 30
        collect_timer, return_timer = 31, 31
        bonus_enabled, return_enabled = False, False
        bonus_mode, bonus, score = 0, 0, 500
        rows = []
        while return_timer:
            skip = len(rows) + 1 in skips
            requested_skip = skip
            if collect_timer:
                if skip:
                    collect_timer = 1
                    skip = False
                collect_timer -= 1
                if collect_timer == 0:
                    bonus_enabled = True
            sound = -1
            if bonus_enabled:
                if skip:
                    skip = False
                    bonus_mode = 1
                    bonus += (timer // 30) * 100
                    timer = 0
                    sound = 3
                if bonus_mode == 0:
                    if timer:
                        if timer % 30 == 0:
                            bonus += 100
                            sound = 24
                        timer = max(0, timer - 10)
                    else:
                        bonus_mode = 1
                else:
                    score += bonus
                    bonus_enabled = False
                    return_enabled = True
            if return_enabled:
                if skip:
                    return_timer = 1
                return_timer -= 1
            rows.append(dict(tick=len(rows) + 1, timer=timer, bonus=bonus,
                             score=score, sound=sound, skip=requested_skip, finished=return_timer == 0))
        checkpoints.append(dict(remaining=remaining, skips=skips, rows=rows))
    return dict(schema='level-flow-v1', start=cases, checkpoint=checkpoints)


if __name__ == '__main__':
    destination = REPO_ROOT / 'tests/golden/synthetic/level_flow.json'
    destination.write_text(json.dumps(facts(), indent=2) + '\n')
