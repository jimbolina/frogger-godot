#!/usr/bin/env python3
"""Golden collision-primitive and animated primitive-part facts for a retail install.

An independent, standard-library-only reading written from FrogLord's
collprim/MRCollprim and mof2/MRMofPart, the frozen MR_COLLPRIM and MR_MAT
layouts (MR_COLL.H, MR_SYS.H) and MR_ANIM.C's stored-LW actual cels. It reuses
the independent archive, model and animation readers in make_golden_mof.py and
make_golden_animation.py and shares no code with the Godot project.

mof_collprims.tsv has one row per collision primitive a part effectively holds;
a part of an incomplete model borrows its counterpart's primitives and matrices
(model.C borrows mp_collprim_ptr and mp_matrix_ptr). A part's matrix count is
what fits before its next section, and matrices_sha256 is the list digest of
every matrix's nine rotation shorts then three translation longs (the pad
short is dropped).

animation_primitive_poses.tsv has, for each action of the animated models with
primitives, the first part holding primitives, the list digest of its actual
cels (virtual cel numbers less one unless the file starts at frame zero) and the
list digest of its sampled part matrices (twelve values per virtual cel).

No model bytes are written. Usage:
    python3 tools/golden/make_golden_collprims.py <dir with FROGGER.EXE and FROGPSX.MWD> <out dir>
"""
import argparse
import os
import struct
import sys

sys.dont_write_bytecode = True
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden import make_golden_mof as mof
from tools.golden import make_golden_animation as anim

POSE_MODELS = (314, 318, 351, 355)


def static_starts(data, model):
    if model['kind'] != 'animated':
        return [0]
    table_at = struct.unpack_from('<I', data, 24)[0]
    return list(struct.unpack_from('<%dI' % len(model['statics']), data, table_at))


def own_part(data, base, part):
    """Primitives and matrices stored by one complete part."""
    prims = []
    if part['collprim_ptr']:
        at = base + part['collprim_ptr']
        while True:
            (kind, flags, run0, run1, ox, oy, oz, _pad, radius2, sx, sy, sz, user,
             matrix_index) = struct.unpack_from('<HHIIhhhhiHHHHi', data, at)
            if run0 or run1:
                raise mof.MofError('collision primitive run-time words are not zero')
            prims.append((kind, flags, ox, oy, oz, radius2, sx, sy, sz, user, matrix_index))
            at += 32
            if flags & mof.COLLPRIM_LAST_IN_LIST:
                break
    matrices = []
    for index in range(part['matrices']):
        values = struct.unpack_from('<9hh3i', data, base + part['matrix_ptr'] + 32 * index)
        matrices.append(list(values[:9]) + list(values[10:13]))
    return prims, matrices


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('data_dir')
    ap.add_argument('out_dir')
    ap.add_argument('--version', default='pc-retail-v3.0e')
    args = ap.parse_args()
    cfg = mof.parse_cfg(os.path.join(mof.CFG_ROOT, 'versions', args.version + '.cfg'))
    offsets = {k: mof.java_int(cfg.values[k].strip()) for k in ('mwiOffset', 'mwiLength')}
    _exe, entries, wads, files = mof.load_archive(args.data_dir, offsets['mwiOffset'], offsets['mwiLength'])
    ids = sorted({rid for children in wads.values() for rid, t in children if t in (mof.TYPE_MOF, mof.TYPE_MAPMOF)})
    parsed, effective = {}, {}
    prim_rows, pose_rows = [], []
    for rid in ids:
        previous = next((i for i in reversed(list(parsed)) if not parsed[i]['incomplete']), None)
        data = files[rid]
        model = mof.parse_model(data, str(rid), parsed.get(previous), [])
        parsed[rid] = model
        effective[rid] = []
        for static_index, (base, static) in enumerate(zip(static_starts(data, model), model['statics'])):
            parts = []
            for part_index, part in enumerate(static['parts']):
                if static['incomplete']:
                    prims, matrices = effective[previous][static_index][part_index]
                    borrowed = 1
                else:
                    prims, matrices = own_part(data, base, part)
                    borrowed = 0
                parts.append((prims, matrices))
                digest = mof.list_digest([v for m in matrices for v in m])
                for prim_index, p in enumerate(prims):
                    kind, flags, ox, oy, oz, radius2, sx, sy, sz, user, matrix_index = p
                    prim_rows.append((rid, mof.file_name(entries, rid), static_index, part_index, borrowed, prim_index,
                                      kind, flags, '%d,%d,%d' % (ox, oy, oz), radius2, '%d,%d,%d' % (sx, sy, sz), user,
                                      matrix_index, len(matrices), digest))
            effective[rid].append(parts)
        if rid in POSE_MODELS:
            xar = anim.parse_xar(data)
            if len(xar['sets']) != 1 or len(xar['sets'][0][0]) != 1:
                raise mof.MofError('%d: expected one model set with one model' % rid)
            primitive_part = next(i for i, (prims, _m) in enumerate(effective[rid][0]) if prims)
            actions = xar['sets'][0][1]
            for action_index, action in enumerate(actions):
                if action['flags'] != 1 or not action['valid']:
                    raise mof.MofError('%d action %d: not a valid discrete action' % (rid, action_index))
                actual = [cel - (0 if xar['zero'] else 1) for cel in action['cels']]
                poses = [v for frame in range(action['frames']) for v in anim.sampled_matrix(xar, action, frame, primitive_part)]
                pose_rows.append((rid, mof.file_name(entries, rid), action_index, action['frames'], primitive_part,
                                  mof.list_digest(actual), mof.list_digest(poses)))
    os.makedirs(args.out_dir, exist_ok=True)

    def write(name, header, rows):
        with open(os.path.join(args.out_dir, name), 'w', encoding='utf-8', newline='\n') as f:
            f.write('# ' + '\t'.join(header) + '\n')
            for row in rows:
                f.write('\t'.join(str(c) for c in row) + '\n')

    write('mof_collprims.tsv', ['resource_id', 'name', 'static_model', 'part', 'borrowed', 'primitive', 'type', 'flags',
                                'offset', 'radius_squared', 'extents', 'user', 'matrix_index', 'matrices',
                                'matrices_sha256'], prim_rows)
    write('animation_primitive_poses.tsv', ['resource_id', 'name', 'action', 'frames', 'primitive_part',
                                            'actual_cels_sha256', 'part_poses_sha256'], pose_rows)
    print('collprims=%d pose_actions=%d' % (len(prim_rows), len(pose_rows)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
