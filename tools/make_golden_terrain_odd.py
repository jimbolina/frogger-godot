#!/usr/bin/env python3
"""Independent odd-grid ordinary-hop facts checked against frozen C."""
import argparse,csv,io,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True
from make_golden_terrain_special import FIELDS,trunc
from make_golden_grid import normalize,cross

def expected():
    position=[0,0,0];velocity=[0,-0x380000,trunc(256*65536,6)]
    cell=[1,2];count=6;flags=2113;mode=1;animations=1
    matrix=[4096,0,0,0,4096,0,0,0,4096];translation=[0,0,0]
    def row(tick):return [0,tick]+position+velocity+cell+[count,flags,mode,0,7]+[0,0,256]+[animations,1,1]+matrix+translation
    yield row(-1)
    for tick in range(8):
        if mode==1:
            count-=1
            if count==0:
                position=[0,0,256*65536];velocity=[0,0,0];flags=2049;mode=0;animations+=1
            else:
                velocity[1]+=0x100000;position=[p+v for p,v in zip(position,velocity)]
            translation=[p>>16 for p in position]
            cell=[(translation[0]+384)>>8,(translation[2]+384)>>8]
        yield row(tick)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--c-oracle',required=True);parser.add_argument('--output',default='tests/golden/synthetic/terrain_odd.csv');parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--odd'],capture_output=True,text=True,check=True)
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
    print(f'Independent Python matched {len(facts)-1} frozen C odd-grid hop records.')
if __name__=='__main__':main()
