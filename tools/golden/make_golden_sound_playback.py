#!/usr/bin/env python3
"""Independent synthetic sound playback facts from frozen MR_SOUND.C, sound.c, FROG.C and the native backend.

Sources, all under ../froggy/engine (read-only):
- vendor/frogger-psx-src/source/API.SRC/MR_SOUND.C: MRSNDPlaySound 320-447
  (note/fine from the pitch offset 375-393, voice identifiers 398-400, fixed
  volume from si_max_volume 403-412), MRSNDUpdateSound 468-541 (REPEAT re-key
  and SINGLE release), MRSNDPitchBend 651-668, MRSNDKillSound 775,
  MRSNDCreateMovingSound default flags and radii 922-990 and
  MRSNDUpdateMovingSounds 1069-1202 (radius 1090, fade 1136-1144,
  pan 1160-1176, doppler bend 1186-1198).
- vendor/frogger-psx-src/source/API.SRC/MR_SOUND.H: voice flags 53-56,
  moving-sound flags and default radii 76-89, MRSND_SAMPLE_INFO volumes 138-139.
- vendor/frogger-psx-src/source/sound.c: PlaySoundDistance 366-443 only gates
  MRSNDPlaySound(sfx, NULL, 0, 0) at 441, so a fixed sound plays at
  si_max_volume on both channels; PlayMovingSound 466-503 overrides the radii.
- vendor/frogger-psx-src/source/FROG.C:347: the listener is the frog's
  translation and matrix.
- mr_stub/src/backend/mr_stub_snd.c: snd_step_q16 827-833 and
  snd_apply_bend_q16 840-854 (11025 Hz at note 60, 44100 Hz output, two-semitone
  bend centred on 64), LOOPED whole-sample wrap and REPEAT left to
  MRSNDUpdateSound 949-960, 16-bit body decode 920-937;
  mr_stub/src/gpu/mr_stub_math.c: ApplyTransposeMatrixLV 155-161 and
  VectorNormal 313-327 (lround, zero vector stays zero).
- FrogLord SCWindowsSoundBankHeader.java:89: 8-bit Windows samples are
  unsigned PCM, 16-bit samples signed little-endian.

The port widens 8-bit samples as (u - 128) << 8. Arithmetic follows C:
arithmetic right shifts, truncating division and u16 radius and volume wraps.
Trigonometry uses the shared rounded 12-bit table of make_golden_paths.py.
"""
import argparse
import hashlib
import math
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT
from tools.golden import make_golden_paths as paths
from tools.golden import make_golden_swamp as swamp

ROOT = REPO_ROOT
OUTPUT = ROOT / 'tests/golden/synthetic/sound_playback.json'
BASE_NOTE, REF_RATE, MIX_RATE = 60, 11025, 44100
BEND_CENTRE, BEND_SEMITONES = 64, 2
SINGLE, REPEAT, LOOPED = 2, 4, 8
DEFAULT_MIN_RADIUS, DEFAULT_MAX_RADIUS = 0x0700, 0x1c00


def s32(value):
    return paths.signed(value, 32)


def c_div(a, b):
    return paths.divided(a, b)


def c_round(value):
    return int(math.floor(value + 0.5))


def digest(values):
    return hashlib.sha256(','.join(str(v) for v in values).encode()).hexdigest()


def pitch_case(note, fine, bend):
    ratio = 2.0 ** ((float(note - BASE_NOTE) + float(fine) / 128.0) / 12.0)
    bend_ratio = 1.0 if bend == BEND_CENTRE else 2.0 ** (
        (float(bend - BEND_CENTRE) / float(BEND_CENTRE)) * float(BEND_SEMITONES) / 12.0)
    base_step = max(1, c_round(float(REF_RATE) * ratio * 65536.0 / float(MIX_RATE)))
    step = base_step if bend == BEND_CENTRE else max(1, c_round(float(base_step) * bend_ratio))
    return dict(note=note, fine=fine, bend=bend, ratio=ratio, bend_ratio=bend_ratio, pitch_scale=ratio * bend_ratio,
                rate_hz=REF_RATE * ratio * bend_ratio, base_step_16=base_step, step_16=step)


