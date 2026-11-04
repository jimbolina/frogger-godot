#!/usr/bin/env python3
"""Independent facts for the default high-score tables in a retail FROGGER.EXE.

Reads Game_high_score (10 rows) and Level_high_scores (60 levels x 3 rows)
from the executable at the v3.0e addresses. Each record is HSView.h's
HIGH_SCORE_ENTRY: he_initials[4] (three letters and a zero), the 32-bit
he_score and five 16-bit he_time_to_checkpoint values, padded to 20 bytes.
The program address is turned into a file offset with the build's
ramOffset from archive/third_party/froglord_cfg, as make_golden_exe_tables.py does.

With --c-reference (default ../froggy/engine/vendor/frogger-psx-src/source)
the HSView.c initialisers are parsed (the non-DEBUG branches, 'Z'+1,
octal 00100, (60*12)+34) and compared with the executable row by row. The
retail rows known to differ from the C are listed in DEVIATIONS; any other
difference fails. See tests/golden/specs/frontend.md#default-high-scores.

Initials are written with printable ASCII 0x21..0x7E other than a backslash
as themselves and every other byte as \\xNN (lower-case hex), so '[' stays
'[' and a space is written \\x20.

Usage:
    python3 tools/golden/make_golden_high_scores.py <dir with FROGGER.EXE> [--check] [--c-reference DIR]
"""
import argparse
import ast
import difflib
import os
import re
import struct
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT
from tools.golden.make_golden_exe_tables import CFG_ROOT, Exe, LEVEL_CODES, java_int, parse_cfg

ROOT = REPO_ROOT
OUT = ROOT / 'tests' / 'golden' / 'pc-retail-v3.0e' / 'exe_high_scores.tsv'
DEFAULT_C = ROOT.parent / 'froggy' / 'engine' / 'vendor' / 'frogger-psx-src' / 'source'
VERSION = 'pc-retail-v3.0e'

MAIN_POINTER = 0x477400
LEVEL_POINTER = 0x4774C8
MAIN_COUNT = 10
LEVEL_COUNT = 60
LEVEL_RANKS = 3
TIMES = 5
ENTRY_SIZE = 20
DEVIATIONS = {
    54: (('STU', 'ORG', 'SKY'), ('SEC', 'ORG', 'SKY')),
    56: (('FOR', 'MAP', 'SEC'), ('STU', 'MAP', 'FOR')),
}


def encode_initials(raw):
    out = []
    for byte in raw:
        out.append(chr(byte) if 0x21 <= byte <= 0x7E and byte != 0x5C else '\\x%02x' % byte)
    return ''.join(out)


def read_entries(exe, pointer, count, label, problems):
    rows = []
    base = exe.file_offset(pointer)
    for index in range(count):
        offset = base + index * ENTRY_SIZE
        if offset < 0 or offset + ENTRY_SIZE > exe.length:
            raise IndexError('%s[%d] at 0x%X outside the program' % (label, index, pointer + index * ENTRY_SIZE))
        raw = exe.data[offset:offset + ENTRY_SIZE]
        initials = raw[0:3]
        score = struct.unpack_from('<I', raw, 4)[0]
        times = list(struct.unpack_from('<5H', raw, 8))
        if raw[3] != 0:
            problems.append('%s[%d] initials are not zero-terminated' % (label, index))
        if raw[18:20] != b'\0\0':
            problems.append('%s[%d] padding is not zero' % (label, index))
        rows.append((initials, score, times))
    return rows


def read_tables(data_dir):
    ver = parse_cfg(os.path.join(CFG_ROOT, 'versions', VERSION + '.cfg'))
    data = open(os.path.join(data_dir, 'FROGGER.EXE'), 'rb').read()
    exe = Exe(data, java_int(ver.values['ramOffset'].strip()))
    problems = []
    main = read_entries(exe, MAIN_POINTER, MAIN_COUNT, 'Game_high_score', problems)
    levels = read_entries(exe, LEVEL_POINTER, LEVEL_COUNT * LEVEL_RANKS, 'Level_high_scores', problems)
    if MAIN_POINTER + MAIN_COUNT * ENTRY_SIZE != LEVEL_POINTER:
        problems.append('Level_high_scores does not follow Game_high_score')
    for level, (_, retail) in sorted(DEVIATIONS.items()):
        got = tuple(levels[level * LEVEL_RANKS + rank][0].decode('latin-1') for rank in range(LEVEL_RANKS))
        if got != retail:
            problems.append('level %d initials %s, expected the recorded retail %s' % (level, got, retail))
    return main, levels, problems


def document(main, levels):
    lines = [
        '# Default high-score tables read from FROGGER.EXE (tools/golden/make_golden_high_scores.py).',
        '# entry rows: kind=entry, table (main|level), level (-1 for main), rank, initials, score, time_0..time_4',
        '# initials: printable ASCII except backslash as itself, other bytes as \\xNN',
        '# fact rows: kind=fact, name, value',
        '# deviation rows: kind=deviation, level, code, retail initials (comma-joined), HSView.c initials',
    ]
    for rank, (initials, score, times) in enumerate(main):
        lines.append('\t'.join(['entry', 'main', '-1', str(rank), encode_initials(initials), str(score)]
                               + [str(t) for t in times]))
    for index, (initials, score, times) in enumerate(levels):
        level, rank = divmod(index, LEVEL_RANKS)
        lines.append('\t'.join(['entry', 'level', str(level), str(rank), encode_initials(initials), str(score)]
                               + [str(t) for t in times]))
    for name, value in [('main_pointer', '0x%X' % MAIN_POINTER), ('level_pointer', '0x%X' % LEVEL_POINTER),
                        ('main_count', MAIN_COUNT), ('level_count', LEVEL_COUNT), ('level_ranks', LEVEL_RANKS),
                        ('entry_size', ENTRY_SIZE), ('times_per_row', TIMES)]:
        lines.append('\t'.join(['fact', name, str(value)]))
    for level in sorted(DEVIATIONS):
        c_rows, retail_rows = DEVIATIONS[level]
        lines.append('\t'.join(['deviation', str(level), LEVEL_CODES[level], ','.join(retail_rows), ','.join(c_rows)]))
    return '\n'.join(lines) + '\n'


