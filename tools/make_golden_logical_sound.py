"""Independent MR_SOUND voice transitions and frozen native sample-clock facts."""
import json
import math
from pathlib import Path


def generate():
    cases = []
    for flags in [2, 4, 8]:
        for length in [1, 183, 184, 1470]:
            random, draws, ident = 1, 0, 1
            voice = None
            rows = []
            for tick in range(12):
                tag = -2
                if tick in [0, 3, 7]:
                    tag = -1
                    if voice is None:
                        random = (random * 1103515245 + 12345) & 0xffffffff
                        draws += 1
                        fine = ((random >> 16) & 32767) & 59
                        step = math.floor(11025 * 2 ** ((fine / 128) / 12) * 65536 / 44100 + .5)
                        voice = dict(pos=0, step=step, base=step, playing=True, initialising=True, pitch=64)
                        tag = ident << 16
                        ident += 1
                if tick == 4 and voice:
                    voice['pitch'] = 96
                    voice['step'] = math.floor(voice['base'] * 2 ** ((32/64*2)/12) + .5)
                if voice:
                    if voice['playing']:
                        if flags == 8:
                            voice['pos'] = (voice['pos'] + voice['step'] * 735) % (length << 16)
                        else:
                            for _ in range(735):
                                if voice['pos'] >= length << 16:
                                    voice['playing'] = False
                                    break
                                voice['pos'] += voice['step']
                    if voice['initialising']:
                        voice['initialising'] = False
                    elif not voice['playing']:
                        if flags == 4:
                            voice.update(pos=0, step=voice['base'], playing=True, initialising=True, pitch=64)
                        else:
                            voice = None
                rows.append(dict(tick=tick, tag=tag, rng=random, draws=draws, allocated=voice is not None, **(voice or {})))
            cases.append(dict(flags=flags, length=length, rows=rows))
    killed_cases = []
    for flags in [2, 4, 8]:
        for fresh in [False, True]:
            occupied, initialising = True, fresh
            rows = []
            for tick in range(3):
                rows.append(dict(occupied=occupied, allocation=-1 if occupied else 131072))
                if initialising:
                    initialising = False
                else:
                    occupied = False
            killed_cases.append(dict(flags=flags, fresh=fresh, rows=rows))
    return dict(schema='logical-sound-v1', cases=cases, killed_cases=killed_cases)


if __name__ == '__main__':
    target = Path(__file__).resolve().parents[1] / 'tests/golden/synthetic/logical_sound.json'
    target.write_text(json.dumps(generate(), indent=2) + '\n')
