#!/usr/bin/env python3
"""Independent decoded traffic cuboids and stored animated frog collision poses."""
import struct

import verify_org1_corridor as corridor
import org1_hilite_reach as hilite
import org1_neighbors as neighbor
from org1_round_trip import apply,transpose

CANDIDATE=(-512,512,-1792,480)


def decode(context):
    """Read all five traffic models and every source frog collision hilite."""
    cache={};vehicles={}
    for identity in context['inventory']:
        if identity['form_name'] not in corridor.TRAFFIC:continue
        at=identity['source_offset'];fid=corridor.contacts.read(context['data'],at+4,'<H')
        book=context['forms'][context['theme']][fid]
        mid=context['wads'][context['level']['high_wad']][book['id']][0]
        raw=corridor.platform.resource(context['files'],context['entries'],context['mwd'],mid)
        part=neighbor.model_facts(context,mid,cache)['_model']['statics'][0]['parts'][0]
        cp=part['collprim_ptr'];kind,flags=struct.unpack_from('<2H',raw,cp)
        ox,oy,oz,pad,radius,x,y,z,user,matrix=struct.unpack_from('<hhhhiHHHHi',raw,cp+12)
        if (part['collprims'],kind,flags,matrix,user,book['death'],book['collision'])!=(1,0,2,-1,1,0,0):
            raise ValueError('traffic primitive/death contract changed')
        vehicles[identity['entity_index']]=dict(offset=[ox,oy,oz],lengths=[x,y,z],reaction=user,death=book['death'])
    raw=corridor.platform.resource(context['files'],context['entries'],context['mwd'],214)
    mesh=corridor.mof.parse_model(raw,'frog',None,[])
    xar=hilite.animation.parse_xar(raw);actions=hilite.discrete_actions(xar,16)
    probes=list(hilite.all_hilites(mesh['statics'][0]))
    matrices=[[hilite.animation.sampled_matrix(xar,a,frame,part) for frame in range(a['frames']) for part in range(16)] for a in actions]
    return vehicles,probes,actions,matrices


def transport_footer(context,geometry):
    """Numeric facts consumed by real frozen MRCollisionCheck and its reaction."""
    vehicles,probes,actions,matrices=decode(context);values=[len(vehicles)]
    for index,cp in vehicles.items():values += [index,*cp['offset'],*cp['lengths'],cp['reaction'],cp['death']]
    values.append(len(probes))
    for part,h,pc,v in probes:values += [part,*v]
    raw=corridor.platform.resource(context['files'],context['entries'],context['mwd'],214)
    xar=hilite.animation.parse_xar(raw)
    values += [int(xar['zero']),len(xar['raw'])]
    for row in xar['raw']:values += row
    values.append(len(actions))
    for action,items in zip(actions,matrices):
        values += [action['frames'],action['unique']]
        values += action['cels']
        values += action['indices']
    return values


def stored_points(root,world,action,cel,decoded):
    """Source stored-LW composition and both signed16 collision-point stores."""
    vehicles,probes,actions,matrices=decoded
    if cel<0:raise ValueError('collision pose has no active cel')
    result=[]
    for part,h,pc,vertex in probes:
        local=matrices[action][cel*16+part]
        rotation=hilite.multiply(root,local[:9]);translation=apply(root,local[9:])
        point=apply(rotation,vertex)
        result.append((part,h,[hilite.short(hilite.short(point[k])+translation[k]+world[k]) for k in range(3)]))
    return result


def primitive_hit(matrix,cp,points):
    """Frozen strict cuboid test, with signed16 displacement before inverse."""
    offset=apply(matrix,cp['offset']);inverse=transpose(matrix)
    for part,h,point in points:
        delta=[hilite.short(point[k]-matrix[9+k]-offset[k]) for k in range(3)]
        local=apply(inverse,delta)
        if all(abs(local[k])<cp['lengths'][k] for k in range(3)):return part,h,local
    return None