def c_value(expression):
    text = re.sub(r'\b0([0-7]+)\b', lambda m: str(int(m.group(1), 8)), expression.strip())
    return _eval(ast.parse(text, mode='eval').body)


def _eval(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, int):
        return node.value
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub, ast.Mult)):
        left, right = _eval(node.left), _eval(node.right)
        return left + right if isinstance(node.op, ast.Add) else left - right if isinstance(node.op, ast.Sub) \
            else left * right
    raise ValueError('unsupported C expression: %s' % ast.dump(node))


def non_debug(text):
    out, stack = [], []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith('#ifdef DEBUG'):
            stack.append(False)
        elif stripped.startswith('#else') and stack:
            stack[-1] = not stack[-1]
        elif stripped.startswith('#endif') and stack:
            stack.pop()
        elif all(stack):
            out.append(line)
    return '\n'.join(out)


def c_entries(text, name):
    start = re.search(r'HIGH_SCORE_ENTRY\s+' + name + r'\[[^=]*=', text)
    if start is None:
        raise ValueError('%s initialiser not found' % name)
    end = text.index('};', start.end())
    body = re.sub(r'//[^\n]*', '', text[start.end():end])
    body = re.sub(r"'(.)'", lambda m: str(ord(m.group(1))), body)
    rows = []
    for match in re.finditer(r'\{([^{}]*)\}', body):
        values = [c_value(part) for part in match.group(1).split(',') if part.strip()]
        values += [0] * (4 + 1 + TIMES - len(values))
        rows.append((bytes(values[0:3]), values[4], values[5:5 + TIMES]))
    return rows


def check_c(c_root, main, levels):
    problems, notes = [], []
    text = non_debug((Path(c_root) / 'HSView.c').read_text(encoding='latin-1'))
    c_main = c_entries(text, 'Game_high_score')
    c_levels = c_entries(text, 'Level_high_scores')
    if len(c_main) != MAIN_COUNT or len(c_levels) != LEVEL_COUNT * LEVEL_RANKS:
        return ['HSView.c gives %d main and %d level rows' % (len(c_main), len(c_levels))], notes
    for rank, (want, got) in enumerate(zip(c_main, main)):
        if want != got:
            problems.append('main rank %d: HSView.c %r, EXE %r' % (rank, want, got))
    seen = set()
    for index, (want, got) in enumerate(zip(c_levels, levels)):
        level, rank = divmod(index, LEVEL_RANKS)
        if want == got:
            continue
        expected = DEVIATIONS.get(level)
        if expected and want[0].decode() == expected[0][rank] and got[0].decode() == expected[1][rank] \
                and want[1:] == got[1:]:
            seen.add(level)
            continue
        problems.append('level %d rank %d: HSView.c %r, EXE %r' % (level, rank, want, got))
    for level in sorted(DEVIATIONS):
        if level in seen:
            notes.append('level %d (%s): retail %s, HSView.c %s (expected deviation)' % (
                level, LEVEL_CODES[level], ','.join(DEVIATIONS[level][1]), ','.join(DEVIATIONS[level][0])))
        else:
            problems.append('expected deviation at level %d not found' % level)
    return problems, notes


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('data_dir', help='folder holding FROGGER.EXE')
    parser.add_argument('--c-reference', type=Path, default=DEFAULT_C,
                        help='frozen C source folder (default: ../froggy/engine/vendor/frogger-psx-src/source)')
    parser.add_argument('--check', action='store_true', help='compare with the committed file instead of writing')
    args = parser.parse_args()
    main_rows, level_rows, problems = read_tables(args.data_dir)
    for problem in problems:
        print('EXE check: ' + problem)
    if problems:
        sys.exit(1)
    if args.c_reference.is_dir():
        c_problems, notes = check_c(args.c_reference, main_rows, level_rows)
        for note in notes:
            print('C cross-check: ' + note)
        for problem in c_problems:
            print('C cross-check FAILED: ' + problem)
        if c_problems:
            sys.exit(1)
        print('C cross-check passed against %s' % args.c_reference)
    else:
        print('C source not found at %s; cross-checks skipped' % args.c_reference)
    text = document(main_rows, level_rows)
    if args.check:
        old = OUT.read_text(encoding='utf-8') if OUT.exists() else ''
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                       str(OUT), 'generated', n=0))
        print('Committed facts differ from the generator' if old != text else 'Committed facts match the generator')
        sys.exit(1 if old != text else 0)
    OUT.write_text(text, encoding='utf-8')
    print('Wrote %s (%d main rows, %d level rows)' % (OUT.relative_to(ROOT), len(main_rows), len(level_rows)))


if __name__ == '__main__':
    main()
