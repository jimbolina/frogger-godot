"""Independent frozen entity lifetime and uncollected baby-frog model for ORG1."""
import struct
from copy import deepcopy
from make_golden_entity_lifecycle import select
from make_golden_camera_zones import cross,yaw,multiply
from make_golden_paths import normalised,divided
from org1_round_trip import apply

IMMORTAL = {'ORG_BABY_FROG','ORG_FLY','STATIC_NOISE','GEN_TOP_LEFT','GEN_BOTTOM_RIGHT'}
MOVING = {'MOVING','SUB_TURTLE','ORG_BABY_FROG','ORG_FLY'}


def groups_from_map(blob):
    at=struct.unpack_from('<I',blob,struct.unpack_from('<I',blob,80)[0]+8)[0]
    result=dict(base=list(struct.unpack_from('<3h',blob,at+4)),dimensions=list(struct.unpack_from('<2H',blob,at+12)),size=list(struct.unpack_from('<2H',blob,at+16)))
    result['counts']=[sum(blob[at+20+i*72:at+28+i*72]) for i in range(result['dimensions'][0]*result['dimensions'][1])]
    return result


class Lifetime:
    """Persistent authored identities with source-ordered live instance generations."""
    def __init__(self,context,geometry,scripts,actions,cels):
        self.records=geometry['neighbors'];self.groups=groups_from_map(context['data'])
        self.immortal={i for i,r in enumerate(self.records) if r['entity_type'] in IMMORTAL}
        self.live=list(reversed(sorted(self.immortal)));self.pending=set()
        self.generation=[int(i in self.immortal) for i in range(64)]
        self.initial=deepcopy(scripts);self.scripts=scripts;self.actions=actions;self.cels=cels
        self.baby=Baby();self.facts=[]

    def visits(self,attached):
        for i in self.live[:]:
            if i in self.pending and i!=attached:
                self.live.remove(i);self.pending.discard(i)
                if i in self.scripts:self.scripts[i]=deepcopy(self.initial[i])
                continue
            yield i
            if i not in self.immortal:self.pending.add(i)

    def tail(self,tick,route,camera):
        z=normalised([v-u for u,v in zip(camera.source,camera.target)])
        x=normalised(cross([0,4096,0],z));y=cross(z,x)
        groups=select(self.groups,dict(source=camera.source,axes=[x,y,z]))
        total=sum(self.groups['counts'][i] for i in groups)
        if total>=2500:raise ValueError('scripted visibility polygon budget exceeded')
        for group in groups:
            for moving in (True,False):
                for i in range(63,-1,-1):
                    r=self.records[i]
                    if (r['entity_type'] in MOVING)!=moving or r['flags']&1 or i in route.hidden:continue
                    point=route.poses[i][9:] if moving else r['initial_position']
                    gx,gz=route.group(point)
                    if gz*self.groups['dimensions'][0]+gx!=group:continue
                    if i not in self.live:
                        self.live.insert(0,i);self.generation[i]+=1
                        self.cels[i]=-1
                        if i in self.scripts:self.scripts[i]=deepcopy(self.initial[i])
                    self.pending.discard(i)
        self.facts.append(dict(tick=tick,groups=groups,polygons=total,order=self.live[:],baby_mode=self.baby.mode,baby_search=self.baby.search,baby_parent=self.baby.parent,
            entities=[[int(i in self.live),int(i in self.pending),self.generation[i],self.scripts[i].timer if i in self.scripts else 0,
                       self.scripts[i].cel if i in self.scripts else self.cels[i]] for i in range(64)]))


class Baby:
    """Frozen uncollected SEARCHING, WAIT, ON_ENTITY and JUMPING branches."""
    def __init__(self):
        self.mode=0;self.search=0;self.parent=-1;self.direction=0;self.delay=0;self.count=0
        self.cell=[0,0];self.offset=[0,0,0];self.velocity=[0,0,0];self.target=[0,0,0]
        self.action=0;self.sound=False;self.requests=[]

    def update(self,parent_id,live,poses,forms,records,cels):
        self.requests=[]
        def action(value):self.action=value;cels[53]=-1
        if self.mode==0:
            if parent_id in live:
                self.search+=1
                if self.search>=2:
                    self.search=0;self.parent=parent_id;self.direction=0;self.cell=[0,0];self.count=0;self.delay=30;self.velocity=[0,0,0]
                    f=forms[records[parent_id]['form_grid_id']]
                    self.offset=[(f[6]+128)<<16,(f[8][0][2]-30)<<16,(f[7]+128)<<16]
                    self.mode=1;action(1)
                else:self.mode=5
        elif self.mode==5:
            if parent_id not in live:self.mode=0
        elif self.mode==1:
            if self.parent not in live:
                self.mode=0;self.parent=-1;self.delay=0;self.search=0
            else:
                old=self.delay;self.delay-=1
                if old==0:
                    f=forms[records[self.parent]['form_grid_id']]
                    for attempt in range(2):
                        dx,dz=((0,1),(1,0),(0,-1),(-1,0))[self.direction]
                        cell=[self.cell[0]+dx,self.cell[1]+dz]
                        if 0<=cell[0]<f[4] and 0<=cell[1]<f[5]:break
                        self.direction=(self.direction+2)&3
                    else:raise ValueError('baby FORM has no legal autonomous hop')
                    if not f[8][0][5][cell[1]*f[4]+cell[0]]&1:raise ValueError('baby hop requires usable FORM')
                    self.cell=cell;self.target=[cell[0]*256+f[6]+128,f[8][0][2]-30,cell[1]*256+f[7]+128];self.count=6
                    self.velocity=[divided((self.target[k]<<16)-self.offset[k],6) for k in range(3)];self.velocity[1]=-((0x100000*7)>>1)
                    self.mode=2;action(0)
                    if not self.sound:self.sound=True;self.requests=['moving:27:768:1536']
        elif self.mode==2:
            self.count-=1
            if self.count==0:
                self.offset=[v<<16 for v in self.target];self.velocity=[0,0,0];self.mode=1;self.delay=30;action(1)
            else:self.offset=[v+d for v,d in zip(self.offset,self.velocity)]
        else:raise ValueError('unadmitted collected baby mode')
        if self.parent>=0 and self.parent in live:
            m=poses[self.parent];point=apply(m,[((v>>16)+32768)%65536-32768 for v in self.offset])
            poses[53]=multiply(m[:9],yaw(self.direction*1024))+[m[9+k]+point[k] for k in range(3)]
