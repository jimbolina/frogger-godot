#!/usr/bin/env python3
"""Independent animation facts, from FrogLord's mof2/animation and the C MR API.

Uses the existing independent archive/static-model readers, never GDScript.
Only counts, identifiers and digests are written; no retail asset bytes.
Usage: python tools/golden/make_golden_animation.py RETAIL_DIR OUTPUT_DIR
"""
import argparse
import collections
import math
import os
import struct
import sys

sys.dont_write_bytecode = True
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden import make_golden_mof as mof


def values_hash(values):
    return mof.list_digest(list(values))


def read_at(data, position, fmt):
    if position < 0 or position + struct.calcsize(fmt) > len(data):
        raise ValueError("animation read outside file: %d %s" % (position, fmt))
    return struct.unpack_from(fmt, data, position)


def signed_short(value):
    return (value + 32768) % 65536 - 32768


def matrix_from_transform(code, values):
    """MRQuaternion[B]ToMatrix and MR_SCALE_MATRIX, in 4.12 integer space."""
    if code < 2:
        matrix = [x << 5 if code == 1 else x for x in values[:9]]
        return matrix + values[9:12]
    w, x, y, z = values[:4]
    shift = 0 if code in (2, 4) else 12
    wx, wy, wz = 2*w*x, 2*w*y, 2*w*z
    xx, xy, xz, yy, yz, zz = 2*x*x, 2*x*y, 2*x*z, 2*y*y, 2*y*z, 2*z*z
    matrix = [4096-((yy+zz) >> shift), (xy+wz) >> shift, (xz-wy) >> shift,
              (xy-wz) >> shift, 4096-((xx+zz) >> shift), (yz+wx) >> shift,
              (xz+wy) >> shift, (yz-wx) >> shift, 4096-((xx+yy) >> shift)]
    matrix = [signed_short(v) for v in matrix]
    if code >= 4 and values[10] & 1:
        matrix = [(v * (values[7+i // 3] << 7)) >> 12 for i, v in enumerate(matrix)]
    return [signed_short(v) for v in matrix] + values[4:7]


def parse_xar(data):
    sets_count, static_count, sets_at, common_at, _ = read_at(data, 12, '<HHIII')
    code = data[1] - 48
    formats = ['<12h', '<9bx3h', '<4b3h', '<7h', '<4b3h4b', '<7h4b']
    if not 0 <= code < len(formats):
        raise ValueError('unsupported transform encoding %d' % code)
    flags, count, rotations, translations, box_count, trans_at, rp, tp, box_at = read_at(data, common_at, '<I4H4I')
    if (flags, rotations, translations, rp, tp) != (9, 0, 0, 0, 0):
        raise ValueError('unsupported common animation data')
    raw = [list(read_at(data, trans_at+i*struct.calcsize(formats[code]), formats[code])) for i in range(count)]
    transforms = [matrix_from_transform(code, v) for v in raw]
    shared_boxes = [read_at(data, box_at+64*i, '<32h') for i in range(box_count)]
    sets = []
    for si in range(sets_count):
        kind, models, cels, boxes, padding, model_at, cel_at, boxes_at = read_at(data, sets_at+20*si, '<I4B3I')
        if kind or cels != 1 or boxes:
            raise ValueError('unsupported model set')
        model_entries = []
        for mi in range(models):
            entry = read_at(data, model_at+24*mi, '<4H4I')
            anim_type, mf, parts, static_id, action_at, bbox_at, bbox_set, constraint = entry
            if anim_type != 1 or action_at != cel_at or constraint or bbox_set:
                raise ValueError('unsupported animation model')
            box = tuple(v for j,v in enumerate(read_at(data, bbox_at, '<32h')) if j % 4 != 3) if mf & 1 else ()
            model_entries.append((static_id, parts, mf, box))
        action_count, _, actions_at = read_at(data, cel_at, '<HHI')
        actions = []
        for ai in range(action_count):
            unique, parts, frames, af, cnums_at, indices_at = read_at(data, actions_at+16*ai, '<4H2I')
            cnums = list(read_at(data, cnums_at, '<%dH' % (frames*(3 if af == 2 else 1))))
            indices = list(read_at(data, indices_at, '<%dh' % (unique*parts)))
            endpoints = [n for j,n in enumerate(cnums) if af != 2 or j % 3 != 2]
            base = 0 if data[0] == 49 or af == 2 else 1
            valid = (af in (1,2) and (af != 2 or code >= 2) and unique > 0 and frames > 0 and
                     all(0 <= n-base < unique for n in endpoints) and
                     all(0 <= n < count for n in indices) and
                     (af != 2 or all(0 <= n <= 4096 for n in cnums[2::3])))
            actions.append(dict(unique=unique,parts=parts,frames=frames,flags=af,cels=cnums,
                                indices=indices,valid=valid))
        sets.append((model_entries, actions))
    return dict(code=code,zero=data[0]==49,raw=raw,transforms=transforms,sets=sets,boxes=shared_boxes,
                static_count=static_count)


def sampled_matrix(xar, action, frame, part):
    cells, indices = action['cels'], action['indices']
    if action['flags'] == 1:
        cel = cells[frame] - (0 if xar['zero'] else 1)
        return xar['transforms'][indices[cel*action['parts']+part]]
    previous, following, weight = cells[frame*3:frame*3+3]
    a = xar['raw'][indices[previous*action['parts']+part]]
    b = xar['raw'][indices[following*action['parts']+part]]
    byte_quaternion = xar['code'] in (2, 4)
    qa = [v << 6 if byte_quaternion else v for v in a[:4]]
    qb = [v << 6 if byte_quaternion else v for v in b[:4]]
    dot = signed_short(sum(x*y for x,y in zip(qa,qb)) >> 12)
    flip = -1 if dot < 0 else 1
    cosine = min(abs(dot) / 4096, 1)
    u = weight / 4096
    if weight == 0:
        q = qa
    elif weight == 4096:
        q = [signed_short(flip*v) for v in qb]
    else:
        start, end = 1-u, u
        if 4096-abs(dot) > 1:
            angle = math.acos(cosine)
            end = math.sin(u*angle)/math.sin(angle)
            start = math.cos(u*angle)-cosine*end
        q = [signed_short(math.floor(start*x+flip*end*y)) for x,y in zip(qa,qb)]
    if weight and byte_quaternion:
        divisor = min(4128, max(4064, math.isqrt(sum(v*v for v in q))))
        factor = (1 << 24) // divisor
        q = [signed_short((v*factor) >> 12) for v in q]
    interpolated = q + [((x*(4096-weight)+y*weight) >> 12) for x,y in zip(a[4:7],b[4:7])]
    matrix = matrix_from_transform(3, interpolated)
    if xar['code'] >= 4 and (a[10] | b[10]) & 1:
        scales = [((x*(4096-weight)+y*weight) >> 5) for x,y in zip(a[7:10],b[7:10])]
        matrix[:9] = [signed_short((v*scales[i//3]) >> 12) for i,v in enumerate(matrix[:9])]
    return matrix


def side_data(data, static, counterpart):
    """Retain effective side data, with original partcel/polygon order."""
    parts = []
    for pi,p in enumerate(static['parts']):
        if static['incomplete']:
            parts.append(counterpart[pi])
            continue
        flips = []
        if p['flipbook_ptr']:
            _, count = read_at(data,p['flipbook_ptr'],'<HH')
            for ai in range(count):
                frames,start = read_at(data,p['flipbook_ptr']+4+ai*4,'<HH')
                flips.append((start,frames,int(frames > 0 and start+frames <= p['partcels'])))
        targets, lists = [], []
        if p['anim_ptr']:
            count, = read_at(data,p['anim_ptr'],'<i')
            raw_targets = [read_at(data,p['anim_ptr']+4+i*16,'<4i') for i in range(count)]
            end = min(x for x in (p['flipbook_ptr'],p['prim_ptr']) if x > p['anim_ptr'])
            cur = p['anim_ptr']+4+count*16
            locations = {}
            while cur < end:
                locations[cur] = len(lists)
                count, = read_at(data,cur,'<i'); cur += 4
                entries = [read_at(data,cur+4*i,'<hH') for i in range(count)]
                lists.append(entries); cur += count*4
            if cur != end:
                raise ValueError('texture animation block end mismatch')
            targets = [(kind,index,locations[ptr]) for kind,index,_,ptr in raw_targets]
        parts.append((flips,targets,lists))
    return parts


def texture_cycle(entries):
    result = []
    entry = elapsed = 0
    for _ in range(sum(max(d,1) for _,d in entries)+1):
        elapsed += 1
        if elapsed >= entries[entry][1]:
            elapsed = 0
            entry = (entry+1) % len(entries)
        result.extend((entry,entries[entry][0]))
    return result


def generate(retail, out_dir):
    cfg = mof.parse_cfg(os.path.join(mof.CFG_ROOT,'versions','pc-retail-v3.0e.cfg'))
    offsets = {k:mof.java_int(cfg.values[k].strip()) for k in ('mwiOffset','mwiLength')}
    _,entries,wads,files = mof.load_archive(retail,offsets['mwiOffset'],offsets['mwiLength'])
    ids = sorted({rid for children in wads.values() for rid,t in children if t in (mof.TYPE_MOF,mof.TYPE_MAPMOF)})
    rows = {name:[] for name in ('xar','actions','parts','flipbooks','texture_cycles')}
    totals = collections.Counter()
    parsed,side = {},{}
    for rid in ids:
        previous = next((i for i in reversed(list(parsed)) if not parsed[i]['incomplete']),None)
        b = files[rid]
        model = mof.parse_model(b,str(rid),parsed.get(previous),[])
        parsed[rid] = model; totals['models'] += 1
        xar = parse_xar(b) if model['kind']=='animated' else None
        if xar:
            totals['animated'] += 1; totals['transforms'] += len(xar['raw'])
            totals['transform_code_%d'%xar['code']] += 1
            metadata = []
            for models,actions in xar['sets']:
                metadata.extend((len(models),len(actions)))
                for sid,pc,mf,box in models:
                    metadata.extend((sid,pc,mf,len(box))); metadata.extend(box)
            rows['xar'].append((rid,xar['code'],int(xar['zero']),len(xar['sets']),len(xar['raw']),
                                values_hash(v for a in xar['raw'] for v in a),values_hash(metadata)))
            for si,(models,actions) in enumerate(xar['sets']):
                for sid,pc,_,_ in models:
                    for ai,a in enumerate(actions):
                        valid = a['valid'] and a['parts'] >= pc
                        samples = [v for f in range(a['frames']) for p in range(pc) for v in sampled_matrix(xar,a,f,p)] if valid else []
                        rows['actions'].append((rid,sid,si,ai,a['unique'],a['parts'],a['frames'],a['flags'],
                            int(valid),values_hash(a['cels']),values_hash(a['indices']),values_hash(samples)))
                        totals['actions'] += 1; totals['virtual_frames'] += a['frames']
        starts = ([0] if model['kind']=='static' else
                  list(read_at(b,read_at(b,24,'<I')[0],'<%dI'%len(model['statics']))) if xar else [])
        side[rid] = []
        for mi,(start,static) in enumerate(zip(starts,model['statics'])):
            effective = side_data(b[start:],static,side[previous][mi] if static['incomplete'] else None)
            side[rid].append(effective)
            for pi,(p,(flips,targets,lists)) in enumerate(zip(static['parts'],effective)):
                geometry_part = parsed[previous]['statics'][mi]['parts'][pi] if static['incomplete'] else p
                geometry = []
                for cel in geometry_part['partcel_list']:
                    for key in ('vertices','normals','box'):
                        geometry.append(len(cel[key])); geometry.extend(cel[key])
                fv = [v for start,count,valid in flips for v in (start,count)]
                lv = [v for ls in lists for v in [len(ls)]+[n for pair in ls for n in pair]]
                rows['parts'].append((rid,mi,pi,int(static['incomplete']),len(geometry_part['partcel_list']),
                    values_hash(geometry),values_hash(fv),values_hash(v for t in targets for v in t),values_hash(lv)))
                for ai,(start,count,valid) in enumerate(flips):
                    rows['flipbooks'].append((rid,mi,pi,ai,start,count,valid))
                    if not static['incomplete']:
                        totals['flipbook_actions'] += 1; totals['unsafe_flipbook_actions'] += 1-valid
                for ti,(_,_,li) in enumerate(targets):
                    seq = lists[li]
                    rows['texture_cycles'].append((rid,mi,pi,ti,li,sum(max(d,1) for _,d in seq),values_hash(texture_cycle(seq))))
                    if not static['incomplete']:
                        totals['texture_targets'] += 1
    headers = {
        'xar':'resource code zero_based sets transforms transforms_sha256 model_metadata_sha256',
        'actions':'resource static set action unique parts frames flags valid cels_sha256 indices_sha256 poses_sha256',
        'parts':'resource static part inherited partcels geometry_sha256 flipbook_sha256 targets_sha256 lists_sha256',
        'flipbooks':'resource static part action start frames valid',
        'texture_cycles':'resource static part target list duration cycle_sha256',
    }
    os.makedirs(out_dir,exist_ok=True)
    for name,table in rows.items():
        with open(os.path.join(out_dir,'animation_'+name+'.tsv'),'w',encoding='utf-8',newline='\n') as f:
            f.write('# '+headers[name].replace(' ','\t')+'\n')
            for row in table:
                f.write('\t'.join(map(str,row))+'\n')
    with open(os.path.join(out_dir,'animation_summary.txt'),'w',encoding='utf-8',newline='\n') as f:
        for key,value in sorted(totals.items()):
            f.write('%s=%d\n'%(key,value))
    print(dict(totals))
    print({name:len(table) for name,table in rows.items()})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('retail_dir'); parser.add_argument('out_dir')
    args = parser.parse_args()
    generate(args.retail_dir,args.out_dir)
