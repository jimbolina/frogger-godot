#!/usr/bin/env python3
"""Independent frozen normal road movement joined to the existing river route."""
import org1_traffic as traffic
import make_golden_paths as paths
import make_golden_grid as grid
import org1_hilite_reach as hilite
from org1_round_trip import Route


class RoadRoute(Route):
    """Flat SAFE road hops and deadly cuboids with prior stored frog probes."""
    def __init__(self,context,geometry,ticks):
        super().__init__(context,geometry,ticks)
        self.pos=[128<<16,-256<<16,-1664<<16]
        self.decoded=traffic.decode(context);self.stored_key=None;self.points=[]
        self.root=(4096,0,0,0,4096,0,0,0,4096)
        self.dead=False;self.first_killer=-1;self.primitive_contacts=[]
        self.store_pose(0,0)

    def pose_tick(self,tick):
        super().pose_tick(tick);self.primitive_contacts=[]

    def store_pose(self,action,cel):
        """Mirror STATIC source cache and previous supported-root sample lifetime."""
        key=(action,self.decoded[2][action]['cels'][cel])
        if key==self.stored_key:return
        self.stored_key=key
        self.points=[] if self.world()[2]>=-128 else traffic.stored_points(self.root,self.world(),action,cel,self.decoded)

    def control(self,direction):
        self.animations=[]
        if self.flags&8:self.flags&=~8;self.mode=2;self.dead=True
        if self.dead:return
        if direction is None:return
        if self.attached>=0 or self.world()[2]>=-128:return super().control(direction)
        if self.mode!=0 or direction!=0:raise ValueError('road fixture requires settled NORTH hops')
        self.mode=1;self.count=6;self.direction=self.heading=0;self.flags|=64
        self.target=[self.world()[0],-256,self.world()[2]+256];self.y=-256
        terrain=next(cell for cell in self.geometry['terrain'] if cell['world_x'][0]<=self.target[0]<cell['world_x'][1] and cell['world_z'][0]<=self.target[2]<cell['world_z'][1])
        up=grid.normal(terrain['layers'][0]['vertices']);x=paths.normalised(grid.cross([0,0,4096],up));z=grid.cross(up,x)
        self.root=hilite.axes(x,[-v for v in up],z)
        self.animations.append(16)
        self.velocity=[0,-(1048576*7>>1),paths.divided(256<<16,6)]

    def move(self):
        if self.count and self.flags&64 and self.target[2]<0:
            self.count-=1
            if not self.count:
                self.pos=[v<<16 for v in self.target];self.velocity=[0,0,0]
                self.attached=self.forbidden=-1;self.mode=2 if self.dead else 0
                self.flags&=~(2|4|16|32|64|128|256|16384|65536)
                self.y=self.old_y=self.world()[1]
                if not self.dead:self.animations.append(14)
            else:self.airborne()
        elif not self.dead:super().move()

    def collide(self):
        self.hits=set();self.primitive_contacts=[]
        if self.mode==2 or self.flags&8:return
        for index in self.scan():
            if index not in self.decoded[0]:continue
            record=self.records[index];m=self.poses[index]
            delta=[paths.signed(self.world()[k]-m[9+k],16) for k in range(3)]
            if paths.signed(sum(v*v for v in delta))>=record['radius_squared']:continue
            contact=traffic.primitive_hit(m,self.decoded[0][index],self.points)
            if contact:
                self.primitive_contacts.append((index,*contact));self.hits.add(index)
                if self.first_killer<0:
                    self.first_killer=index;self.flags=(self.flags&~2048)|8;self.animations.append(2)
                    if self.mode!=1 or not self.flags&64:self.velocity=[0,0,0]
        if not self.flags&8:super().collide()

    def snapshot(self,tick,phase):
        result=super().snapshot(tick,phase)
        result.update(zip(('vx16','vy16','vz16'),self.velocity))
        result.update(death_equate=2 if self.first_killer>=0 else 0,lives=2 if self.first_killer>=0 else 3,
                      first_killer=self.first_killer,stored_action=self.stored_key[0],stored_actual_cel=self.stored_key[1],
                      primitive_hit_indices=';'.join(str(p[0]) for p in self.primitive_contacts) or '-',
                      primitive_contacts=';'.join(f'{p[0]}:{p[1]}:{p[2]}:0' for p in self.primitive_contacts) or '-')
        return result
