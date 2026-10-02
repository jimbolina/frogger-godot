#!/usr/bin/env python3
"""Compare represented integer ControlFrog/MoveFrog component fields exactly."""
import argparse
import csv
from pathlib import Path
import sys

FIELDS = 'scenario,tick,component,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,input,direction,animation_requests,sound_requests,score_requests,buffered_keys,buffered_input_count,pad_pressed,pad_held'.split(',')


def read(path,scenario=None,reference=False):
    with Path(path).open(encoding='utf-8-sig',newline='') as stream:
        reader=csv.DictReader(stream)
        if reader.fieldnames != FIELDS:
            raise ValueError('%s: schema differs from represented component fields' % path)
        rows=[]
        for i,row in enumerate(reader):
            if None in row or any(v is None for v in row.values()):
                raise ValueError('%s: malformed row %d' % (path,i+2))
            for field in FIELDS:
                if field != 'component':
                    try: row[field]=int(row[field])
                    except ValueError: raise ValueError('%s: row %d %s is not an integer' % (path,i+2,field))
            rows.append(row)
    if scenario is not None:
        if reference:
            full_keys=[(r['scenario'],r['tick'],r['component']) for r in rows]
            canonical=[(s,t,c) for s in range(3) for t in range(16) for c in ('control','move')]
            if full_keys!=canonical: raise ValueError('%s: reference must contain all 96 ordered component records' % path)
            rows=[r for r in rows if r['scenario']==scenario]
        elif any(r['scenario']!=scenario for r in rows):
            raise ValueError('%s: candidate contains other scenarios under explicit --scenario' % path)
    scenarios=range(3) if scenario is None else [scenario]
    expected_keys=[(s,t,c) for s in scenarios for t in range(16) for c in ('control','move')]
    keys=[(r['scenario'],r['tick'],r['component']) for r in rows]
    if keys != expected_keys:
        for i in range(max(len(keys),len(expected_keys))):
            want=expected_keys[i] if i<len(expected_keys) else '<no extra row>'
            got=keys[i] if i<len(keys) else '<missing row>'
            if want != got:
                raise ValueError('%s: row %d missing/extra/reordered component: expected %r, got %r' % (path,i+2,want,got))
    return rows


def compare(expected,actual,scenario=None):
    a,b=read(expected,scenario,reference=True),read(actual,scenario)
    for i,(want,got) in enumerate(zip(a,b)):
        for field in FIELDS:
            if want[field] != got[field]:
                key=(want['scenario'],want['tick'],want['component'])
                recent=[{name: row[name] for name in ('scenario','tick','component','pad_pressed','pad_held','grid_x','grid_z')}
                        for row in b[max(0,i-5):i+1]]
                raise ValueError('row %d scenario/tick/component=%r field=%s expected=%r actual=%r\nRecent candidate commands/grid: %r\nRNG consumers: excluded from this component schema' %
                                 (i+2,key,field,want[field],got[field],recent))
    return len(a)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('expected')
    parser.add_argument('actual')
    parser.add_argument('--candidate-command',default='<not supplied>')
    parser.add_argument('--scenario',type=int,choices=range(3))
    args=parser.parse_args()
    try:
        count=compare(args.expected,args.actual,args.scenario)
    except (ValueError,OSError) as error:
        print('Terrain component trace mismatch: %s\nCandidate command: %s' % (error,args.candidate_command),file=sys.stderr)
        return 1
    print('%d component records match every represented integer field.' % count)
    return 0


if __name__ == '__main__': sys.exit(main())
