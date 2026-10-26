#!/usr/bin/env python3
"""Independent normal-hop/SAFE FORM calculation for the bounded ORG1 route.

This reader never consumes runtime or C output to construct expectations.
It intentionally rejects other movement/reaction workloads.
"""
import math
import struct

import make_golden_paths as paths
import make_golden_entities as entities
import make_golden_form_contacts as contacts
import org1_neighbor_admission as neighbor


def apply(matrix, point):
    """Source fixed12 matrix application (integer vector, no translation)."""
    return [paths.signed(sum(matrix[3*r+k]*point[k] for k in range(3)) >> 12)
            for r in range(3)]


def transpose(matrix):
    return [matrix[3*c+r] for r in range(3) for c in range(3)]


def quadrant(v):
    return (0 if v[2]>0 else 2) if abs(v[2])>abs(v[0]) else (1 if v[0]>0 else 3)


class Route:
    """Source integer movement/contact owner, restricted to a proven SAFE route."""
    def __init__(self,context,geometry,ticks):
        self.context=context;self.geometry=geometry
        self.records=geometry['neighbors'];self.forms=contacts.parse_forms(context['data'])
        definitions=neighbor.decode_paths(context['data'])
        self.traces={}
        for record in self.records:
            if 'path' in record:
                p=record['path']
                self.traces[record['entity_index']]=paths.python_trace(dict(segments=definitions[p['index']],
                    start=dict(segment_index=p['initial_segment'],distance=p['initial_distance'],speed=p['speed'],flags=9),tick_limit=ticks))
        data=context['data'];grap=contacts.read(data,80,'<I');group=contacts.read(data,grap+8,'<I')
        gx,gy,gz,pad,nx,nz,sx,sz=struct.unpack_from('<4h4H',data,group+4)
        self.group_base=(gx,gz);self.group_dims=(nx,nz);self.group_size=(sx,sz)
        self.pos=[128<<16,-256<<16,-128<<16];self.velocity=[0,0,0]
        self.offset=[0,0,0];self.cell=[0,0];self.target=[0,0,0]
        self.mode=0;self.flags=2049;self.attached=self.forbidden=-1;self.count=0
        self.old_y=self.y=-256;self.direction=0;self.heading=0
        self.poses=[];self.animations=[]
        self.hits=set()
        self.hidden=set()
        self.frog_root=(4096,0,0,0,4096,0,0,0,4096)
        self.relative_root=self.frog_root

    def update_root(self):
        """Frozen unscaled UpdateFrogMatrix for this bounded terrain/support route."""
        from org1_hilite_admission import ROOTS,axes,multiply
        from make_golden_grid import cross,normal
        if self.flags&4:
            self.frog_root=multiply(self.poses[self.attached],self.relative_root)
        elif not self.flags&128:
            up=paths.normalised([-self.frog_root[k] for k in (1,4,7)])
            facing=list(ROOTS[self.direction][1][2::3])
            if self.flags&(64|16)==16:
                facing=apply(self.poses[self.attached],facing)
            elif not self.flags&32:
                point=self.target if self.flags&64 else self.world()
                cell=next((c for c in self.geometry['terrain'] if c['world_x'][0]<=point[0]<c['world_x'][1] and c['world_z'][0]<=point[2]<c['world_z'][1]),None)
                if cell:up=normal(cell['layers'][0]['vertices'])
            x=paths.normalised(cross(facing,up));z=cross(up,x)
            self.frog_root=axes(x,[-v for v in up],z)

    def world(self):return [v>>16 for v in self.pos]

    def pose_tick(self,tick):
        """Advance every independent authored path before frog control."""
        self.poses=[];self.scripted_poses=False
        for r in self.records:
            index=r['entity_index']
            if index in self.traces:
                m=entities.moving_matrix(self.traces[index][tick+1],r['flags'])
            else:m=[4096,0,0,0,4096,0,0,0,4096,*r['initial_position']]
            self.poses.append(m)

    def group(self,world):
        return tuple(max(0,min(self.group_dims[i]-1,paths.divided(world[k]-self.group_base[i],self.group_size[i])))
                     for i,k in enumerate((0,2)))

    def scan(self):
        """Moving relinks head-insert after source-ordered static initial links."""
        world=self.world();gx,gz=[paths.divided(world[k]-self.group_base[i],self.group_size[i]) for i,k in enumerate((0,2))]
        result=[]
        for z in range(max(0,gz-1),min(self.group_dims[1]-1,gz+1)+1):
            for x in range(max(0,gx-1),min(self.group_dims[0]-1,gx+1)+1):
                for moving in (True,False):
                    for r in reversed(self.records):
                        if moving and r['entity_index'] in self.hidden:continue
                        if hasattr(self,'live') and r['entity_index'] not in self.live:continue
                        is_moving=r['entity_type'] in ('MOVING','SUB_TURTLE','ORG_BABY_FROG','ORG_FLY')
                        if is_moving==moving and self.group(self.poses[r['entity_index']][9:])==(x,z):result.append(r['entity_index'])
        return result

    def control(self,direction):
        self.animations=[]
        if direction is None:return
        if self.mode not in (0,5):raise ValueError('route command is not a settled/centring normal hop')
        if direction not in (0,2):raise ValueError('route only audits north/south hops')
        world=self.world();self.mode=1;self.count=6;self.direction=self.heading=direction
        self.animations.append(16)
        if self.attached<0:
            self.flags|=64;self.target=[world[0],-64,world[2]+256]
            self.y=-64
        else:
            record=self.records[self.attached];m=self.poses[self.attached];form=self.forms[record['form_grid_id']]
            self.flags=(self.flags&~4)|16;self.forbidden=self.attached
            local_dir=quadrant(apply(transpose(m),[0,0,4096 if direction==0 else -4096]))
            self.direction=local_dir
            delta=((0,1),(1,0),(0,-1),(-1,0))[local_dir]
            self.cell=[self.cell[i]+delta[i] for i in range(2)]
            if 0<=self.cell[0]<form[4] and 0<=self.cell[1]<form[5]:
                raise ValueError('round-trip schedule unexpectedly hops within the same FORM')
            if direction==2 and world[2]<256:
                self.flags|=64;self.direction=2
                self.target=[(world[0]//256)*256+128,-256,-128];self.y=-256
            else:
                self.flags&=~(2|64)
                self.target=[form[6]+self.cell[0]*256+128,form[8][0][2],form[7]+self.cell[1]*256+128]
                self.y=world[1]
        vy=paths.divided((self.y-world[1])<<16,7)-(1048576*7>>1)
        origin=self.offset if self.attached>=0 and not self.flags&64 else self.pos
        self.velocity=[paths.divided((self.target[0]<<16)-origin[0],6),vy,
                       paths.divided((self.target[2]<<16)-origin[2],6)]

    def carry(self):
        matrix=self.poses[self.attached]
        local=apply(matrix,[v>>16 for v in self.offset])
        self.pos=[(local[k]+matrix[9+k])<<16 for k in range(3)]

    def airborne(self):
        self.velocity[1]+=1048576
        if self.flags&8320==8320 and self.world()[1]>=self.old_y:
            self.animations.append(6);self.flags&=~8192
        if self.attached>=0 and not self.flags&64:
            self.offset[0]+=self.velocity[0];self.offset[2]+=self.velocity[2]
            matrix=self.poses[self.attached];local=apply(matrix,self.offset)
            self.pos=[(matrix[9]<<16)+local[0],self.pos[1]+self.velocity[1],(matrix[11]<<16)+local[2]]
        else:self.pos=[v+d for v,d in zip(self.pos,self.velocity)]

    def move(self):
        if self.mode==5:
            self.count-=1
            if self.count==0:
                self.velocity=[0,0,0];self.mode=0;self.offset=[v<<16 for v in self.target];self.animations.append(14)
            else:self.offset=[v+d for v,d in zip(self.offset,self.velocity)]
            self.carry()
        elif self.mode in (0,2) and self.attached>=0:
            self.carry();self.y=self.world()[1]
        elif self.mode==1:
            self.count-=1
            if self.count==0:
                if self.flags&64:
                    if self.target[2]!=-128:raise ValueError('route lands on unsupported terrain')
                    self.pos=[v<<16 for v in self.target];self.velocity=[0,0,0]
                    self.attached=self.forbidden=-1;self.mode=0;self.flags&=~(2|4|16|32|64|128|256|16384|65536)
                    self.y=self.old_y=self.world()[1];self.direction=2;self.animations.append(14)
                else:
                    if self.attached>=0:self.airborne()
                    self.attached=-1;self.flags&=~(2|16|32|64|128|256|16384|65536)
                    self.flags|=8320;self.count=0x7ffffff
                    self.velocity[0]=self.velocity[2]=0;self.old_y=self.y
            else:self.airborne()

    def collide(self):
        self.hits=set()
        if self.mode==2:return
        for index in self.scan():
            if hasattr(self,'live') and index not in self.live:continue
            if index not in self.geometry['included_FORM_indices'] or index in (self.attached,self.forbidden):continue
            r=self.records[index];form=self.forms[r['form_grid_id']];matrix=self.poses[index]
            delta=[contacts.s16(self.world()[k]-matrix[9+k]) for k in range(3)]
            if paths.signed(sum(v*v for v in delta))>=r['radius_squared']:continue
            local=apply(transpose(matrix),delta);nx,nz,ox,oz=form[4:8];height=form[8][0][2]
            if not (ox<local[0]<ox+nx*256 and oz<local[2]<oz+nz*256 and height<=local[1]<=r['runtime_max_y_write']):continue
            if 'turtle' in r and r['turtle']['type']==0 and not self.scripted_poses:
                raise ValueError('diving FORM contact requires source script deviation')
            cell=[(local[0]-ox)>>8,(local[2]-oz)>>8]
            flags=form[8][0][5][cell[1]*nx+cell[0]]
            if index==53 and flags==1:
                self.hits.add(index)
                continue
            if flags!=3:raise ValueError('route FORM changed SAFE reaction')
            self.cell=cell;self.offset=[local[0]<<16,height<<16,local[2]<<16]
            self.target=[local[0],height,local[2]]
            for axis,dim,origin,ci,flag in ((0,nx,ox,cell[0],64),(2,nz,oz,cell[1],128)):
                if not r['book_flags']&flag or abs(local[axis])>((dim-1)*128):self.target[axis]=origin+ci*256+128
            vector=[self.target[k]-(self.offset[k]>>16) for k in range(3)]
            self.count=math.isqrt(sum(v*v for v in vector))//15+1;self.mode=5
            self.velocity=[paths.divided(v<<16,self.count) for v in vector]
            self.animations += [14,5 if abs(vector[0])>=96 or abs(vector[2])>=96 else 14]
            self.attached=index;self.carry();self.y=self.old_y=self.world()[1]
            self.flags=(self.flags&~(2|16|32|64|128|256|16384|65536))|4
            self.direction=quadrant(apply(transpose(matrix),[0,0,4096 if self.heading==0 else -4096]))
            from org1_hilite_admission import ROOTS,multiply
            from org1_route_camera import projected
            self.frog_root=multiply(ROOTS[self.direction][1],matrix)
            self.relative_root=projected(multiply(self.frog_root,transpose(matrix)))
            self.hits.add(index)

    def snapshot(self,tick,phase):
        return dict(tick=tick,phase=phase,x16=self.pos[0],y16=self.pos[1],z16=self.pos[2],flags=self.flags,
                    mode=self.mode,attached=self.attached,count=self.count,old_y=self.old_y,direction=self.direction)


def expected(context,geometry,ticks,commands):
    """Produce six-phase movement/attachment facts independently of the C trace."""
    state=Route(context,geometry,ticks);rows=[]
    for tick in range(ticks):
        state.pose_tick(tick);state.control(commands.get(tick));rows.append(state.snapshot(tick,'control'))
        state.move();rows.append(state.snapshot(tick,'move'))
        state.collide();rows.append(state.snapshot(tick,'collision'))
        for phase in ('camera','scripts','pose'):rows.append(state.snapshot(tick,phase))
    return rows
