"""Independent frozen ent_gen.c BONUS_FLY frame, voice-gate and RNG facts."""
import json
import math
from pathlib import Path


def sine(angle):
    value = math.sin((angle % 4096) * math.tau / 4096) * 4096
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def generate():
    cases = []
    for uid in [-32768, -1, 0, 7, 32767]:
        for active in [False, True]:
            for stopped in [False, True]:
                random, draws, y = 1, 0, 32760
                rows = []
                for frame in [0, 1, 7, 16, 31, 63, 64, 65535, 65536, 65537, 0xffffffff]:
                    pitch = -1
                    if not stopped:
                        angle = (((uid & 7) << 7) + ((frame & 65535) << 6)) & 4095
                        y = 32760 + (sine(angle) >> 6) + 64
                        if active:
                            random = (random * 1103515245 + 12345) & 0xffffffff
                            pitch = 64 - (((random >> 16) & 32767) & 15)
                            random = (random * 1103515245 + 12345) & 0xffffffff
                            pitch += (((random >> 16) & 32767) & 3) * 8
                            pitch -= sine(frame << 8) >> 8
                            draws += 2
                    rows.append(dict(frame=frame, y=y, pitch=pitch, rng=random, draws=draws))
                cases.append(dict(uid=uid, active=active, stopped=stopped, rows=rows))
    return dict(schema="bonus-fly-v1", reward_ids=[1, 2, 3, 5, 7, 9, 10, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23], cases=cases)


if __name__ == "__main__":
    target = Path(__file__).resolve().parents[1] / "tests/golden/synthetic/bonus_fly.json"
    target.write_text(json.dumps(generate(), indent=2) + "\n")
