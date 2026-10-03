"""Recompute every JUN1 neighbor exclusion over complete authored path cycles."""
from pathlib import Path
import struct, math, json
import make_golden_exe_tables as ex,make_golden_form_contacts as co,make_golden_mof as mo,make_golden_retail_platform as rp,make_golden_paths as pa,make_golden_entities as en
import argparse
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--data-dir', required=True, type=Path)
ROOT = parser.parse_args().data_dir
# The runtime guard pins these same MAP, form, script, WAD and model inputs.
# Fail before geometry work if any determining input changed.
rp.route_fixture(ROOT, 'pc-retail-v3.0e', return_context=True)
cfg=ex.parse_cfg(str(Path(ex.CFG_ROOT)/'versions/pc-retail-v3.0e.cfg'));im=ex.Exe((ROOT/'FROGGER.EXE').read_bytes(),ex.java_int(cfg.values['ramOffset']));levels,_=ex.read_map_book(im,ex.java_int(cfg.values['mapBook']),ex.java_int(cfg.values['themeBook']));_,entries,wads,files=mo.load_archive(str(ROOT),ex.java_int(cfg.values['mwiOffset']),ex.java_int(cfg.values['mwiLength']));mwd=(ROOT/'FROGPSX.MWD').read_bytes();level=levels[ex.LEVEL_CODES.index('JUN1')];data=rp.resource(files,entries,mwd,level['high_map']);theme=co.read(data,co.read(data,76,'<I')+10,'<H');emtp=co.read(data,88,'<I');forms=co.parse_forms(data)
names,sections,_=ex.name_list('forms',cfg.values.get('formList','1997-09-12-psx-build57'));ens,_,_=ex.name_list('entities',cfg.values.get('entityList','1997-09-12-psx-build57'));lib=ex.read_forms(im,ex.read_theme_book(im,ex.java_int(cfg.values['themeBook'])),sections,[])
paths=[];pp=co.read(data,96,'<I')
for pi in range(co.read(data,pp+4,'<I')):
 ptr=co.read(data,pp+8+pi*4,'<I');segments=[]
 for si in range(co.read(data,ptr+4,'<I')):
  at=co.read(data,ptr+8+si*4,'<I');kind,length=struct.unpack_from('<2i',data,at);s={'segment_type':kind,'length':length}
  if kind==0:
   v=struct.unpack_from('<28i',data,at+8);s.update(matrix=list(v[:12]),smooth_t=list(v[12:16]),smooth_c=list(v[16:]))
  elif kind==1:s.update(start=list(struct.unpack_from('<3h',data,at+8)),centre=list(struct.unpack_from('<3h',data,at+16)),normal=list(struct.unpack_from('<3h',data,at+24)),radius=co.read(data,at+32,'<i'),pitch=co.read(data,at+36,'<i'))
  else:s.update(start=list(struct.unpack_from('<3h',data,at+8)),end=list(struct.unpack_from('<3h',data,at+16)))
  segments.append(s)
 paths.append(segments)
models={};entities=[]
offsets=[co.read(data,emtp+12+4*j,'<I') for j in range(co.read(data,emtp+8,'<I'))]
for i,at in enumerate(offsets):
 grid,uid,fi,flags=struct.unpack_from('<4H',data,at);bk=lib[0 if fi&0x8000 else theme][fi&0x7fff];name=names[bk['global']];typ=ens[bk['entity_type']]
 e=dict(index=i,unique=uid,at=at,grid=grid,flags=flags,name=name,type=typ,book=bk)
 if bk['flags'] & 1:
  e['mid']=-1;e['model']=None
  e['payload']=data[at+24:min([x for x in offsets if x>at]+[emtp+co.read(data,emtp+4,'<I')])]
  entities.append(e)
  continue
 try:
  mid=wads[level['high_wad']][bk['id']][0]
  if mid not in models:models[mid]=mo.parse_model(rp.resource(files,entries,mwd,mid),name,None,[])
  e['mid']=mid;e['model']=models[mid]
 except Exception as exc:e['model_error']=str(exc)
 e['payload']=data[at+24:min([x for x in offsets if x>at]+[emtp+co.read(data,emtp+4,'<I')])]
 entities.append(e)


