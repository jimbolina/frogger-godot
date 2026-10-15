#!/usr/bin/env python3
"""Check the ORG1 turtle/log proposal's excluded-neighbor RNG obligation.

This is a counterexample check, not a complete route/admission generator.
Default exit 3 means the counterexample agrees; --background exits 0 when the
expanded component proof agrees. --admission adds neighbor and animated-hilite
checks and exits 3 while route obligations remain. No mode admits a route. Exit 1 means
verification failed. Inputs are independently decoded with the existing readers.
Only decoded facts, hashes and oracle output are written, outside repositories.
"""
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_golden_exe_tables as exe_tables
import make_golden_form_contacts as contacts
import make_golden_mof as mof
import make_golden_retail_platform as platform
import make_golden_paths as paths
import make_golden_entities as entities


TRAFFIC = {
    'ORG_TRUCK_RED': 'SCRIPT_ORG_TRUCK',
    'ORG_LORRY': 'SCRIPT_ORG_LORRY',
    'ORG_CAR_PURPLE': 'SCRIPT_ORG_CAR_PURPLE',
    'ORG_BULL_DOZER': 'SCRIPT_ORG_BULL_DOZER',
    'ORG_CAR_BLUE': 'SCRIPT_ORG_CAR_BLUE',
}


def commands(script):
    """Return decoded opcode names and arguments, never GDScript output."""
    words = script['stream']
    result = []
    offset = 0
    while offset < len(words):
        opcode = words[offset]
        if type(opcode) is not int or not 0 <= opcode < len(exe_tables.OPCODES):
            raise ValueError(f'invalid decoded opcode at word {offset}: {opcode!r}')
        name, count = exe_tables.OPCODES[opcode]
        if offset + count >= len(words):
            raise ValueError('incomplete decoded script')
        result.append((name, words[offset + 1:offset + count + 1]))
        offset += count + 1
    return result


