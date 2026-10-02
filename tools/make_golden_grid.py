#!/usr/bin/env python3
"""Independent frozen GRID.C integer facts; never reads Godot output."""
import argparse
import json
import math
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
import make_golden_map as maps


def retail(data_dir, output):
    archive=maps.archive
    cfg=archive.parse_cfg(str(archive.CFG_ROOT / 'versions' / 'pc-retail-v3.0e.cfg') if isinstance(archive.CFG_ROOT,Path) else
                          str(Path(archive.CFG_ROOT)/'versions'/'pc-retail-v3.0e.cfg'))
    _,entries,_,files=archive.load_archive(data_dir,archive.java_int(cfg.values['mwiOffset']),archive.java_int(cfg.values['mwiLength']))
    mwd=(Path(data_dir)/'FROGPSX.MWD').read_bytes()
    for entry in entries:
        if entry['type'] != 0 or entry['flags'] & archive.FLAG_GROUP_ACCESS: continue
        at=entry['sector']*archive.SECTOR_SIZE
        compressed=archive.is_compressed(entry['flags'])
        raw=mwd[at:at+(entry['packed'] if compressed else entry['unpacked'])]
        files[entry['index']]=archive.pp20_unpack(raw)[0] if compressed else raw
    rows=[]
    for rid,data in sorted(files.items()):
        name=archive.file_name(entries,rid)
        if not name.upper().endswith('.MAP') or data[:4]!=b'FROG': continue
        grap=maps.read(data,80,'<I')[0]
        _,_,poly,vert,grid,_=maps.read(data,grap+4,'<6I')
        dims=maps.read(data,grid+4,'<4H')
        stacks=[maps.read(data,grid+12+i*4,'<BBH') for i in range(dims[0]*dims[1])]
        count=sum(s[0] for s in stacks)
        pointers=maps.read(data,poly+24,'<9I'); counts=maps.read(data,poly+4,'<9H')
        addresses={}; index=0
        for ti in range(9):
            for pi in range(counts[ti]):
                addresses[pointers[ti]+pi*maps.SIZES[ti]]=index; index+=1
        records=[]; geometry=[]; heights=[]; centres=[]
        bx,bz=-(dims[0]*dims[2] >> 1),-(dims[1]*dims[3] >> 1)
        for si in range(count):
            at=grid+12+len(stacks)*4+si*8
            flags,ptr=maps.read(data,at,'<2I')
            records += [flags,ptr,addresses[ptr]]
            indices=maps.read(data,ptr,'<4H')
            vertices=[maps.read(data,vert+8+vi*8,'<3h') for vi in indices]
            geometry += indices+[v for p in vertices for v in p]
            avg=[sum(p[k] for p in vertices) >> 2 for k in range(3)]
            heights.append(avg[1])
            centres += [(((avg[0]-bx) >> 8) << 8)+128+bx,avg[1],(((avg[2]-bz) >> 8) << 8)+128+bz]
        rows.append([rid,name]+dims+[bx,bz,len(stacks),count,
                    archive.list_digest([v for s in stacks for v in s]),
                    archive.list_digest(records),archive.list_digest(geometry),
                    archive.list_digest(heights),archive.list_digest(centres)])
    if len(rows)!=78: raise ValueError('Expected 78 retail grids')
    maps.write(str(output),'grid_facts.tsv',['resource_id','name','x_count','z_count','x_length','z_length','base_x','base_z',
                'stack_count','square_count','stacks_sha256','squares_sha256','geometry_sha256','heights_sha256','centres_sha256'],rows)
    print('Generated independent GRID census for 78 retail maps.')


def normalize(v):
    length = math.sqrt(sum(x*x for x in v))
    if not length:
        return [0, 0, 0]
    return [int(math.copysign(math.floor(abs(x*4096/length)+0.5), x)) for x in v]


def signed32(value):
    return ((value+0x80000000)&0xffffffff)-0x80000000

def cross(a, b):
    return [signed32(a[1]*b[2]-a[2]*b[1]) >> 12,
            signed32(a[2]*b[0]-a[0]*b[2]) >> 12,
            signed32(a[0]*b[1]-a[1]*b[0]) >> 12]


def normal(v):
    edge = lambda a,b: [(v[a][i]-v[b][i]) << 4 for i in range(3)]
    n0 = normalize(cross(edge(2,0), edge(1,0)))
    if not any(edge(2,3)):
        return n0
    n1 = normalize(cross(edge(1,3), edge(2,3)))
    return normalize([(a+b) >> 1 for a,b in zip(n0,n1)])


def surface(v, x, z):
    a,b,c,d = [p[1] for p in v]
    dx,dz = x & 255,z & 255
    if dz >= dx:
        height = a + ((dx*(b-a)) >> 8) + (((256-dz)*(c-a)) >> 8)
        xs,zs = b-a,a-c
    else:
        height = d + (((256-dx)*(c-d)) >> 8) + ((dz*(b-d)) >> 8)
        xs,zs = d-c,b-d
    return [height] + normalize([256,xs,0]) + normalize([0,zs,256])


