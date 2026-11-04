#!/usr/bin/env python3
"""Independent outward-hop prefix; stop before frozen unbounded final lookup."""
import argparse,csv,io,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden.make_golden_terrain_special import FIELDS,trunc
from tools.golden.make_golden_grid import normalize,cross

def expected():
    for scenario,index in enumerate([13,7,1,4]):
        cell=[index%4,index//4];delta=[[0,1],[1,0],[0,-1],[-1,0]][scenario]
        position=[(cell[0]*256-384)*65536,0,(cell[1]*256-384)*65536]
        targetcell=[cell[i]+2*delta[i] for i in range(2)]
        target=[targetcell[0]*256-384,0,targetcell[1]*256-384]
        velocity=[trunc(target[0]*65536-position[0],6),-0x380000,trunc(target[2]*65536-position[2],6)]
        translation=[p>>16 for p in position];count=6
        matrix=[4096,0,0,0,4096,0,0,0,4096]
        def row(tick):return [scenario,tick]+position+velocity+cell+[count,2049,1,scenario,-1]+target+[1,1,1]+matrix+translation
        cell=targetcell[:];yield row(-1)
        for tick in range(5):
            count-=1;velocity[1]+=0x100000;position=[p+v for p,v in zip(position,velocity)]
            translation=[p>>16 for p in position];cell=[(translation[0]+512)>>8,(translation[2]+512)>>8]
            normal=[0,-4096,0];facing=[[0,0,4096],[4096,0,0],[0,0,-4096],[-4096,0,0]][scenario]
            x=normalize(cross(facing,normal));z=cross(normal,x);matrix=[v for i in range(3) for v in [x[i],-normal[i],z[i]]]
            yield row(tick)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--c-oracle',required=True);parser.add_argument('--output',default='tests/golden/synthetic/terrain_bounds.csv');parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--bounds'],capture_output=True,text=True,check=True)
    lines=process.stdout.splitlines();start=next(i for i,s in enumerate(lines) if s.startswith('scenario,tick,'))
    stream=io.StringIO(newline='');writer=csv.writer(stream,lineterminator='\n');writer.writerow(FIELDS);writer.writerows(expected());text=stream.getvalue()
    actual=list(csv.reader(lines[start:]));facts=list(csv.reader(text.splitlines()))
    if actual!=facts:
        for i,(a,b) in enumerate(zip(actual,facts)):
            if a!=b:raise ValueError(f'Frozen C row {i}: {a} != independent Python {b}')
        raise ValueError('Frozen C record count differs')
    target=Path(args.output)
    if args.verify:
        if target.read_text()!=text:raise ValueError('Golden facts differ')
    else:target.write_text(text,encoding='utf-8')
    print(f'Independent Python matched {len(facts)-1} frozen C bounds-prefix records.')
if __name__=='__main__':main()