import make_golden_animation as ani
themes=ex.read_theme_book(im,ex.java_int(cfg.values['themeBook']))
for e in entities:
 if e['book']['flags'] & 1:continue
 if e['book']['id']>=128:
  mid=wads[themes[0]['high_wad']][e['book']['id']-128][0]
  if mid not in models:
   rawmid=rp.resource(files,entries,mwd,mid)
   try: models[mid]=mo.parse_model(rawmid,e['name'],None,[])
   except mo.MofError as exc:
    if 'incomplete' not in str(exc):raise
    candidates=sorted({rid for children in wads.values() for rid,typ in children if typ in (3,4) and rid<mid},reverse=True)
    for rid in candidates:
     try: counterpart=mo.parse_model(rp.resource(files,entries,mwd,rid),str(rid),None,[])
     except mo.MofError:continue
     if not counterpart['incomplete']:break
    checked=mo.parse_model(rawmid,e['name'],counterpart,[])
    models[mid]=counterpart
  e['mid']=mid;e['model']=models[mid];e.pop('model_error',None)
for e in entities:
 if e['book']['flags'] & 1:
  e['radius2']=e['book']['radius2']
  continue
 b=e['book'];m=e['model'];raw=rp.resource(files,entries,mwd,e['mid']);r=b['radius2']
 if r==0 and m['kind']!='dummy':
  if m['kind']=='animated':
   ar=ani.parse_xar(raw);box=ar['sets'][0][0][0][3];r=max(sum(v*v for v in box[j:j+3]) for j in range(0,len(box),3))
  else:
   for p in m['statics'][0]['parts']:
    for cel in p['partcel_list']:
     box=cel['box']
     for j in range(0,len(box),3):r=max(r,sum(v*v for v in box[j:j+3]))
    if p['collprims']:
     at=p['collprim_ptr']
     for _ in range(p['collprims']):
      kind,fl=struct.unpack_from('<HH',raw,at);ox,oy,oz,pad,rad,xl,yl,zl,pad2,mat=struct.unpack_from('<hhhhiHHHHi',raw,at+12)
      rr=xl*xl+yl*yl+zl*zl if kind==0 else (xl*xl if kind==1 else yl*yl if kind==2 else zl*zl if kind==3 else 0)+rad
      r=max(r,ox*ox+oy*oy+oz*oz+rr);at+=36
  r+=100
 e['radius2']=r

rect=(1900,2303,-5376,-4865);pnear={}
for pi,segments in enumerate(paths):
 best=(10**20,None)
 for si,s in enumerate(segments):
  for d in range(s['length']+1):
   _,p,t=pa.sample(s,d,False);dx=max(rect[0]-p[0],p[0]-rect[1],0);dz=max(rect[2]-p[2],p[2]-rect[3],0);dd=dx*dx+dz*dz
   if dd<best[0]:best=(dd,(si,d,p,t))
 pnear[pi]=best
possible=set()
for e in entities:
 i=e['index'];b=e['book']
 if b['flags']&1:
  assert b['collision']==0, ('unproved NO_MODEL callback',i)
  continue
 assert not e['flags']&8, ('unexpected hidden/collision-suppressed entity',i)
 if i<=36:
  pi=struct.unpack_from('<H',e['payload'])[0];best=pnear[pi];print(i,e['name'],'radius',e['radius2'],'nearestXZ2',best[0], 'POSSIBLE' if best[0]<e['radius2'] else 'excluded','witness',best[1] if best[0]<e['radius2'] else '')
  if best[0]<e['radius2']:possible.add(i)
 else:
  p=struct.unpack_from('<3i',e['payload'],20);dx=max(rect[0]-p[0],p[0]-rect[1],0);dz=max(rect[2]-p[2],p[2]-rect[3],0);dd=dx*dx+dz*dz
  print(i,e['name'],'radius',e['radius2'],'nearestXZ2',dd,'POSSIBLE' if dd<e['radius2'] else 'excluded','pos',p if dd<e['radius2'] else '')
  if dd<e['radius2']:possible.add(i)
