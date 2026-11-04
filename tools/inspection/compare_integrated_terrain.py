#!/usr/bin/env python3
"""Compare the explicit 42-column independent component scope with a game JSONL trace."""
import argparse
import csv
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.inspection.compare_run_trace import read
from tools.golden.make_golden_integrated_terrain import FIELDS


def fields(state):
    camera, animation = state['camera'], state['animation']
    return (state['position_16'] + state['velocity_16'] + state['cell'] +
        [state[key] for key in ('remaining_ticks','flags','mode','current_input','direction','no_input_timer','death_count')] +
        [camera[key] for key in ('mode','move_timer','twist_counter')] + camera['tracked_world'] + camera['source_world'] +
        [camera['controller_directions'][0],camera['shake_timer'],animation['script_type'],animation['script_timer'],animation['flags'],
         animation['environment_flags'],state['rng_state'],state['animation_condition_counter'],animation['program_id'],animation['word_offset'],
         animation['action'],animation['cel'],animation['total_cels'],animation['update_count'],
         10 if state['game_mode_request'] == -1 else state['game_mode_request']])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--scenario', type=int, choices=range(4), required=True)
    args = parser.parse_args()
    with args.reference.open(newline='',encoding='utf-8-sig') as file:
        rows = list(csv.reader(file))
    if rows.pop(0) != FIELDS or len(rows) != 1464:
        raise ValueError('Reference requires the complete 1464-row independent schema')
    references = []
    counts = [24,24,120,76]
    index = 0
    for scenario,ticks in enumerate(counts):
        for tick in range(ticks):
            for phase in ('control','move','collision','camera','scripts','pose'):
                row = rows[index];index += 1
                if len(row) != len(FIELDS) or row[:3] != [str(scenario),str(tick),phase]:
                    raise ValueError('Reference ordered schema differs at row %s' % (index+1))
                numbers = [int(value) for value in row[3:]]
                if scenario == args.scenario and phase != 'scripts':
                    references.append((tick,'final' if phase=='pose' else phase,numbers))
    candidate = read(args.candidate)
    metadata = candidate.pop(0)
    if metadata['seed'] != 1 or metadata['action_lengths'] != [3+i%3 for i in range(34)]:
        raise ValueError('Candidate seed/action metadata differs from authored component setup')
    if len(candidate) != len(references):
        raise ValueError('Missing/extra candidate phases: expected %s, got %s' % (len(references),len(candidate)))
    for number,((tick,phase,expected),actual) in enumerate(zip(references,candidate),1):
        if (actual['tick'],actual['phase']) != (tick,phase):
            raise ValueError('Phase order differs row %s: expected %s/%s, got %s/%s' % (number,tick,phase,actual['tick'],actual['phase']))
        pressed = 3 if args.scenario==0 and tick==0 else 32 if args.scenario==1 and tick==0 else 1 if args.scenario!=1 and tick==0 else 0
        held = 1 if args.scenario==1 and 1<=tick<=12 else 1 if args.scenario==0 and tick==0 else pressed
        if (actual['pressed'],actual['held']) != (pressed,held):
            raise ValueError('Command differs scenario %s tick %s: expected pressed/held %s/%s' % (args.scenario,tick,pressed,held))
        values = fields(actual['state'])
        if len(values) != len(expected) or any(type(value) is not int for value in values):
            raise ValueError('Candidate represented state requires exact integer fields')
        for key,want,got in zip(FIELDS[3:],expected,values):
            if want != got:
                print('First difference: scenario %s tick %s phase %s field %s, expected %s actual %s' % (args.scenario,tick,phase,key,want,got))
                print('Command pressed=%s held=%s; cell=%s position16=%s; exact integer equality.' % (pressed,held,actual['state']['cell'],actual['state']['position_16']))
                print('Reproduce the authored scenario with seed1 and counts 3+action%%3; selected camera/animation RNG only, omitted effect-factory draws are not compensated.')
                raise SystemExit(1)
    print('Independent component scope matches %s candidate phase rows and 39 integer fields; remaining JSONL state is outside this comparison.' % len(candidate))


if __name__ == '__main__':
    main()
