"""Declare source-derived foreground bounds before candidate rendering."""
import argparse,json,math,re,hashlib
from pathlib import Path
from PIL import Image

def normalize(v):
 d=math.sqrt(sum(x*x for x in v));return [x/d for x in v]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def axes(matrix):
 x=normalize([matrix[a]/4096 for a in (0,3,6)])
 y=[matrix[a]/4096 for a in (1,4,7)];y=normalize([a-b*dot(x,y) for a,b in zip(y,x)])
 z=[matrix[a]/4096 for a in (2,5,8)];dx=dot(x,z);dy=dot(y,z)
 return x,y,normalize([a-b*dx-c*dy for a,b,c in zip(z,x,y)])
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--log',type=Path,required=True);p.add_argument('--source-image',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 repo=Path(__file__).resolve().parents[1]
 for protected in (repo,repo.parent/'froggy'):
  if a.output.resolve()==protected.resolve() or protected.resolve() in a.output.resolve().parents:p.error('Output must be outside both repositories')
 text=a.log.read_text();line=[l for l in text.splitlines() if l.startswith('CAPTURE_FACTS')][-1]
 def vector(key):return list(map(int,re.search(r'(?:^| )'+key+r'=([-0-9,]+)',line).group(1).split(',')))
 camera=vector('camera');basis=vector('basis');frog=vector('frog');frog_basis=vector('frog_basis');camera_axes=axes(basis)
 fixture={'source_image':str(a.source_image.resolve()),'source_sha256':hashlib.sha256(a.source_image.read_bytes()).hexdigest(),'source_log_sha256':hashlib.sha256(a.log.read_bytes()).hexdigest(),'camera':camera,'camera_basis':basis,'frog':frog,'frog_basis':frog_basis,'action':vector('action')[0],'cel':vector('cel')[0],'landmarks':[]}
 catalog=(repo/'assets/catalog.tres').read_text(encoding='utf-8')
 fixture['input_sha256']={name:re.search(key+r' = "([0-9a-f]{64})"',catalog).group(1) for name,key in (('FROGGER.EXE','exe_sha256'),('FROGPSX.MWD','mwd_sha256'))}
 fixture['part_flags']={int(v[1]):{'flags':int(v[2]),'rendered':bool(int(v[3]))} for v in (line.split() for line in text.splitlines() if line.startswith('PART_FLAGS '))}
 assert fixture['part_flags'], 'Source visibility facts required'
 gamma=(146*2**-24)/(1-146*2**-24)
 for line in text.splitlines():
  if not line.startswith('LANDMARK '):continue
  v=list(map(int,line.split()[1:]));part,index=v[:2];local=v[2:5];mat=v[5:14];trans=v[14:17];view=v[17:20];screen=v[20:22]
  world=[dot(mat[r*3:r*3+3],local)/4096+trans[r] for r in range(3)]
  rel=[x-y for x,y in zip(world,camera)];native=[dot(axis,rel)*scale for axis,scale in zip(camera_axes,(2,1.875,1))]
  rounding=gamma*(sum(abs(x) for x in rel)+sum(abs(x) for x in local))
  dz=abs(view[2]-native[2])+rounding;lower=min(view[2],native[2])-rounding;assert lower>128
  bounds=[1+256*((abs(view[i]-native[i])+rounding*scale)/lower+abs(native[i])*dz/(lower*native[2]))+gamma*640 for i,scale in enumerate((2,1.875))]
  fixture['landmarks'].append({'part':part,'vertex':index,'screen':screen,'bounds':bounds,'rendered':fixture['part_flags'][part]['rendered']})
 fixture['max_bounds']=[max(v['bounds'][i] for v in fixture['landmarks']) for i in (0,1)]
 fixture['silhouette_radius_chebyshev']=math.ceil(max(fixture['max_bounds']))+1
 image=Image.open(a.source_image).convert('RGB');assert image.size==(640,480)
 fixture['source_nonblack_pixels']=sum(pixel!=(0,0,0) for pixel in image.getdata());assert fixture['source_nonblack_pixels']>0
 a.output.write_text(json.dumps(fixture,indent=2));print('Declared',len(fixture['landmarks']),'landmarks; max bounds',fixture['max_bounds'],'silhouette radius',fixture['silhouette_radius_chebyshev'])
if __name__=='__main__':main()