assert possible=={0,16,18,20,21,22,23,24,25,26,27,31,109,110}, ('unproved contact candidates',sorted(possible))

from fractions import Fraction
# All non-scripted supported models are handled by existing setup, but retain
# the fixed exceptions to document the complete rectangle audit.
for idx,minx in [(109,2561),(110,2570)]:
 e=entities[idx];m=list(struct.unpack_from('<9h2x3i',e['payload']));f=forms[e['grid']]
 assert m[:9]==[4096,0,0,0,4096,0,0,0,4096]
 assert m[9]+f[6]+1==minx and minx>=2304
 assert sum(p['collprims'] for s in e['model']['statics'] for p in s['parts'])==0
print('FIXED_FORM_EXCLUSIONS tree109_minX=2561 mushroom110_minX=2570')

# Crocodile has no primitives in any static component; SET_ACTION never changes
# its generic moving root transform. Invert the exact quantized transpose,
# using inclusive real bounds that conservatively contain integer floor tests.
e=entities[0];f=forms[e['grid']];_,_,_,_,nx,nz,ox,oz,items=f
assert sum(p['collprims'] for s in e['model']['statics'] for p in s['parts'])==0
bestz=None;bestzw=None;crocposes=0
for si,s in enumerate(paths[1]):
 for d in range(s['length']+1):
  crocposes+=1;_,pos,tan=pa.sample(s,d,False);m=en.moving_matrix([0]*9+pos+tan,0)
  assert m[3]==m[5]==0
  a,b,c,dd=m[0],m[6],m[2],m[8];det=a*dd-b*c
  for lx in [(ox+1)*4096,(ox+nx*256)*4096]:
   for lz in [(oz+1)*4096,(oz+nz*256)*4096]:
    z=pos[2]+Fraction(-c*lx+a*lz,det)
    if bestz is None or z>bestz:bestz=z;bestzw=(si,d,pos,tan)
assert bestz < -5376
print('CROC0_EXACT_INVERSE_MAX_Z',str(bestz),float(bestz),'POSES',crocposes,'WITNESS',bestzw)

