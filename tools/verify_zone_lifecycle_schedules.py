"""Verify complete synthetic and JUN1 combined traces at headless/30/60/144 Hz."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from verify_lifecycle_schedules import check_png, CAPTURES


def compare_facts(expected, camera, zone, region, angle, world, lifecycle):
    observed=dict(camera,frog_zone=zone,frog_region=region,entity_angle=angle,
                  mod_rotation=camera['mod_matrix12'][:9])
    for key,value in expected['camera'].items():
        if observed[key]!=value:raise ValueError(f'Camera {key} differs: {observed[key]} != {value}')
    for key,actual in [('world',world),('selected_groups',lifecycle['selected_groups']),
                       ('live_order',lifecycle['live_order']),('events',lifecycle['lifecycle_events'])]:
        if actual!=expected[key]:raise ValueError(f'Independent {key} differs')
    if len(lifecycle['entities'])!=len(expected['entities']):raise ValueError('Entity inventory differs')
    for entity,wanted in zip(lifecycle['entities'],expected['entities']):
        for key in ('entity_index','live','destroy_pending','generation'):
            if entity[key]!=wanted[key]:raise ValueError(f'Entity {wanted["entity_index"]} {key} differs')
        if entity['matrix12'][9:]!=wanted['position']:raise ValueError('Entity position differs')
        if wanted['path'] is not None:
            p=entity['path']
            fields=[p[k] for k in ('tick_index','segment_index','segment_type','segment_distance',
                                   'segment_length','segment_param','total_distance','speed','flags')]
            fields+=p['position']+p['tangent']
            if fields!=wanted['path']:raise ValueError('Path cursor differs')


def verify(rows, golden, retail):
    count=320 if retail else 336
    schema='camera-zone-lifecycle-v1' if retail else 'entity-lifecycle-v1'
    if rows[0].get('schema')!=schema or rows[0].get('tick_limit')!=count:raise ValueError('Wrong metadata')
    if len(rows)!=1+count*(1 if retail else 5):raise ValueError('Incomplete trace')
    if not retail:
        for i,row in enumerate(rows[1:]):
            if (row.get('tick'),row.get('phase'))!=(i//5,('control','move','collision','camera','final')[i%5]):
                raise ValueError('Missing or reordered phase')
            if row.get('error'):raise ValueError(row['error'])
    finals=rows[1:] if retail else [r for r in rows[1:] if r['phase']=='final']
    angle=0
    for tick,row in enumerate(finals):
        if row['tick']!=tick:raise ValueError('Missing or reordered tick')
        if retail:
            if tick%160==0:angle=0
            angle=(angle+row['camera']['entity_angle_delta'])&3
            expected=golden['cases'][tick//160]['expected'][tick%160]
            compare_facts(expected,row['camera'],row['frog_zone'],row['frog_region'],angle,row['world'],row['entity_lifecycle'])
            if row['polygon_total']!=expected['polygon_total']:raise ValueError('Polygon budget differs')
        else:
            s=row['state'];expected=golden['cases'][0]['expected'][tick]
            compare_facts(expected,s['camera'],s['camera_zone_index'],s['camera_zone_region_index'],s['entity_angle'],s['world_position'],row['entity_lifecycle'])


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--godot',required=True)
    ap.add_argument('--output-directory',type=Path,required=True)
    args=ap.parse_args();repo=Path(__file__).resolve().parents[1];output=args.output_directory.resolve()
    for protected in (repo,(repo.parent/'froggy').resolve()):
        if output==protected or protected in output.parents:ap.error('Evidence must be outside repositories')
    output.mkdir(parents=True,exist_ok=True)
    def hashes():
        return {str(p.relative_to(repo)):hashlib.sha256(p.read_bytes()).hexdigest()
                for folder in ('src','tools','tests/golden') for p in (repo/folder).rglob('*')
                if p.is_file() and p.suffix in ('.gd','.py','.json','.tsv','.c','.h')}
    before=hashes()
    for retail in (False,True):
        label='jun1' if retail else 'synthetic'
        golden=json.loads((repo/f'tests/golden/{"pc-retail-v3.0e" if retail else "synthetic"}/zone_lifecycle.json').read_text())
        baseline=None
        for rate,viewer in ((30,False),(30,True),(60,True),(144,True)):
            name=f'{label}-'+(f'render{rate}' if viewer else 'headless')
            command=[sys.executable,'-B',str(repo/'tools/run_terrain.py'),'--godot',args.godot,
                     '--entity-lifecycle','visibility','--render-rate',str(rate),'--output-directory',str(output/name)]
            if retail:command+=['--camera-inspection','jun1-camera-zones']
            else:command+=['--scenario-file',str(repo/'tests/golden/fixtures/lifecycle_zones.json')]
            if viewer:command+=['--viewer']
            run=subprocess.run(command,cwd=repo,capture_output=True,text=True,timeout=1200)
            (output/(name+'.log')).write_text(run.stdout+run.stderr)
            if run.returncode:raise ValueError(f'{name} failed; see {output/(name+".log")}')
            prefix='Camera inspection succeeded: ' if retail else 'Terrain run succeeded: '
            trace=Path(next(line.removeprefix(prefix) for line in run.stdout.splitlines() if line.startswith(prefix))).with_suffix('.jsonl')
            rows=[json.loads(line) for line in trace.read_text().splitlines()]
            verify(rows,golden,retail)
            if baseline is None:baseline=rows
            elif rows!=baseline:raise ValueError(f'{name}: complete snapshots differ')
            if viewer:
                if retail:
                    captures=list(trace.parent.glob('zone-*.png'))
                    if len(captures)<16:raise ValueError('Missing zone/lifecycle captures')
                    for p in captures:check_png(p)
                else:
                    for stage in CAPTURES:check_png(trace.parent/f'entity-{stage}.png')
            print(f'{name}: complete trace matches independent facts; {trace}',flush=True)
    if before!=hashes():raise ValueError('Sources changed during schedule verification')
    (output/'comparison.json').write_text(json.dumps(dict(pass_all=True,rates=[30,60,144],source_hashes=before),indent=2)+'\n')
    print('Both combined inspections agree at headless/30/60/144 Hz.')


if __name__=='__main__':main()