def retail_counterexamples(root, with_context=False):
    """Find authored traffic whose first update reaches a RANDOM branch."""
    cfg = exe_tables.parse_cfg(str(Path(exe_tables.CFG_ROOT) / 'versions/pc-retail-v3.0e.cfg'))
    exe_bytes = (root / 'FROGGER.EXE').read_bytes()
    exe = exe_tables.Exe(exe_bytes, exe_tables.java_int(cfg.values['ramOffset']))
    levels, _ = exe_tables.read_map_book(exe, exe_tables.java_int(cfg.values['mapBook']),
                                       exe_tables.java_int(cfg.values['themeBook']))
    level = levels[exe_tables.LEVEL_CODES.index('ORG1')]
    if level['high_map'] != 658:
        raise ValueError('ORG1 high-detail resource changed')
    _, entries, wads, files = mof.load_archive(str(root), exe_tables.java_int(cfg.values['mwiOffset']),
                                          exe_tables.java_int(cfg.values['mwiLength']))
    mwd = (root / 'FROGPSX.MWD').read_bytes()
    data = platform.resource(files, entries, mwd, 658)
    theme = contacts.read(data, contacts.read(data, 76, '<I') + 10, '<H')
    names, sections, _ = exe_tables.name_list('forms', cfg.values.get('formList', '1997-09-12-psx-build57'))
    entity_names, _, _ = exe_tables.name_list('entities', cfg.values.get('entityList', '1997-09-12-psx-build57'))
    script_list = cfg.values.get('scriptList', '1997-09-18-psx-build63')
    script_names, _, _ = exe_tables.name_list('scripts', script_list, False)
    script_cfg = exe_tables.parse_cfg(str(Path(exe_tables.CFG_ROOT)/'scripts'/f'{script_list}.cfg'))
    callbacks = next(section.text for section in script_cfg.children if section.name == 'CallbackNames')
    if callbacks[0] != 'SCRIPT_CB_FROG_TRAFFIC_SPLAT':
        raise ValueError('traffic callback name mapping changed')
    scripts = exe_tables.read_scripts(exe, exe_tables.java_int(cfg.values['scripts']), len(script_names))
    problems = []
    themes = exe_tables.read_theme_book(exe, exe_tables.java_int(cfg.values['themeBook']))
    forms = exe_tables.read_forms(exe, themes, sections, problems)
    if problems:
        raise ValueError('; '.join(problems))
    packet = contacts.read(data, 88, '<I')
    count = contacts.read(data, packet + 8, '<I')
    found = []
    inventory = []
    for index in range(count):
        at = contacts.read(data, packet + 12 + index * 4, '<I')
        _grid, uid, form_id, flags = struct.unpack_from('<4H', data, at)
        book = forms[0 if form_id & 0x8000 else theme][form_id & 0x7fff]
        name = names[book['global']]
        inventory.append(dict(entity_index=index,unique_id=uid,source_offset=at,form_name=name,
                              entity_type=entity_names[book['entity_type']],script_name=script_names[book['script']],
                              script_id=book['script'],flags=flags))
        if name not in TRAFFIC:
            continue
        script_id = book['script']
        program = commands(scripts[script_id])
        if script_names[script_id] != TRAFFIC[name] or entity_names[book['entity_type']] != 'MOVING':
            raise ValueError(f'entity {index} traffic behavior mapping changed')
        if flags != 0 or [op for op, _ in program[:3]] != ['REGISTER_CALLBACK', 'SETLOOP', 'SCRIPT_IF']:
            raise ValueError(f'entity {index} no longer has the audited unconditional prefix')
        branch, condition, target, divisor = program[2][1]
        if branch != 0 or condition != 6 or divisor not in (2, 4):
            raise ValueError(f'entity {index} random branch semantics changed')
        if not 0 <= target < min(len(scripts), len(script_names)):
            raise ValueError(f'entity {index} traffic branch target is invalid')
        found.append(dict(entity_index=index, unique_id=uid, source_offset=at,
                          form_name=name, script_id=script_id, script_name=script_names[script_id],
                          target_script_name=script_names[target], divisor=divisor))
    if [item['entity_index'] for item in found] != list(range(24, 48)):
        raise ValueError('ORG1 traffic counterexample inventory changed')
    facts = dict(build='pc-retail-v3.0e', map_resource_id=658, entity_count=count,
                map_sha256=hashlib.sha256(data).hexdigest(),
                executable_sha256=hashlib.sha256(exe_bytes).hexdigest(), traffic=found)
    if with_context:
        return facts, dict(data=data, forms=forms, names=names, theme=theme,
                           scripts=scripts, script_names=script_names, packet=packet,
                           inventory=inventory,callbacks=callbacks,level=level,themes=themes,
                           entity_names=entity_names,
                           entries=entries,wads=wads,files=files,mwd=mwd)
    return facts


def random_step(seed):
    """Frozen MR_SYS.H unsigned32 LCG, independently evaluated in Python."""
    after = (seed * 0x41c64e6d + 0x3039) & 0xffffffff
    return after, (after >> 16) & 0x7fff