def pitch_cases():
    rows = []
    for note, fine in ((60, 0), (60, 64), (60, 127), (48, 0), (72, 0), (66, 32), (36, 5), (84, 100), (0, 0), (127, 127)):
        for bend in (64, 0, 32, 96, 127):
            rows.append(pitch_case(note, fine, bend))
    return rows


def radius_of(delta):
    reduced = [v >> 4 for v in delta]
    squared = sum(v * v for v in reduced)
    if squared > 0x7fffffff:
        raise ValueError('squared radius leaves MR_LONG')
    return (math.isqrt(squared) << 4) & 0xffff


def transpose_apply(matrix, vector):
    return [s32(sum(matrix[3 * k + row] * vector[k] for k in range(3)) >> 12) for row in range(3)]


def y_matrix(angle):
    cos, sin = paths.trig(angle)
    return [cos, 0, sin, 0, 4096, 0, -sin, 0, cos]


def moving_volume(source, listener, matrix, min_radius, max_radius, min_volume, max_volume, fade=True, pan=True):
    vec = [s32(a - b) for a, b in zip(source, listener)]
    radius = radius_of(vec)
    clamped = min(max(radius, min_radius), max_radius)
    angle = c_div(1024 * (clamped - min_radius), max_radius - min_radius)
    if fade:
        volume = ((4096 - paths.trig(angle)[1]) * (max_volume - min_volume)) >> 7
        volume = (volume + (min_volume << 5)) & 0xffff
    else:
        volume = (max_volume << 5) & 0xffff
    if pan:
        panvec = transpose_apply(matrix, paths.normalised(vec))
        pan_x = max(0, min(8191, panvec[0] + 4096))
        right, left = (volume * pan_x) >> 18, (volume * (8191 - pan_x)) >> 18
    else:
        pan_x = None
        right = left = volume >> 5
    return dict(source=source, listener=listener, matrix=matrix, min_radius=min_radius, max_radius=max_radius,
                min_volume=min_volume, max_volume=max_volume, fade=fade, pan=pan, radius=radius,
                in_range=radius <= max_radius, clamped_radius=clamped, angle=angle, volume_12=volume,
                pan_x=pan_x, left=left, right=right)


def volume_cases():
    identity = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096]
    turned = y_matrix(0x400)
    tilted = y_matrix(0x200)
    rows = [
        moving_volume([0, 0, 0], [0, 0, 0], identity, DEFAULT_MIN_RADIUS, DEFAULT_MAX_RADIUS, 0, 127),
        moving_volume([0x600, 0, 0], [0, 0, 0], identity, DEFAULT_MIN_RADIUS, DEFAULT_MAX_RADIUS, 0, 127),
        moving_volume([-0x600, 0, 0], [0, 0, 0], identity, DEFAULT_MIN_RADIUS, DEFAULT_MAX_RADIUS, 0, 127),
        moving_volume([0x1000, 0, 0x800], [0x100, 0, -0x100], identity, DEFAULT_MIN_RADIUS, DEFAULT_MAX_RADIUS, 20, 110),
        moving_volume([0, -0x200, 0x1400], [0, 0, 0], identity, DEFAULT_MIN_RADIUS, DEFAULT_MAX_RADIUS, 10, 90),
        moving_volume([0x1c00, 0, 0], [0, 0, 0], identity, DEFAULT_MIN_RADIUS, DEFAULT_MAX_RADIUS, 15, 127),
        moving_volume([0x1c10, 0, 0], [0, 0, 0], identity, DEFAULT_MIN_RADIUS, DEFAULT_MAX_RADIUS, 15, 127),
        moving_volume([0x3000, 0x40, -0x2000], [0x80, 0, 0x40], identity, DEFAULT_MIN_RADIUS, DEFAULT_MAX_RADIUS, 0, 100),
        moving_volume([0x900, 0, 0], [0, 0, 0], turned, DEFAULT_MIN_RADIUS, DEFAULT_MAX_RADIUS, 0, 127),
        moving_volume([0, 0, 0x900], [0, 0, 0], turned, DEFAULT_MIN_RADIUS, DEFAULT_MAX_RADIUS, 0, 127),
        moving_volume([0x700, 0x100, 0x700], [-0x40, 0x20, 0x10], tilted, 0x400, 0x2000, 40, 120),
        moving_volume([0x500, 0, 0xc00], [0, 0, 0], identity, 0x200, 0x1000, 64, 64),
        moving_volume([0x1800, 0, 0], [0, 0, 0], identity, 0x300, 0x3000, 0, 127),
        moving_volume([-0x2000, 0x300, 0x900], [0x100, 0x100, 0x100], tilted, 0x300, 0x3000, 5, 127),
        moving_volume([300, 64, 2367], [0, 0, 0], identity, 0x100, 0x2000, 0, 127),
        moving_volume([337, 64, 936], [0, 0, 0], identity, 0x100, 0x2000, 0, 127),
        moving_volume([300, 64, 2473], [0, 0, 0], tilted, 0x100, 0x2000, 0, 127),
    ]
    rows.append(dict(fixed=True, min_volume=30, max_volume=100, left=100, right=100))
    rows.append(dict(fixed=True, min_volume=0, max_volume=127, left=127, right=127))
    return rows


