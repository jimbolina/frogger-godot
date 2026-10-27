"""Independent frozen EFFECTS.C and MR_SPLIN.C tongue clock/curve facts."""
import json
from pathlib import Path


def signed(value, bits):
    return (value + (1 << (bits - 1))) % (1 << bits) - (1 << (bits - 1))


def curve(matrix, section, target):
    def short(v):
        return [signed(x, 16) for x in v]
    def transform(v):
        return [signed(sum(matrix[r * 3 + c] * v[c] for c in range(3)), 32) >> 12 for r in range(3)]
    origin = matrix[9:]
    offset = transform([0, -32, 48])
    p1 = short([a + b for a, b in zip(origin, offset)])
    if target is not None:
        p4 = short(target)
        p2 = short([p1[a] + (matrix[a * 3 + 2] >> 4) for a in range(3)])
        p3 = [(a + b) >> 1 for a, b in zip(p4, p2)]
    else:
        p4 = short([a + b for a, b in zip(origin, transform([8, -80, 48]))])
        p2 = short([p1[a] + (matrix[a * 3 + 2] >> 5) + (matrix[a * 3] >> 5) for a in range(3)])
        p3 = short([p1[a] + (matrix[a * 3 + 2] >> 5) - (matrix[a * 3] >> 5) for a in range(3)])
    t = section * 256
    t2 = signed(t * t, 32) >> 3
    t3 = signed(t2 * t, 32) >> 11
    result = []
    for axis in range(3):
        u, v, big_u, big_v = p1[axis] >> 3, signed((p2[axis] >> 3) * 3, 16), signed((p3[axis] >> 3) * 3, 16), p4[axis] >> 3
        a, d = -u + v - big_u + big_v, u
        u = signed(u * 3, 16)
        b, c = u - 2 * v + big_u, -u + v
        result.append(signed((signed(t3 * a, 32) >> 16) + (signed(t2 * b, 32) >> 16) + (signed(t * c, 32) >> 8) + (d << 3), 16))
    return result


def facts():
    result = []
    for name, matrix, target in [
        ('target', [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 128, -7, 128], [333, -100, 601]),
        ('eyes', [0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 512, 17, -128], None),
        ('narrow', [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 32767, -32760, 65539], [65540, 32780, -65539]),
    ]:
        mode, section, counter = 1, 0, 0
        position = target
        rows = []
        for tick in range(1, 26):
            collected = False
            active = mode != 0
            if mode == 1:
                section += 1
                if section == 8:
                    mode, counter = 2, 4 if target is not None else 8
            elif mode == 2:
                counter -= 1
                if counter == 0:
                    mode = 3
            elif mode == 3:
                section -= 1
                if section == 0:
                    mode, collected = 0, target is not None
            tip = curve(matrix, section, position) if active else rows[-1]['tip']
            if position is not None and active and (mode == 3 or collected):
                position = tip
            rows.append(dict(tick=tick, mode=mode, section=section, counter=counter, collected=collected, tip=tip))
        result.append(dict(name=name, matrix=matrix, target=target, rows=rows))
    return dict(schema='tongue-v1', cases=result)


if __name__ == '__main__':
    path = Path(__file__).resolve().parents[1] / 'tests/golden/synthetic/tongue.json'
    path.write_text(json.dumps(facts(), indent=2) + '\n')
