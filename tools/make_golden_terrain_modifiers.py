#!/usr/bin/env python3
"""Independent ushort modifier expiry facts checked against UpdateFrogPowerUps."""
import argparse
import csv
import io
from pathlib import Path
import subprocess

def expected():
    for scenario in range(4):
        flags=7;timers=[scenario,scenario+1,scenario+2]
        for tick in range(7):
            for index,mask in enumerate([4,1,2]):
                if flags&mask:
                    if timers[index]:timers[index]-=1
                    else:flags&=~mask
            yield [scenario,tick,flags]+timers

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--c-oracle',required=True)
    parser.add_argument('--output',default='tests/golden/synthetic/terrain_modifiers.csv')
    parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--modifiers'],capture_output=True,text=True,check=True)
    lines=process.stdout.splitlines();start=next(i for i,s in enumerate(lines) if s.startswith('scenario,tick,'))
    stream=io.StringIO(newline='');writer=csv.writer(stream,lineterminator='\n')
    writer.writerow(['scenario','tick','flags','auto_timer','tongue_timer','quick_timer']);writer.writerows(expected())
    text=stream.getvalue()
    if list(csv.reader(lines[start:]))!=list(csv.reader(text.splitlines())):raise ValueError('Frozen C modifier mismatch')
    target=Path(args.output)
    if args.verify:
        if target.read_text()!=text:raise ValueError('Golden facts differ')
    else:target.write_text(text,encoding='utf-8')
    print('Independent Python matched 28 frozen C modifier records.')

if __name__=='__main__':main()