def preset_manifest(context,geometry,oracle,acos,output):
    """Prove the broader corridor while retaining the original river preset."""
    import make_golden_org1_route as generator
    narrow=neighbor.neighbor_facts(dict(entity_count=64,build='pc-retail-v3.0e',
        map_sha256=geometry['map_sha256'],executable_sha256=geometry['executable_sha256']),context)
    probes=hilite.check_reachable_probes(context,narrow,oracle,acos,output)
    supports=[tuple(r) for r in probes['support_roots']]
    roots=hilite.root_closure(geometry['terrain'],supports)
    if roots!=[tuple(r) for r in probes['roots']]:raise ValueError('road terrain enlarges the independently checked root closure')
    proof=generator.preset_manifest(context,narrow,probes)
    vehicles,_,_,_=decode(context)
    included=sorted(geometry['included_FORM_indices']+list(vehicles))
    if geometry['zone_count'] or geometry['unresolved_contact_indices']!=list(vehicles):raise ValueError('road neighbor closure changed')
    for cell in geometry['terrain']:
        if len(cell['layers'])!=1 or cell['layers'][0]['flags'] not in (3,65539,9):raise ValueError('road terrain reaction closure changed')
        if any(not -256<=v[1]<=0 for v in cell['layers'][0]['vertices']):raise ValueError('road terrain height closure changed')
    for r in geometry['neighbors']:
        if r['entity_index'] in vehicles:
            if geometry['form_grids'][r['form_grid_id']]['form_data_count']:raise ValueError('traffic gained a FORM fallback')
        elif r['entity_index'] not in included:
            if not r['contact_status'].startswith('excluded_'):raise ValueError('road has an unproved neighbor')
            if r['entity_type'] in ('CHECKPOINT','ORG_FLY','ORG_BABY_FROG') and r['minimum_candidate_xz_distance_squared']<=640**2:
                raise ValueError('road introduces a tongueable neighbor')
    offsets=probes['probe_offset_bounds']
    world=[[CANDIDATE[0]+offsets[0][0],CANDIDATE[1]-1+offsets[0][1]],
           [CANDIDATE[2]+offsets[2][0],CANDIDATE[3]-1+offsets[2][1]]]
    if any(b[0]<-32768 or b[1]>32767 for b in world):raise ValueError('road probe XZ can wrap')
    for r in geometry['neighbors'][24:48]:
        x,y,z=r['geometry']['position_bounds']
        dx=max(abs(a-b) for a in x for b in world[0]);dz=max(abs(a-b) for a in z for b in world[1])
        if max(dx,dz)>=32768 or dx*dx+dz*dz+32768**2>=2**31:raise ValueError('traffic source-width closure changed')
    proof.update(schema='org1-road-river-preset-v1',bounds_x=list(CANDIDATE[:2]),bounds_z=list(CANDIDATE[2:]),
        included_contact_indices=included,spawn_cell=[10,1],spawn_world=[128,-256,-1664],spawn_direction=0,default_ticks=180,
        contact_exclusions=[dict(index=r['entity_index'],unique_id=r['unique_id'],offset=r['source_offset'],reason=r['contact_status']) for r in geometry['neighbors'] if r['entity_index'] not in included],
        traffic_primitives=[dict(index=i,**cp) for i,cp in vehicles.items()],
        frog_probe_offset_bounds=offsets,frog_probe_world_xz_bounds=world,
        collision_pose_cache='Explicit reset action0/cel0 priming; prior stored LW; frozen STATIC action/actual-cel cache at final pose.',
        road_river=dict(commands=[[t,1] for t in (0,12,24,36,102,114,126,138)],observation_ticks=180,bank_tick=119,turtle_contact_tick=129,small_log_contact_tick=144),
        vehicle_death=dict(commands=[[t,1] for t in (0,12,24,36,48)],observation_ticks=60,collision_tick=50,entity_index=31,callback_tick=51,sound_id=13),
        conditions=['Single unpowered player uses pinned GEN_FROG.XAR; source camera zones are absent.',
            'Every current and retained collision-sample root origin stays in the half-open rectangle; rejected ticks roll back.',
            'Road SAFE, bank SAFE and river WATER only; landing height difference stays below the source stun threshold.',
            'Ten primitive-free SAFE FORMs and all 24 decoded static deadly vehicle cuboids participate in source ordered collision.',
            'Every excluded neighbor has complete path FORM or source-width origin-sphere exclusion; no tongueable neighbor within640 units.',
            'All64 authored logical updates persist in descending all-attached order, including next-update HIT callbacks.',
            'Traffic has no FORM data fallback; all five named types use DEADLY primitive reaction1 and EXE death0 SQUISHED.',
            'Cached LW refresh uses source actual-cel keys after final pose; dying and MUST_DIE frogs skip later primitive scans.'])
    for key in ('round_trip','attached_diver','traffic_probe_z_minimum','traffic_point_z_maximum'):proof.pop(key,None)
    return proof