def fixture():
    quad = lambda x,z,ys: [[x,ys[0],z+256],[x+256,ys[1],z+256],
                           [x,ys[2],z],[x+256,ys[3],z]]
    squares = [quad(-512,-512,[-3,257,-131,121]),
               quad(-256,-512,[0,256,0,256]),
               quad(0,-512,[50]*4),quad(0,-512,[200]*4)]
    squares += [[[-500,100,-260],[-260,120,-260],[-510,80,-500],[-270,100,-510]],
                [squares[1][0],squares[1][1],squares[1][2],squares[1][2]]]
    stacks = [[1,0],[1,1],[2,2],[0,0]] + [[0,0]]*12
    queries = [[x,y,z] for x,z in [(-512,-512),(-511,-257),(-257,-511),
                (-385,-385),(-256,-512),(-128,-384),(-1,-257),(0,-512),
                (255,-257),(256,-512)] for y in [-100,50,200,201]]
    return dict(base=[-512,-512],dimensions=[4,4],stacks=stacks,
                squares=squares,queries=queries)

def odd_fixture():
    squares=[]
    for i in range(9):
        x,z=-384+(i%3)*256,-384+(i//3)*256
        squares.append([[x,0,z+256],[x+256,128,z+256],[x,-64,z],[x+256,32,z]])
    # Legal signed16 corners exercise source MR_SVEC centre narrowing separately.
    squares.append([[32767,32767,32767]]*4)
    stacks=[[1,i] for i in range(9)];stacks[8]=[2,8]
    queries=[[x,0,z] for x,z in [(-384,-384),(-256,-256),(-129,-129),(-128,-128),(-1,-1),(0,0),(128,128),(383,383)]]
    return dict(base=[-384,-384],dimensions=[3,3],stacks=stacks,squares=squares,queries=queries)


def width_fixture():
    squares=[
        [[-128,-32768,128],[128,32767,128],[-128,-32768,-128],[128,32767,-128]],
        [[-128,32767,128],[128,-32768,128],[-128,-32768,-128],[-128,-32768,-128]],
        [[-32768,-32768,32767],[32767,32767,32767],[-32768,32767,-32768],[32767,-32768,-32768]]]
    return dict(base=[-128,-128],dimensions=[1,1],stacks=[[3,0]],squares=squares,
                queries=[[-128,0,-128],[0,0,0],[127,32767,127],[2147483647,0,0],[-2147483648,0,0],[0,0,2147483647],[0,0,-2147483648]])

def answers(f):
    result=[]
    bx,bz=f['base']
    for i,v in enumerate(f['squares']):
        avg=[sum(p[k] for p in v) >> 2 for k in range(3)]
        centre=[(((avg[0]-bx) >> 8) << 8)+128+bx,avg[1],
                (((avg[2]-bz) >> 8) << 8)+128+bz]
        centre=[((value+32768)&65535)-32768 for value in centre]
        result.append(['S',i,avg[1]]+centre+normal(v))
    for i,(x,y,z) in enumerate(f['queries']):
        gx,gz=signed32(x-bx)>>8,signed32(z-bz)>>8
        if not (0<=gx<f['dimensions'][0] and 0<=gz<f['dimensions'][1]):
            result.append(['W',i,gx,gz]);continue
        count,start=f['stacks'][gz*f['dimensions'][0]+gx]
        if not count:
            result.append(['Q',i,0xbabe,-1]); continue
        selected=start
        for si in range(start+count-1,start-1,-1):
            if any(p[1]>=y for p in f['squares'][si]):
                selected=si; break
        result.append(['Q',i,surface(f['squares'][selected],x,z)[0],selected]
                      +surface(f['squares'][start],x,z))
    return result


def check_c(f, expected, executable):
    words=f['base']+f['dimensions']+[len(f['squares']),len(f['queries'])]
    for s in f['stacks']: words += s
    for s in f['squares']:
        for v in s: words += v
    for q in f['queries']: words += q
    proc=subprocess.run([executable],input=' '.join(map(str,words)),
                        text=True,capture_output=True,check=True)
    actual=[[row.split()[0]]+list(map(int,row.split()[1:]))
            for row in proc.stdout.splitlines()]
    if actual != expected:
        for a,b in zip(actual,expected):
            if a != b: raise ValueError('Frozen C disagreement: %r != %r' % (a,b))
        raise ValueError('Frozen C answer count disagreement')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--c-oracle',required=True)
    parser.add_argument('--output',default='tests/golden/synthetic/grid.json')
    parser.add_argument('--verify',action='store_true')
    parser.add_argument('--odd',action='store_true')
    parser.add_argument('--width',action='store_true')
    parser.add_argument('--retail-data-dir')
    parser.add_argument('--retail-output',default='tests/golden/pc-retail-v3.0e')
    args=parser.parse_args()
    f=width_fixture() if args.width else odd_fixture() if args.odd else fixture(); f['expected']=answers(f)
    check_c(f,f['expected'],args.c_oracle)
    target=Path(args.output)
    if args.verify:
        if json.loads(target.read_text()) != f: raise ValueError('Grid golden differs')
    else:
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(json.dumps(f,indent=2)+'\n')
    print('Frozen C overlap passed: %d square and %d query answers.' %
          (len(f['squares']),len(f['queries'])))
    if args.retail_data_dir: retail(args.retail_data_dir,Path(args.retail_output))


if __name__ == '__main__': main()