def check_oracle(oracle, acos, output, divisors):
    """Check taken/untaken branches and sound suppression against linked C."""
    cases = []
    for divisor in sorted(divisors):
        for taken in (False, True):
            seed = next(seed for seed in range(1, 100) if (random_step(seed)[1] % divisor == 1) == taken)
            for muted in (0, 1):
                cases.append((seed, divisor, muted))
    fixture = output / 'script-rng-input.txt'
    fixture.write_text(str(len(cases)) + '\n' + ''.join(' '.join(map(str, row)) + '\n' for row in cases), encoding='ascii')
    run = subprocess.run([str(oracle), str(acos), '--script-rng', str(fixture)],
                         text=True, capture_output=True, timeout=30,
                         creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    (output / 'script-rng.csv').write_text(run.stdout, encoding='utf-8')
    (output / 'script-rng-stderr.txt').write_text(run.stderr, encoding='utf-8')
    if run.returncode:
        raise ValueError(f'linked C instruction check failed: exit {run.returncode}; {run.stderr[:500]}')
    # Frozen archive initialization emits a WAD-selection diagnostic first.
    header = 'case,seed,divisor,sound_disabled,seed_after,branch_taken,continues'
    lines = run.stdout.splitlines()
    if lines.count(header) != 1:
        raise ValueError('oracle CSV header is missing or duplicated')
    rows = list(csv.DictReader(io.StringIO('\n'.join(lines[lines.index(header):]))))
    if len(rows) != len(cases):
        raise ValueError(f'expected {len(cases)} oracle cases, got {len(rows)}')
    for number, (row, (seed, divisor, muted)) in enumerate(zip(rows, cases)):
        after, draw = random_step(seed)
        expected = dict(case=number, seed=seed, divisor=divisor, sound_disabled=muted,
                        seed_after=after, branch_taken=int(draw % divisor == 1), continues=1)
        actual = {key: int(value) for key, value in row.items()}
        if actual != expected:
            raise ValueError(f'C/Python RNG disagreement: {actual} != {expected}')
    return rows


BACKGROUND_HEADER = ('tick,index,root_program,cursor,loop_start,loop_end,timer,'
                     'callback_condition,callback_type,callback_called,rng,fly_mode,'
                     'fly_timer,fly_checkpoint,covered,entity_flags,x,y,z,sounds')


def background_inputs(facts, context):
    """Close the supplied traffic call graph and decode checkpoint/fly positions."""
    if not context.get('callbacks') or context['callbacks'][0] != 'SCRIPT_CB_FROG_TRAFFIC_SPLAT':
        raise ValueError('traffic callback name mapping changed')
    roots = {item['script_id'] for item in facts['traffic']}
    targets = set()
    for sid in roots:
        program = commands(context['scripts'][sid])
        if [name for name, _ in program] != ['REGISTER_CALLBACK', 'SETLOOP', 'SCRIPT_IF',
                                            'SET_TIMER', 'WAIT_UNTIL_TIMER', 'ENDLOOP', 'RESTART']:
            raise ValueError('traffic root instruction closure changed')
        callback, loop, branch, timer, wait, end, restart = [args for _, args in program]
        if callback != [0, 0, 0, 0] or timer != [0, 0] or wait != [0, 10]:
            raise ValueError('traffic callback/timer operands changed')
        divisor = 2 if context['script_names'][sid] == 'SCRIPT_ORG_LORRY' else 4
        if branch[0] != 0 or branch[1] != 6 or branch[3] != divisor:
            raise ValueError('traffic random branch operands changed')
        target = branch[2]
        if type(target) is not int or target < 0:
            raise ValueError('invalid traffic branch target')
        for table in (context['scripts'], context['script_names']):
            if (target not in table if isinstance(table, dict) else target >= len(table)):
                raise ValueError('invalid traffic branch target')
        target_program = commands(context['scripts'][target])
        if [name for name, _ in target_program] != ['PLAY_SOUND_DISTANCE', 'RESTART']:
            raise ValueError('traffic target instruction closure changed')
        args = target_program[0][1]
        if args[0:2] != [0, 20] or args[3] != 2 or args[4] not in (256, 384):
            raise ValueError('traffic sound operands changed')
        if context['script_names'][target] != context['script_names'][sid] + '_SFX':
            raise ValueError('traffic branch target name changed')
        targets.add(target)
    if len(roots) != 5 or len(targets) != 5:
        raise ValueError('traffic script closure must contain five roots and five targets')
    data = context['data']
    points = [None] * 5
    fly_position = None
    for index in range(facts['entity_count']):
        at = contacts.read(data, context['packet'] + 12 + index * 4, '<I')
        form_id = contacts.read(data, at + 4, '<H')
        book = context['forms'][0 if form_id & 0x8000 else context['theme']][form_id & 0x7fff]
        name = context['names'][book['global']]
        if name.startswith('GEN_CHECKPOINT_'):
            slot = int(name[-1]) - 1
            points[slot] = list(struct.unpack_from('<3i', data, at + 24 + 20))
        elif name == 'ORG_FLY':
            if index != 55:
                raise ValueError('bonus fly identity changed')
            fly_position = list(struct.unpack_from('<3i', data, at + 24 + 20))
    if any(p is None for p in points) or fly_position is None:
        raise ValueError('missing checkpoint/fly definitions')
    return {sid: context['scripts'][sid]['stream'] for sid in sorted(roots | targets)}, points, fly_position


def background_expected(facts, programs, points, fly_position, ticks, seed, reverse, collected):
    """Independent unsigned32 RNG, traffic VM and non-contact bonus-fly lifecycle.

    Frog slots are inactive, so distance sound requests and hit callbacks cannot
    fire. This proves background script state, not route/contact/audio parity.
    """
    states = {item['entity_index']: dict(root=item['script_id'], program=item['script_id'],
              cursor=0, start=-1, end=-1, timer=0, condition=0, callback_type=0, called=0)
              for item in facts['traffic']}
    fly = dict(mode=0, timer=60, checkpoint=-1, covered=0, flags=9, position=fly_position[:])
    order = list(states) + [55]
    if reverse:
        order.reverse()
    rows = []
    for tick in range(ticks):
        for index in order:
            if index == 55:
                expired = fly['timer'] == 0
                fly['timer'] -= 1
                if expired:
                    if fly['mode'] == 0:
                        seed, draw = random_step(seed)
                        slot = draw % 5
                        if not ((collected | fly['covered']) & (1 << slot)):
                            fly.update(mode=1, timer=120, checkpoint=slot,
                                       covered=fly['covered'] | (1 << slot), flags=0,
                                       position=[points[slot][0], signed16(points[slot][1]-256),
                                                 signed16(points[slot][2]-50)])
                        else:
                            fly.update(timer=60, checkpoint=-1)
                    else:
                        fly.update(mode=0, timer=60, checkpoint=-1, covered=0, flags=9)
                root = cursor = start = end = timer = condition = callback_type = called = -1
            else:
                state = states[index]
                for instruction in range(4096):
                    words = programs[state['program']]
                    cursor = state['cursor']
                    name, count = exe_tables.OPCODES[words[cursor]]
                    args = words[cursor+1:cursor+count+1]
                    following = cursor + count + 1
                    if name == 'REGISTER_CALLBACK':
                        state.update(condition=args[2], callback_type=args[3], called=2)
                    elif name == 'SETLOOP':
                        end = following
                        while exe_tables.OPCODES[words[end]][0] != 'ENDLOOP':
                            end += exe_tables.OPCODES[words[end]][1] + 1
                        state.update(start=following, end=end+1)
                    elif name == 'SCRIPT_IF':
                        seed, draw = random_step(seed)
                        if draw % args[3] == 1:
                            state.update(program=args[2], cursor=0, start=-1, end=-1)
                            continue
                    elif name == 'SET_TIMER':
                        state['timer'] = args[1] & 0xffff
                    elif name == 'WAIT_UNTIL_TIMER':
                        if state['timer'] < args[1]:
                            break
                    elif name == 'ENDLOOP':
                        state['cursor'] = state['start']
                        break  # Linked frozen port yields at ENDLOOP.
                    elif name == 'PLAY_SOUND_DISTANCE':
                        pass  # No active frogs in this component fixture.
                    elif name == 'RESTART':
                        # NEW_SCRIPT changes the cursor, not si_type.
                        state.update(program=state['root'], cursor=0)
                        continue
                    else:
                        raise ValueError(f'unsupported background instruction {name}')
                    state['cursor'] = following
                else:
                    raise ValueError('background program did not yield within instruction budget')
                state['timer'] = (state['timer']+1) & 0xffff
                if state['program'] != state['root']:
                    raise ValueError('traffic target unexpectedly persisted across update')
                root, cursor, start, end, timer, condition, callback_type, called = (
                    state[k] for k in ('root','cursor','start','end','timer','condition','callback_type','called'))
            rows.append([tick,index,root,cursor,start,end,timer,condition,callback_type,called,
                         seed,fly['mode'],fly['timer'],fly['checkpoint'],fly['covered'],fly['flags'],
                         *fly['position'],0])
    return rows


def signed16(value):
    return (value + 32768) % 65536 - 32768


def check_background(oracle, acos, output, facts, context):
    """Compare whole traffic updates plus fly cycles in two explicit update orders."""
    programs, points, fly_position = background_inputs(facts, context)
    summaries = []
    for reverse, collected in ((0,0), (1,0), (0,31)):
        ticks, seed = 730, 12345
        lines = [f'{ticks} {seed} {reverse}', str(len(programs))]
        for sid, words in programs.items():
            lines.append(f'{sid} {len(words)} ' + ' '.join(map(str,words)))
        lines.append(str(len(facts['traffic'])))
        lines.extend(f"{item['entity_index']} {item['script_id']}" for item in facts['traffic'])
        lines.append(str(collected))
        lines.extend('0 ' + ' '.join(map(str,p)) for p in points)
        lines.append(' '.join(map(str,fly_position)))
        fixture = output / f'background-{reverse}-{collected}.txt'
        fixture.write_text('\n'.join(lines)+'\n',encoding='ascii')
        run = subprocess.run([str(oracle),str(acos),'--org1-background',str(fixture)],
                             text=True,capture_output=True,timeout=30,
                             creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        trace = output / f'background-{reverse}-{collected}.csv'
        trace.write_text(run.stdout,encoding='utf-8')
        if run.returncode:
            raise ValueError(f'background C check failed: exit {run.returncode}; {run.stderr[:500]}')
        lines = run.stdout.splitlines()
        if lines.count(BACKGROUND_HEADER)!=1:
            raise ValueError('missing/duplicate background header')
        actual = [[int(v) for v in line.split(',')] for line in lines[lines.index(BACKGROUND_HEADER)+1:]]
        expected = background_expected(facts,programs,points,fly_position,ticks,seed,reverse,collected)
        if len(actual)!=len(expected):
            raise ValueError(f'background row count mismatch {len(actual)} != {len(expected)}')
        for row,want in zip(actual,expected):
            if row!=want:
                raise ValueError(f'background C/Python mismatch {row} != {want}')
        summaries.append(dict(reverse=reverse,collected=collected,rows=len(actual),final_seed=actual[-1][10],
                              trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest()))
    allocation = check_moving_sound(oracle,acos,output,context)
    geometry = traffic_geometry(context)
    return dict(program_names=[context['script_names'][sid] for sid in programs],
                checkpoints=points,fly_position=fly_position,cases=summaries,
                inventory=context['inventory'],moving_sound=allocation,
                traffic_geometry=geometry,
                scope='Whole traffic script updates and non-contact fly cycles; inactive frogs, no geometry or playback.')


def check_moving_sound(oracle, acos, output, context):
    """Check real allocation, reuse, owner clearing and recreation, without playback."""
    noises = [item for item in context['inventory'] if item['entity_type']=='STATIC_NOISE']
    if [item['entity_index'] for item in noises] != [56,57,58,59,62,63]:
        raise ValueError('static noise inventory changed')
    cases = []
    for item in noises:
        program = commands(context['scripts'][item['script_id']])
        if [op for op,_ in program] != ['PREPARE_REGISTERS','SETLOOP','PLAY_MOVING_SOUND','ENDLOOP','RESTART']:
            raise ValueError('static noise instruction closure changed')
        if program[0][1]!=[32,2] or program[2][1][1:]!=[1,0,1]:
            raise ValueError('static noise register operands changed')
        minimum,maximum = struct.unpack_from('<2i',context['data'],item['source_offset']+24+32)
        sound = program[2][1][0]
        fixture = output/f"moving-sound-{item['entity_index']}.txt"
        fixture.write_text(f'{sound} {minimum} {maximum}\n',encoding='ascii')
        run = subprocess.run([str(oracle),str(acos),'--moving-sound-state',str(fixture)],
                             text=True,capture_output=True,timeout=30,
                             creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        (output/f"moving-sound-{item['entity_index']}.csv").write_text(run.stdout,encoding='utf-8')
        if run.returncode:
            raise ValueError(f'moving sound allocation check failed: {run.returncode}; {run.stderr[:500]}')
        header='case,allocated,count,min_radius,max_radius,owner_matches,rng'
        lines=run.stdout.splitlines()
        if lines.count(header)!=1:
            raise ValueError('missing/duplicate moving sound header')
        rows=[[int(v) for v in line.split(',')] for line in lines[lines.index(header)+1:]]
        expected=[[c,int(c not in (0,3)),int(c not in (0,3)),minimum if c not in (0,3) else -1,
                   maximum if c not in (0,3) else -1,int(c not in (0,3)),12345] for c in range(5)]
        if rows!=expected:
            raise ValueError(f'moving sound allocation mismatch {rows} != {expected}')
        cases.append(dict(entity_index=item['entity_index'],sound_id=sound,minimum=minimum,maximum=maximum))
    return dict(cases=cases,scope='Real allocation/owner state only; no voice or audio update, no RNG compensation.')


def traffic_geometry(context, point_bounds=None):
    """Bound traffic cuboids at every integer path pose, not the frog probe.

    Axis-aligned yaw and source-width closure make local X independent of frog
    Y and world X. This covers the cuboid narrow phase, not merely its sphere.
    Frog primitive checks use an animated hilite, not simply the frog origin.
    Its bound is still required before this becomes a collision exclusion.
    """
    if point_bounds is None:point_bounds=[[-512,511],[-224,479]]
    if len(point_bounds)!=2 or any(len(b)!=2 or b[0]>b[1] or b[0]<-32768 or b[1]>32767 for b in point_bounds):
        raise ValueError('invalid world-short traffic probe bounds')
    data=context['data'];pp=contacts.read(data,96,'<I');models={};sampled={};proof=[]
    for item in context['inventory']:
        if item['form_name'] not in TRAFFIC:
            continue
        at=item['source_offset'];form_id=contacts.read(data,at+4,'<H')
        book=context['forms'][context['theme']][form_id]
        mid=context['wads'][context['level']['high_wad']][book['id']][0]
        if mid not in models:
            raw=platform.resource(context['files'],context['entries'],context['mwd'],mid)
            model=mof.parse_model(raw,item['form_name'],None,[])
            if model['kind']!='static' or len(model['statics'])!=1 or len(model['statics'][0]['parts'])!=1:
                raise ValueError('traffic model topology changed')
            part=model['statics'][0]['parts'][0]
            if part['collprims']!=1:
                raise ValueError('traffic primitive count changed')
            cp=part['collprim_ptr'];kind,flags=struct.unpack_from('<2H',raw,cp)
            ox,oy,oz,_pad,_unused_radius,xlen,ylen,zlen,_pad2,matrix=struct.unpack_from('<hhhhiHHHHi',raw,cp+12)
            if kind!=0 or flags!=2 or matrix!=-1 or not xlen:
                raise ValueError('traffic cuboid frame/type changed')
            models[mid]=(ox,xlen,hashlib.sha256(raw).hexdigest())
        ox,xlen,digest=models[mid]
        path_id,segment,distance,motion,speed,pad=struct.unpack_from('<6H',data,at+24)
        if segment or pad or motion!=8 or item['flags']:
            raise ValueError('traffic path start flags changed')
        if path_id not in sampled:
            ptr=contacts.read(data,pp+8+4*path_id,'<I')
            if contacts.read(data,ptr+4,'<I')!=1:
                raise ValueError('traffic path segment count changed')
            sp=contacts.read(data,ptr+8,'<I');kind,length=struct.unpack_from('<2i',data,sp)
            if kind!=2 or length<=0:
                raise ValueError('traffic path must be the audited straight line')
            line=dict(segment_type=kind,length=length,start=list(struct.unpack_from('<3h',data,sp+8)),
                      end=list(struct.unpack_from('<3h',data,sp+16)))
            if line['start'][1:]!=line['end'][1:]:
                raise ValueError('traffic path left its horizontal lane')
            poses=[]
            for d in range(length+1):
                _,position,tangent=paths.sample(line,d,False)
                matrix=entities.moving_matrix([0]*9+position+tangent,0)
                if matrix[0]!=0 or matrix[3]!=0 or abs(matrix[6])!=4096:
                    raise ValueError('traffic cuboid local X no longer equals signed world Z')
                # World XZ differences stay signed16 even for any point in the candidate.
                dx=max(abs(position[0]-x) for x in point_bounds[0])
                dz=max(abs(position[2]-z) for z in point_bounds[1])
                if max(dx,dz)>=32768 or dx*dx+dz*dz+32768**2>=2**31:
                    raise ValueError('traffic source-width exclusion no longer holds')
                poses.append((position[2],matrix[6]//4096))
            sampled[path_id]=poses
        lower=min(z+sign*ox-(xlen-1) for z,sign in sampled[path_id])
        upper=max(z+sign*ox+(xlen-1) for z,sign in sampled[path_id])
        if upper>=-224:
            raise ValueError(f"traffic cuboid {item['entity_index']} intrudes into candidate: max Z {upper}")
        proof.append(dict(entity_index=item['entity_index'],model_resource_id=mid,model_sha256=digest,
                          path_id=path_id,integer_poses=len(sampled[path_id]),primitive_point_z=[lower,upper]))
    return dict(candidate_x=[-512,512],candidate_z=[-224,480],route_admitted=False,entities=proof,
                scope='Cuboid world-point bounds only. Animated frog-hilite reach is not bounded here; no traffic collision exclusion is certified.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', required=True, type=Path)
    parser.add_argument('--oracle', required=True, type=Path)
    parser.add_argument('--acos-table', required=True, type=Path)
    parser.add_argument('--output-directory', required=True, type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--background', action='store_true', help='verify the expanded traffic/fly dependency closure; does not admit a route')
    mode.add_argument('--admission', action='store_true', help='also inspect all neighbors and animated frog reach; exit 3 means route admission remains blocked')
    args = parser.parse_args()
    output = args.output_directory.resolve()
    project = Path(__file__).resolve().parent.parent
    for protected in (project, project.parent / 'froggy'):
        if output.is_relative_to(protected.resolve()):
            raise ValueError('audit output must be outside both repositories')
    evidence, context = retail_counterexamples(args.data_dir, with_context=True)
    output.mkdir(parents=True, exist_ok=True)
    rows = check_oracle(args.oracle.resolve(), args.acos_table.resolve(), output,
                        {item['divisor'] for item in evidence['traffic']})
    if args.background or args.admission:
        closure = check_background(args.oracle.resolve(),args.acos_table.resolve(),output,evidence,context)
        closure.update(build=evidence['build'],map_sha256=evidence['map_sha256'],
                       executable_sha256=evidence['executable_sha256'],
                       oracle_sha256=hashlib.sha256(args.oracle.read_bytes()).hexdigest(),route_admitted=False)
        (output/'org1-background-proof.json').write_text(json.dumps(closure,indent=2)+'\n',encoding='utf-8')
        print(f"Expanded traffic/fly C/Python dependency checks agree: {sum(c['rows'] for c in closure['cases'])} ordered rows.")
        if args.admission:
            from org1_hilite_admission import traffic_hilite_admission
            from org1_neighbor_admission import neighbor_admission
            closure['traffic_hilites'] = traffic_hilite_admission(context, closure['traffic_geometry'])
            closure['neighbors'] = neighbor_admission(evidence, context)
            closure['schema'] = 'org1-admission-v1'
            closure['status'] = 'blocked'
            closure['scope'] = ('Background C/Python components plus independent conditional neighbor '
                                'and frog-probe diagnostics; no integrated route or runtime admission.')
            closure['verifier_sources'] = {name: hashlib.sha256((Path(__file__).parent / name).read_bytes()).hexdigest()
                                           for name in ('verify_org1_admission.py', 'org1_neighbor_admission.py',
                                                        'org1_hilite_admission.py')}
            closure['remaining_integration_gates'] = [
                'Reachable frog action/mode/world-transform bounds and full traffic collision exclusion.',
                'Active-frog script callbacks and sound/effect request semantics.',
                'Turtle behavior, shared FORM writes and complete ordered entity updates.',
                'Connected bank/turtle/log return trace with retail animation and phase guards.',
            ]
            destination = output / 'org1-admission-proof.json'
            destination.write_text(json.dumps(closure, indent=2) + '\n', encoding='utf-8')
            print('BLOCKED: neighbor and animated-hilite evidence does not admit an integrated route.')
            print(f'Evidence: {destination}')
            return 3
        print('No ORG1 route or boundary is admitted by this component check.')
        return 0
    evidence.update(status='blocked', reason='excluded traffic consumes shared MRrand state',
                    oracle_sha256=hashlib.sha256(args.oracle.read_bytes()).hexdigest(),
                    instruction_checks=rows,
                    scope='Counterexample only: no route, geometry exclusion or whole-engine trace is certified.')
    (output / 'org1-admission-counterexample.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    for item in evidence['traffic']:
        print(f"EMTP[{item['entity_index']}] UID {item['unique_id']} offset {item['source_offset']}: "
              f"{item['form_name']} / {item['script_name']} -> RANDOM modulo {item['divisor']}")
    print(f'Independent retail inventory and {len(rows)} linked-C/Python instruction checks agree.')
    print('BLOCKED: the 24 excluded traffic entities consume shared RNG before frog control; geometry and sound suppression do not remove that effect.')
    print(f'Evidence: {output}')
    return 3


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, IndexError, struct.error, subprocess.SubprocessError) as error:
        print(f'ORG1 admission verification failed: {error}', file=sys.stderr)
        raise SystemExit(1)