BODY_SIZE = 40


def body_bytes():
    return [(index * 73 + 41) & 0xff for index in range(BODY_SIZE)]


def pcm_case(present, offset, size, bits):
    body = body_bytes()
    row = dict(present=present, offset=offset, size=size, bits=bits)
    if not present:
        return dict(row, error='absent')
    if offset < 0 or size <= 0 or offset > BODY_SIZE or size > BODY_SIZE - offset:
        return dict(row, error='span')
    if size % (bits // 8):
        return dict(row, error='partial')
    data = body[offset:offset + size]
    if bits == 16:
        samples = [paths.signed(data[i] | (data[i + 1] << 8), 16) for i in range(0, size, 2)]
    else:
        samples = [(value - 128) << 8 for value in data]
    return dict(row, error='', frames=len(samples), samples=samples, digest=digest(samples))


def pcm_cases():
    return dict(body_rule='byte i = (i * 73 + 41) & 255', body_size=BODY_SIZE, body_digest=digest(body_bytes()),
                rows=[pcm_case(True, 0, 8, 16), pcm_case(True, 10, 6, 16), pcm_case(True, 3, 5, 8),
                      pcm_case(True, 32, 8, 8), pcm_case(True, 38, 2, 16), pcm_case(False, 0, 8, 16),
                      pcm_case(True, 36, 8, 16), pcm_case(True, 41, 0, 8), pcm_case(True, 4, 0, 16),
                      pcm_case(True, 4, 7, 16)])


def loop_cases():
    rows = []
    for flags in (SINGLE, REPEAT, LOOPED):
        for frames in (1, 183, 22050):
            rows.append(dict(flags=flags, frames=frames, wraps_in_mixer=flags == LOOPED,
                             retriggers=flags == REPEAT, loop=flags in (REPEAT, LOOPED), loop_begin=0,
                             loop_end=frames if flags in (REPEAT, LOOPED) else 0))
    return rows


SAMPLE_FLAGS = {0: SINGLE, 1: SINGLE, 2: REPEAT, 3: LOOPED, 4: SINGLE, 5: LOOPED}


def voice(slot, sample, identifier, note=60, fine=0, pitch=64, playing=True, killed=False):
    return dict(slot=slot, sample=sample, identifier=identifier, note=note, fine=fine, pitch=pitch,
                playing=playing, killed=killed)


def diff(before, after, tracked):
    """One committed tick: start on a new identifier, bend on a pitch change, stop killed or silent loops.

    A one-shot that stops playing is left to finish; its slot is released once
    the voice is retired or replaced without a kill.
    """
    old = {v['slot']: v for v in before}
    new = {v['slot']: v for v in after}
    actions = []
    for slot in range(24):
        b, a = old.get(slot), new.get(slot)
        live = a is not None and a['sample'] is not None and not a['killed']
        held = tracked.get(slot)
        if live and a['playing'] and (b is None or b['sample'] is None or b['identifier'] != a['identifier']):
            tracked[slot] = dict(identifier=a['identifier'], pitch=a['pitch'], loops=SAMPLE_FLAGS[a['sample']] != SINGLE)
            actions.append(dict(slot=slot, action='start', sample=a['sample'], identifier=a['identifier'],
                                note=a['note'], fine=a['fine'], pitch=a['pitch']))
        elif live and held is not None and held['identifier'] == a['identifier']:
            if not a['playing'] and held['loops']:
                del tracked[slot]
                actions.append(dict(slot=slot, action='stop'))
            elif a['pitch'] != held['pitch']:
                held['pitch'] = a['pitch']
                actions.append(dict(slot=slot, action='bend', note=a['note'], fine=a['fine'], pitch=a['pitch']))
        elif held is not None:
            del tracked[slot]
            replaced = a is not None and a['sample'] is not None and a['identifier'] != held['identifier']
            stopped = (a is not None and a['killed']) or held['loops'] or replaced
            actions.append(dict(slot=slot, action='stop' if stopped else 'release'))
    return actions


def voice_diff_cases():
    sequences = [
        ('start_bend_finish', [
            [],
            [voice(0, 0, 1, 62, 5)],
            [voice(0, 0, 1, 62, 5)],
            [voice(0, 0, 1, 62, 5, 96)],
            [voice(0, 0, 1, 62, 5, 96, playing=False)],
            [voice(0, 0, 1, 62, 5, 96, playing=False)],
            []]),
        ('killed_and_retired', [
            [],
            [voice(3, 1, 7), voice(5, 4, 8, 55)],
            [voice(3, 1, 7, killed=True, playing=False), voice(5, 4, 8, 55)],
            [voice(5, 4, 8, 55)],
            [voice(5, None, 8, 55, playing=False)],
            []]),
        ('slot_reuse', [
            [],
            [voice(2, 0, 10)],
            [voice(2, 1, 11, 64, 12)],
            [voice(2, 1, 11, 64, 12)],
            [voice(2, 0, 12, 60, 0, 40)],
            [voice(2, 0, 12, 60, 0, 30), voice(4, 0, 13)]]),
        ('loops_and_doppler', [
            [],
            [voice(8, 3, 20, 58, 3), voice(23, 2, 21)],
            [voice(8, 3, 20, 58, 3, 70), voice(23, 2, 21)],
            [voice(8, 3, 20, 58, 3, 0), voice(23, 2, 21, pitch=127)],
            [voice(8, 3, 20, 58, 3, 0), voice(23, 2, 22)],
            [voice(8, 3, 20, 58, 3, 64, killed=True, playing=False), voice(23, 2, 22)],
            [voice(23, 2, 22, playing=False)],
            []]),
        ('silent_loop_and_release', [
            [],
            [voice(6, 5, 30), voice(7, 4, 31)],
            [voice(6, 5, 30, playing=False), voice(7, 4, 31, playing=False)],
            [voice(7, None, 31, playing=False)],
            [voice(7, 4, 32)]]),
    ]
    rows = []
    for name, ticks in sequences:
        steps, tracked = [], {}
        for index in range(1, len(ticks)):
            steps.append(dict(tick=index, before=ticks[index - 1], after=ticks[index],
                              actions=diff(ticks[index - 1], ticks[index], tracked)))
        rows.append(dict(name=name, steps=steps))
    return dict(sample_flags=[[k, v] for k, v in sorted(SAMPLE_FLAGS.items())], sequences=rows)


def cases():
    return dict(schema='sound-playback-v1', reference=dict(base_note=BASE_NOTE, reference_rate=REF_RATE,
                                                            mix_rate=MIX_RATE, bend_centre=BEND_CENTRE,
                                                            bend_semitones=BEND_SEMITONES),
                pitch=pitch_cases(), volume=volume_cases(), pcm=pcm_cases(), loop=loop_cases(),
                voice_diff=voice_diff_cases())


def main():
    """Verify reproducibility by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = swamp.encode(cases()) + '\n'
    if args.write:
        OUTPUT.write_text(text)
    elif OUTPUT.read_text() != text:
        raise SystemExit('Sound playback facts differ; use --write only to deliberately regenerate')
    print('Sound playback facts verified')


if __name__ == '__main__':
    main()
