#!/usr/bin/env python3
"""Independent combined terrain reaction precedence, checked with frozen C."""
import argparse,csv,io,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden.make_golden_terrain_special import FIELDS,trunc

def expected():
    for scenario in range(10):
        velocity=[0,0,0];cell=[1,1];count=0;flags=2049;mode=0;square=5;target=[0,0,0];animations=sounds=0
        if scenario==0:flags=9;mode=269;animations=1
        elif scenario in (2,3,4):
            flags=9;animations=sounds=1
            if scenario in (2,4):velocity=[0,65536,0]
        elif scenario in (5,6):
            cell=[1,2];count=10;mode=258 if scenario==5 else 267;square=9;target=[-128,0,128]
            velocity=[0,0,trunc(256*65536,10)];animations=1
        elif scenario==7:mode=262
        yield [scenario,-1,-128*65536,0,-128*65536]+velocity+cell+[count,flags,mode,0,square]+target+[animations,sounds,0]+[4096,0,0,0,4096,0,0,0,4096,-128,0,-128]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--c-oracle',required=True);parser.add_argument('--output',default='tests/golden/synthetic/terrain_priority.csv');parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--priority'],capture_output=True,text=True,check=True)
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
    print('Independent Python matched 10 frozen C priority records.')
if __name__=='__main__':main()