# The HIPPO program changes only root Y. The entire cycle is therefore bounded
# in XZ independently of script timer and vertical deviation. All authored
# runners repeat forward; enumerate a superset: every integer segment distance.
e=entities[23];f=forms[e['grid']];_,_,_,_,nx,nz,ox,oz,items=f;r=e['radius2']
assert r==119457 and [q['index'] for q in entities if q['grid']==e['grid']]==[18,20,21,22,23]
assert all(struct.unpack_from('<6H',entities[i]['payload'])[3]==8 for i in [18,20,21,22,23])
best=(-999999,None);count=0;tiltedcount=0;tiltedcap=-999999
def interval(a,b,lo,hi):
 if a==0:return (-100000,100000) if lo<=b<hi else (1,0)
 if a>0:return (-((b-lo)//a),(hi-1-b)//a)
 a=-a;return (-((hi-1-b)//a),(b-lo)//a)
for si,s in enumerate(paths[2]):
 for d in range(s['length']+1):
  count+=1;_,pos,tan=pa.sample(s,d,False)
  if pos[0]+math.isqrt(r-1)<1800 or pos[2]+math.isqrt(r-1)<-5376 or pos[2]-math.isqrt(r-1)>=-4864:continue
  m=en.moving_matrix([0]*9+pos+tan,0)
  if m[3] or m[5]:
   tiltedcount+=1
   assert m[3]==m[6]==0 and abs(m[0])==4096
   tiltedcap=max(tiltedcap,pos[0]+(ox+nx*256-1 if m[0]>0 else -ox-1))
   continue
  for z in range(-5376,-4864):
   dz=z-pos[2];rr=r-1-dz*dz
   if rr<0:continue
   lim=math.isqrt(rr);lower,upper=-lim,lim
   for a,b,lo,hi in [(m[0],m[6]*dz,(ox+1)*4096,(ox+nx*256)*4096),(m[2],m[8]*dz,(oz+1)*4096,(oz+nz*256)*4096)]:
    l,h=interval(a,b,lo,hi);lower=max(lower,l);upper=min(upper,h)
   if lower<=upper and pos[0]+upper>best[0]:best=(pos[0]+upper,(si,d,pos,tan,z))
assert best[0]==1888 and tiltedcap==1789 and max(best[0],tiltedcap)<1900
print('HIPPO_EXACT_MAX_X',best,'POSES',count,'TILTED',tiltedcount,'TILTED_X_CAP',tiltedcap)

# Pin the failure at the original proposed west edge through a reachable runner.
row=pa.python_trace({'segments':paths[2],'start':{'segment_index':2,'distance':171,'speed':30,'flags':9},'tick_limit':27})[-1]
pos=row[9:12];tan=row[12:15];m=en.moving_matrix([0]*9+pos+tan,0);frog=[1856,-256,-4924];delta=[a-b for a,b in zip(frog,pos)]
local=[sum(m[rr*3+cc]*delta[rr] for rr in range(3))>>12 for cc in range(3)]
assert pos==[1655,-256,-4691] and local==[112,0,-287] and sum(v*v for v in delta)==94690
print('ORIGINAL_RECTANGLE_FAILED',{'entity_index':23,'uid':entities[23]['unique'],'offset':entities[23]['at'],'advanced_tick':27,'frog':frog,'entity_position':pos,'local':local,'distance2':94690,'radius2':119457})


# Explicit NO_MODEL rejection and arithmetic closure. A null collision callback
# takes COLLIDE.C's next_entity branch before primitives/FORM.
nomodel=[]
for e in entities:
 if e['book']['flags']&1:
  assert e['book']['collision']==0, ('unproved NO_MODEL callback',e['index'])
  nomodel.append(e['index'])
print('NO_MODEL_NULL_CALLBACK_EXCLUDED',nomodel)
# Maximal XZ contribution bounds signed32 squared-distance arithmetic for ANY
# signed16 Y, even if the unbounded mathematical Y difference wraps on cast.
maxxz=(-1,None);delta_min=[10**20,10**20];delta_max=[-10**20,-10**20]
def check_origin(p,label):
 global maxxz
 for x in [1900,2303]:
  for z in [-5376,-4865]:
   dx,dz=x-p[0],z-p[2]
   delta_min[0]=min(delta_min[0],dx);delta_min[1]=min(delta_min[1],dz)
   delta_max[0]=max(delta_max[0],dx);delta_max[1]=max(delta_max[1],dz)
   sq=dx*dx+dz*dz
   if sq>maxxz[0]:maxxz=(sq,(label,p,x,z))
for pi,segments in enumerate(paths):
 for si,s in enumerate(segments):
  for d in range(s['length']+1):
   _,p,t=pa.sample(s,d,False);check_origin(p,('path',pi,si,d))
for e in entities[37:]:
 p=struct.unpack_from('<3i',e['payload'],20)
 check_origin(p,('static',e['index']))
assert all(v>=-32768 for v in delta_min) and all(v<=32767 for v in delta_max)
assert maxxz[0]+32768**2<2**31
print('SIGNED16_XZ_DELTA_RANGE',delta_min,delta_max)
print('MAX_XZ_SQUARE',maxxz)
print('MAX_SIGNED32_DISTANCE_WITH_ANY_SIGNED16_Y',maxxz[0]+32768**2,'LT',2**31)
print('REVISED_GEOMETRY_PASSED X[1900,2304) Z[-5376,-4864); pinned retail inputs and source semantics')
