#!/usr/bin/env python3
"""Compose independently decoded ORG1 paths, scripts, frog and animation facts."""
import struct

import make_golden_frog_animation as animation
import verify_org1_admission as admission
import org1_neighbor_admission as neighbor
import org1_hilite_admission as hilite
from org1_round_trip import Route
from org1_script_state import Script,short
from org1_route_camera import Camera


def verify(context,geometry,ticks,commands,actual,entity_actual,expected_death_tick=None):
    """Require all phase movement/scans and every ordered script state to agree."""
    if len(actual)!=ticks*6 or len(entity_actual)!=ticks*64:raise ValueError('incomplete ORG1 oracle trace')
    programs={i:s['stream'] for i,s in context['scripts'].items()} if isinstance(context['scripts'],dict) else {i:s['stream'] for i,s in enumerate(context['scripts'])}
    route=Route(context,geometry,ticks);scripts={};actions={};cels={};cache={}
    for r in geometry['neighbors']:
        index=r['entity_index'];mid=r['model_resource_id'];m=neighbor.model_facts(context,mid,cache)['_model']
        if m['incomplete']:mid=cache[mid]['counterpart_resource_id'];m=cache[mid]['_model']
        p=m['statics'][0]['parts'][0];count=p['flipbook_actions'] if not m['incomplete'] else 0
        raw=admission.platform.resource(context['files'],context['entries'],context['mwd'],mid)
        actions[index]=[admission.contacts.read(raw,p['flipbook_ptr']+4+j*4,'<H') for j in range(count)]
        cels[index]=-1
        if not r['script_id']:continue
        regs=[];sid=r['script_id']
        if 'turtle' in r:
            t=r['turtle'];regs=[t['dive_delay'],t['rise_delay'],t['type']]
            sid=context['script_names'].index(t['effective_script'])
        elif r['entity_type']=='STATIC_NOISE':regs=list(struct.unpack_from('<2i',context['data'],r['source_offset']+56))
        scripts[index]=Script(programs,sid,regs,actions[index])
    raw=admission.platform.resource(context['files'],context['entries'],context['mwd'],214)
    data=animation.catalog();data['action_lengths']=[a['frames'] for a in hilite.discrete_actions(hilite.animation.parse_xar(raw),16)]
    frog_anim=animation.State(data);seed=1;sounds=0;hits=set();carried=-1
    general=admission.contacts.read(context['data'],76,'<I')
    camera=Camera(struct.unpack_from('<3h',context['data'],general+24),struct.unpack_from('<3h',context['data'],general+32))
    fly_mode=0;fly_timer=60;fly_checkpoint=-1;fly_position=geometry['neighbors'][55]['initial_position'][:]
    markers={r['entity_type']:r['initial_position'] for r in geometry['neighbors'] if r['entity_type'].startswith('GEN_')}
    top=markers['GEN_TOP_LEFT'];bottom=markers['GEN_BOTTOM_RIGHT'];fade=[top[0],bottom[0],bottom[2],top[2]]
    compared=0;death_tick=None;expected_phases=[];expected_entities=[]
    def compare(row,wanted,where):
        nonlocal compared
        for key,value in wanted.items():
            if row[key]!=str(value):raise ValueError(f'{where}: {key}: C={row[key]}, Python={value}')
            compared+=1
    for tick in range(ticks):
        route.pose_tick(tick)
        route.poses[55][9:]=fly_position
        for visit,index in enumerate(range(63,-1,-1)):
            r=geometry['neighbors'][index];s=scripts.get(index)
            previous_flags=(4098 if actions[index] else 0)|(65536 if s and s.no_fade else 0)|(64 if index in hits else 0)|(4 if index==carried else 0)
            killed_here=False
            if index==55:
                expired=fly_timer==0;fly_timer-=1
                if expired:
                    if fly_mode==0:
                        seed,draw=admission.random_step(seed);fly_checkpoint=draw%5;fly_mode=1;fly_timer=120
                        cp=geometry['neighbors'][[54,49,50,51,52][fly_checkpoint]]['initial_position']
                        fly_position=[short(cp[0]),short(cp[1]-256),short(cp[2]-50)]
                        route.poses[index][9:]=fly_position
                    else:fly_mode=0;fly_timer=60;fly_checkpoint=-1
            if s:
                seed,requested,sprites,drown=s.update(seed,route.poses[index],route.world(),index in hits,index==carried,r['form_id'],fade)
                if drown and route.mode!=2:
                    if expected_death_tick!=tick:raise ValueError('round trip unexpectedly carries a drowning frog')
                    death_tick=tick;route.mode=2;route.flags&=~2048;route.velocity=[0,0,0];route.count=0
                    frog_anim.request(8)
                    s.requests.append('death_pgen')
                    killed_here=True
                sounds+=len(requested);route.poses[index][10]+=s.deviation
            wanted=dict(tick=tick,index=index,root=s.root if s else -1,program=s.program if s else -1,
                        cursor=s.cursor if s else -1,loop_start=s.start if s else -1,loop_end=s.end if s else -1,
                        timer=s.timer if s else 0,deviation=s.deviation if s else 0,delta=s.delta if s else 0,
                        destination=s.destination if s else 0,remaining=s.remaining if s else 0,
                        action=s.action if s else 0 if actions[index] else -1,
                        cel=s.cel if s and actions[index] else cels[index],rng=seed,sounds=sounds,
                        moving_sound=int(bool(s and s.moving_sound)),requests=';'.join(s.requests) if s and s.requests else '-')
            wanted.update(zip(('red','green','blue'),s.colours if s else [0,0,0]))
            wanted.update(zip(('ambient_red','ambient_green','ambient_blue'),s.ambient if s else [160,160,160] if r['entity_type']=='CHECKPOINT' else [0,0,0]))
            wanted.update(previous_flags=previous_flags,live_flags=(previous_flags&~65536)|(65536 if s and s.no_fade else 0))
            if killed_here:wanted['live_flags']&=~4
            wanted.update(zip('xyz',route.poses[index][9:]))
            wanted.update(fly_mode=fly_mode,fly_timer=fly_timer,fly_checkpoint=fly_checkpoint,covered=0 if fly_checkpoint<0 else 1<<fly_checkpoint)
            for cb in range(2):wanted['callback'+str(cb)]=':'.join(map(str,s.callbacks.get(cb,(-1,0,0,0)) if s else (-1,0,0,0)))
            wanted.update(zip(('sound_id','sound_min','sound_max'),s.moving_sound if s and s.moving_sound else (-1,-1,-1)))
            compare(entity_actual[tick*64+visit],wanted,f'tick {tick} entity {index}')
            expected_entities.append(wanted)
        route.scripted_poses=True
        route.hidden={55} if fly_mode==0 else set()
        hits=set();carried=-1
        if route.mode in (0,5):frog_anim.no_input_timer+=1
        if tick in commands:frog_anim.no_input_timer=0;sounds+=1
        previous=route.attached;route.control(commands.get(tick));camera.transfer(previous,route.attached,route.poses);event_cursor=0
        for phase_index,phase in enumerate(('control','move','collision','camera','scripts','pose')):
            previous=route.attached
            if phase=='move':
                route.move()
                if route.flags&4 and route.mode!=2:carried=route.attached
            elif phase=='collision':
                route.collide();hits=route.hits.copy()
                if route.flags&4 and route.mode!=2:carried=route.attached
            camera.transfer(previous,route.attached,route.poses,route.mode==0)
            if phase=='camera' and route.mode!=2:camera.update(route)
            for request in route.animations[event_cursor:]:frog_anim.request(request)
            event_cursor=len(route.animations)
            if phase=='scripts':frog_anim.seed=seed;frog_anim.scripts();seed=frog_anim.seed
            elif phase=='pose':
                frog_anim.pose()
                for index in range(64):
                    s=scripts.get(index)
                    if s:s.advance_animation()
                    elif actions[index]:cels[index]=min(cels[index]+1,actions[index][0]-1) if index==53 else (cels[index]+1)%actions[index][0]
            wanted=route.snapshot(tick,phase)
            wanted.update(camera.snapshot())
            wanted.update(action=frog_anim.action,cel=frog_anim.cel,rng=seed,sounds=sounds,
                          diver_y=scripts[0].deviation,diver_timer=scripts[0].timer,diver_action=scripts[0].action,
                          scan=';'.join(map(str,route.scan())))
            compare(actual[tick*6+phase_index],wanted,f'tick {tick} phase {phase}')
            if not (-512<=route.world()[0]<512 and -128<=route.world()[2]<480):
                raise ValueError(f'candidate escapes bounds at {tick} {phase}')
            expected_phases.append(wanted)
    if death_tick!=expected_death_tick:raise ValueError('expected attached diver death did not occur')
    print(f'Independent Python/C agreement: {compared} values, {ticks*6} phases, {ticks*64} ordered entity updates.')
    return expected_phases,expected_entities
