"""Independent v3.0e sound table and Windows bank duration facts; never writes assets."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT
from tools.golden.make_golden_manifest import read_mwi, is_compressed, pp20_unpack


def facts(folder):
    exe = (folder / 'FROGGER.EXE').read_bytes()
    archive = (folder / 'FROGPSX.MWD').read_bytes()
    index = read_mwi(exe[0x8ae20:0x8ae20+48840])
    banks = [list(struct.unpack_from('<ii', exe, 0x6e890+i*12)) for i in range(12)]
    groups = [list(struct.unpack_from('<hh', exe, 0x6e920+i*4)) for i in range(4)]
    samples = [list(struct.unpack_from('<I8H', exe, 0x6e938+i*32)) for i in range(174)]
    music_pitches = [list(struct.unpack_from('<ii', exe, 0x6ff20+i*8)) for i in range(60)]
    headers = []
    for bank_id, (header_id, body_id) in enumerate(banks):
        if header_id < 0:
            continue
        entry = index[header_id]
        size = entry['packed'] if is_compressed(entry['flags']) else entry['unpacked']
        raw = archive[entry['sector']*2048:entry['sector']*2048+size]
        data = pp20_unpack(raw)[0] if is_compressed(entry['flags']) else raw
        count, = struct.unpack_from('<i', data)
        rows = []
        for sound_id in range(count):
            present, offset, size, a, b, rate, bits = struct.unpack_from('<7i', data, 4+sound_id*28)
            assert a == b == 1 and bits == 16
            if present == 1:
                assert offset + size <= index[body_id]['unpacked'] and samples[sound_id][1] == bank_id
                rows.append([sound_id, offset, size, rate, bits, size//2])
        headers.append(dict(bank_id=bank_id, header_id=header_id, body_id=body_id, count=count, rows=rows))
    init_offset = 0x42358b - 0x401000 + 1024
    code = exe[init_offset:init_offset+20]
    assert code[0] == code[5] == code[10] == 0x68
    assert [struct.unpack_from('<I',code,i)[0] for i in [1,6,11]] == [0x46f938,0x46f920,0x46f890]
    return dict(schema='sound-tables-v1', initialization=dict(address=0x42358b,file_offset=init_offset,length=20,sha256=hashlib.sha256(code).hexdigest()), banks=banks,groups=groups,samples=samples,headers=headers,music_pitches=music_pitches)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir',required=True,type=Path)
    args=parser.parse_args()
    target=REPO_ROOT/'tests/golden/pc-retail-v3.0e/sound_tables.json'
    target.write_text(json.dumps(facts(args.data_dir),indent=2)+'\n')
