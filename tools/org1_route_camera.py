#!/usr/bin/env python3
"""Independent frozen follow-camera subset for the normal ORG1 round trip."""
import math
from make_golden_camera import damp,trig
from make_golden_paths import divided,normalised
from make_golden_grid import cross
from org1_hilite_admission import multiply,axes,ROOTS
from org1_round_trip import apply,transpose,quadrant


def projected(matrix):
    z=normalised([matrix[2],0,matrix[8]])
    x=normalised(cross([0,4096,0],z))
    return axes(x,[0,4096,0],z)


class Camera:
    """No zones, twist, shake or fixed-camera modes are used by this fixture."""
    def __init__(self,source,target):
        self.mod=ROOTS[0][1];self.current=[128,-256,-128]
        self.source_offset=source;self.target_offset=target
        self.source=[a+b for a,b in zip(self.current,source)]
        self.target=[a+b for a,b in zip(self.current,target)];self.controller=0
        self.theta=self.delta=self.destination=0

    def transfer(self,old,new,poses,landed=False):
        if old==new:return
        if old>=0:self.mod=multiply(self.mod,projected(poses[old]))
        if new>=0:self.mod=multiply(self.mod,transpose(projected(poses[new])))
        if new>=0 or landed:
            z=[self.mod[2],self.mod[5],self.mod[8]]
            d=0 if z[2]>2896 else 2 if z[2]<-2896 else 1 if z[0]>2896 else 3
            axis=[ROOTS[d][1][2],0,ROOTS[d][1][8]]
            dot=sum(a*b for a,b in zip(axis,z))>>12
            angle=math.floor(math.acos(max(-4096,min(4096,dot))/4096)*2048/math.pi)
            normal=cross(axis,z)[1];self.destination=0
            if normal:
                self.destination=4096 if d==0 and normal<0 else d*1024
                self.theta=self.destination+(angle if normal>0 else -angle)
                self.delta=-32 if normal>0 else 32
            else:self.delta=0

    def update(self,route):
        dest=route.world()
        if route.mode==1 and not route.flags&128:
            dest[1]=route.old_y+divided((6-route.count)*(route.y-route.old_y),6)
        dest[1]=min(dest[1],0)
        self.current=[damp(a,b,24 if i==1 else None) for i,(a,b) in enumerate(zip(self.current,dest))]
        if self.delta:
            self.theta+=self.delta
            if (self.delta>0 and self.theta>=self.destination) or (self.delta<0 and self.theta<=self.destination):
                self.theta=self.destination;self.delta=0
            sine=trig(self.theta);cosine=trig(self.theta,True)
            self.mod=(cosine,0,sine,0,4096,0,-sine,0,cosine)
        matrix=self.mod
        if route.attached>=0:matrix=multiply(matrix,projected(route.poses[route.attached]))
        source=apply(matrix,self.source_offset);target=apply(matrix,self.target_offset)
        self.source=[a+b for a,b in zip(self.current,source)]
        self.target=[a+b for a,b in zip(self.current,target)]
        self.controller=quadrant([target[0]-source[0],0,target[2]-source[2]])

    def snapshot(self):
        result={}
        for prefix,values in (('camera',self.current),('source',self.source),('target',self.target)):
            result.update((prefix+'_'+axis,value) for axis,value in zip('xyz',values))
        result.update(('controller_'+str(i),(self.controller+i)&3) for i in range(4))
        result.update(('camera_mod'+str(r)+str(c),self.mod[r*3+c]) for r in range(3) for c in range(3))
        return result
