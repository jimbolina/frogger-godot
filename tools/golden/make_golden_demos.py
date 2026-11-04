#!/usr/bin/env python3
"""Independent FrogLord PC demo-header and decoded-input summary facts."""
import argparse
import hashlib
from pathlib import Path
import struct
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden.make_golden_exe_tables import CFG_ROOT, Exe, find_demo_table, java_int, parse_cfg, read_demo_tables
from tools.golden.make_golden_manifest import is_compressed, pp20_unpack, read_mwi


def demo_facts(payload):
    """Decode signed header and summarize the entire stored unsigned-byte buffer."""
    if len(payload) < 12:
        raise ValueError("demo header is shorter than 12 bytes")
    duration, x, z = struct.unpack_from('<iii', payload)
    if min(duration, x, z) < 0:
        raise ValueError("negative demo duration or coordinate")
    inputs = payload[12:]
    digest = hashlib.sha256(','.join(map(str, inputs)).encode('ascii')).hexdigest()
    return [duration, x, z, len(inputs), digest, sum(bool(b & 128) for b in inputs),
            *(sum((b & 3) == direction and not b & 128 for b in inputs) for direction in range(4)),
            *(sum(bool(b & (1 << bit)) for b in inputs) for bit in range(2, 7))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('data_dir', type=Path)
    parser.add_argument('output_dir', type=Path)
    parser.add_argument('--version', default='pc-retail-v3.0e')
    args = parser.parse_args()
    version = parse_cfg(str(Path(CFG_ROOT) / 'versions' / (args.version + '.cfg'))).values
    exe_bytes = (args.data_dir / 'FROGGER.EXE').read_bytes()
    offset, length = (java_int(version[key]) for key in ('mwiOffset', 'mwiLength'))
    entries = read_mwi(exe_bytes[offset:offset + length])
    exe = Exe(exe_bytes, java_int(version['ramOffset']))
    table_offset, low = find_demo_table(exe, entries)
    if table_offset < 0:
        raise ValueError('no demo table found')
    tables = read_demo_tables(exe, table_offset, low)
    archive = (args.data_dir / 'FROGPSX.MWD').read_bytes()
    rows = []
    for detail, table in zip(('low', 'high') if low else ('high',), tables):
        for level, rid, unlock in table:
            if min(level, rid, unlock) < 0:
                continue
            entry = entries[rid]
            size = entry['packed'] if is_compressed(entry['flags']) else entry['unpacked']
            payload = archive[entry['sector'] * 2048:entry['sector'] * 2048 + size]
            if len(payload) != size:
                raise ValueError('truncated resource %d' % rid)
            if is_compressed(entry['flags']):
                payload, _ = pp20_unpack(payload)
            rows.append([detail, level, rid, *demo_facts(payload)])
    args.output_dir.mkdir(parents=True, exist_ok=True)
    header = 'detail level resource duration start_x start_z input_count input_digest skip up right down left unused super_hop tongue camera_ccw camera_cw'.split()
    output = '#' + '\t'.join(header) + '\n' + ''.join('\t'.join(map(str, row)) + '\n' for row in rows)
    (args.output_dir / 'demos.tsv').write_text(output, encoding='utf-8')
    print('Wrote %d demo facts' % len(rows))


if __name__ == '__main__':
    main()
