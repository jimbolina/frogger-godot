#!/usr/bin/env python3
"""Independent integer gameplay projection and preinspection analytic pixel bounds."""
import argparse,csv,math,subprocess
from pathlib import Path
POSES=((0,-500,-500),(-500,-500,0),(0,-1000,-100),(200,-400,400))
POINTS=((0,0,0),(128,0,128),(-128,0,128),(128,0,-128),(-128,0,-128),(0,-64,0),(0,-128,0),(0,0,256),(256,0,0),(0,0,-256))
FIELDS='pose,point,width,height,h,aspect_x,aspect_y,source_x,source_y,source_z,vertex_x,vertex_y,vertex_z,r00,r01,r02,r10,r11,r12,r20,r21,r22,translation_x,translation_y,translation_z,view_x,view_y,view_z,clamped_z,screen_x,screen_y,ca00,ca01,ca02,ca10,ca11,ca12,ca20,ca21,ca22'.split(',')
def rnd(x):return math.floor(x+0.5) if x>=0 else math.ceil(x-0.5)
def normal(v,integer=True):
    scale=(4096 if integer else 1)/math.sqrt(sum(x*x for x in v))
    return [rnd(x*scale) if integer else x*scale for x in v]
def cross(a,b,integer=True):
    v=[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
    return [x>>12 for x in v] if integer else v
def div(a,b):return (-1 if (a<0)!=(b<0) else 1)*(abs(a)//abs(b))
def rows():
    for p,source in enumerate(POSES):
        target=(0,100,0) if p==3 else (0,0,0)
        z=normal([a-b for a,b in zip(target,source)])
        x=normal(cross((0,4096,0),z));y=cross(z,x)
        r=[x,[v*7680>>12 for v in y],z]
        r[0]=[v*2 for v in x]
        translation=[sum(a*-b for a,b in zip(row,source))>>12 for row in r]
        iz=normal([a-b for a,b in zip(target,source)],False)
        ix=normal(cross((0,1,0),iz,False),False);iy=cross(iz,ix,False)
        for q,vertex in enumerate(POINTS):
            view=[(sum(a*b for a,b in zip(row,vertex))>>12)+t for row,t in zip(r,translation)]
            depth=max(128,view[2]);screen=[320+div(view[0]*256,depth),240+div(view[1]*256,depth)]
            # Float renderer reference uses exact unit axes, before rasterization.
            relative=[a-b for a,b in zip(vertex,source)]
            ideal=[sum(a*b for a,b in zip(axis,relative))*aspect for axis,aspect in zip((ix,iy,iz),(2,1.875,1))]
            ideal_depth=max(128,ideal[2]);ideal_screen=[320+ideal[0]*256/ideal_depth,240+ideal[1]*256/ideal_depth]
            # Ratio perturbation bound plus one pixel for C truncation, separately X/Y.
            dz=abs(depth-ideal_depth);low=min(depth,ideal_depth)
            bounds=[256*(abs(view[a]-ideal[a])/low+abs(ideal[a])*dz/(low*ideal_depth))+1 for a in (0,1)]
            facts=[p,q,640,480,256,8192,7680]+list(source)+list(vertex)+sum(r,[])+translation+view+[depth]+screen+[axis[a] for a in range(3) for axis in (x,y,z)]
            # Native Camera3D performs this exact Gram-Schmidt order.
            gx=normal([v/4096 for v in x],False)
            gy0=[v/4096 for v in y];dot=sum(a*b for a,b in zip(gx,gy0))
            gy=normal([b-a*dot for a,b in zip(gx,gy0)],False)
            gz0=[v/4096 for v in z]
            dotx=sum(a*b for a,b in zip(gx,gz0));doty=sum(a*b for a,b in zip(gy,gz0))
            gz=normal([c-a*dotx-b*doty for a,b,c in zip(gx,gy,gz0)],False)
            native=[sum(a*b for a,b in zip(axis,relative))*aspect for axis,aspect in zip((gx,gy,gz),(2,1.875,1))]
            # 27 normalization ops + 33 projection/subtraction ops in GS;
            # 21 view ops + 28 homogeneous projection ops + 11 viewport ops,
            # and 8 setup roundings: at most128 rounded scalar operations.
            gamma128=(128*2**-24)/(1-128*2**-24)
            rounding=gamma128*sum(abs(v) for v in relative)
            errors=[abs(a-b)+rounding*aspect for a,b,aspect in zip(native,ideal,(2,1.875,1))]
            safe_depth=min(depth,ideal_depth)-errors[2]
            assert safe_depth>128
            bounds=[1+256*((abs(view[a]-ideal[a])+errors[a])/safe_depth+abs(ideal[a])*(dz+errors[2])/(safe_depth*ideal_depth))+gamma128*640 for a in (0,1)]
            yield facts,ideal_screen,bounds

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('output',type=Path);parser.add_argument('--c-oracle',type=Path);args=parser.parse_args()
    expected=list(rows())
    if args.c_oracle:
        output=subprocess.check_output([str(args.c_oracle)],text=True)
        lines=output.splitlines();start=next(i for i,l in enumerate(lines) if l.startswith('pose,point,'))
        actual=list(csv.reader(lines[start+1:]));assert len(actual)==len(expected)
        for i,(actual_row,(facts,_,_)) in enumerate(zip(actual,expected)):
            assert list(map(int,actual_row))==facts,(i,actual_row,facts)
        print('Actual frozen C matches all40 rows40 scalar fields.')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('w',newline='',encoding='utf-8') as f:
        w=csv.writer(f,lineterminator='\n');w.writerow(FIELDS+['ideal_screen_x','ideal_screen_y','bound_x_pixels','bound_y_pixels'])
        for facts,ideal,bounds in expected:w.writerow(facts+[format(v,'.9f') for v in ideal+bounds])
    print('Maximum preinspection bounds:',*[max(bounds[a] for _,_,bounds in expected) for a in (0,1)])
if __name__=='__main__':main()
