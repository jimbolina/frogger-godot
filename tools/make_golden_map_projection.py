#!/usr/bin/env python3
"""Independent synthetic map-slice projection facts from frozen C sources.

python tools/make_golden_map_projection.py tests/golden/pc-retail-v3.0e
Uses no retail files, Godot code/output or other golden generators.
"""
import argparse
import csv
from pathlib import Path

ROWS = ((8192,0,0),(0,5430,-5430),(0,2896,2896))


def short(value):
    return ((value+32768)&65535)-32768


def divide(numerator,denominator):
    """Signed C integer division truncates toward zero, unlike Python //."""
    result = abs(numerator)//abs(denominator)
    return -result if (numerator<0) != (denominator<0) else result


def rotate(vector):
    narrowed = [short(value) for value in vector]
    return [sum(a*b for a,b in zip(row,narrowed))>>12 for row in ROWS]


def project(vertex,camera):
    translation = rotate([-value for value in camera])
    view = [a+b for a,b in zip(rotate(vertex),translation)]
    depth = max(500,view[2])
    screen = [320+divide(view[0]*1000,depth),240+divide(view[1]*1000,depth)]
    triangle = (1365*(depth*3))>>12
    quad = depth
    buckets = [((average>>2)+64) if average>16 and ((average>>2)+64)<4096 else -1
               for average in (triangle,quad)]
    return translation+view+[depth]+screen+[short(v) for v in screen]+[depth&65535,triangle,quad]+buckets


def samples():
    cases = [
        ('origin',(0,0,0),(0,0,0)),
        ('driver_target',(0,-10000,-10000),(0,0,0)),
        ('positive_x',(0,-10000,-10000),(1000,0,0)),
        ('negative_x',(0,-10000,-10000),(-1000,0,0)),
        ('negative_floor',(0,0,0),(-1,-1,0)),
        ('negative_quotient',(0,0,0),(-1,0,1001)),
        ('separate_floor',(1,1,1),(1,1,1)),
        ('negative_vertex',(21,-10000,-10000),(-257,-513,-1025)),
        ('near_below',(0,0,0),(23,0,707)),
        ('near_equal',(0,0,0),(23,0,708)),
        ('near_above',(0,0,0),(23,0,710)),
        ('behind_camera',(0,0,0),(256,-1000,-1000)),
        ('camera_negative_wrap',(-32768,-32768,-32768),(0,0,0)),
        ('camera_positive_wrap',(32768,32768,32768),(0,0,0)),
        ('camera_multiple_wrap',(65537,-65537,100000),(123,-456,789)),
        ('signed_vertex_limits',(0,0,0),(-32768,32767,-32768)),
        ('screen_short_wrap',(0,0,0),(32767,-32768,-32768)),
        ('far_depth',(0,-32767,-32767),(32767,32767,32767)),
    ]
    for z in range(22808,22819):
        cases.append(('ot_boundary_%d'%z,(0,0,0),(7,0,z)))
    for z in range(27153,27161):
        cases.append(('depth_word_%d'%z,(0,-32767,-32767),(-7,0,z)))
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('out_dir')
    args = parser.parse_args()
    out = Path(args.out_dir)
    out.mkdir(parents=True,exist_ok=True)
    header = ['case','camera_x','camera_y','camera_z','vertex_x','vertex_y','vertex_z',
              'translation_x','translation_y','translation_z','view_x','view_y','view_z',
              'clamped_z','screen_x','screen_y','stored_screen_x','stored_screen_y','stored_z_u16',
              'triangle_uniform_average','quad_uniform_average','triangle_uniform_bucket','quad_uniform_bucket']
    with (out/'map_projection.tsv').open('w',encoding='utf-8',newline='') as f:
        writer = csv.writer(f,delimiter='\t',lineterminator='\n')
        writer.writerow(header)
        for name,camera,vertex in samples():
            writer.writerow([name]+list(camera)+list(vertex)+project(vertex,camera))
    print('Generated %d independent map-slice projection samples.'%len(samples()))


if __name__ == '__main__':
    main()
