"""Run an isolated native foreground and verify predeclared source-derived bounds."""
import argparse,json,os,re,subprocess,uuid,hashlib
from pathlib import Path
from PIL import Image,ImageChops,ImageFilter
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',required=True);p.add_argument('--fixture',type=Path,required=True);p.add_argument('--output-directory',type=Path,required=True);a=p.parse_args()
 repo=REPO_ROOT;out=a.output_directory.resolve()
 for protected in (repo,repo.parent/'froggy'):
  if out==protected.resolve() or protected.resolve() in out.parents:p.error('Output must be outside both repositories')
 fixture=json.loads(a.fixture.read_text());source=Path(fixture['source_image']);assert hashlib.sha256(source.read_bytes()).hexdigest()==fixture['source_sha256']
 catalog=(repo/'assets/catalog.tres').read_text(encoding='utf-8')
 imported={name:re.search(key+r' = "([0-9a-f]{64})"',catalog).group(1) for name,key in (('FROGGER.EXE','exe_sha256'),('FROGPSX.MWD','mwd_sha256'))}
 for name,digest in fixture['input_sha256'].items():assert imported[name]==digest, 'Imported assets come from other inputs than the source'
 run=out/('foreground-'+uuid.uuid4().hex);(run/'profile').mkdir(parents=True);(run/'temp').mkdir()
 env=os.environ.copy();env.update(APPDATA=str(run/'profile'),XDG_DATA_HOME=str(run/'profile'),TEMP=str(run/'temp'),TMP=str(run/'temp'))
 startup=None
 if os.name=='nt':startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
 def stage(name,args,headless=True):
  log=run/(name+'.log');cmd=[a.godot,'--disable-crash-handler','--path',str(repo),'--log-file',str(log)]+(['--headless'] if headless else [])+args
  with (run/(name+'-process.log')).open('w') as f:result=subprocess.run(cmd,cwd=repo,env=env,startupinfo=startup,stdout=f,stderr=subprocess.STDOUT,timeout=120)
  text=log.read_text() if log.exists() else ''
  if result.returncode or not text or any(s in text for s in ('SCRIPT ERROR','Parse Error','Failed to load script','CHECK FAILED')):raise RuntimeError(f'{name} failed, see {log}')
 stage('import',['--import']);stage('check',['-s','res://tools/check/check_scripts.gd'])
 stage('capture',['-s','res://tools/inspection/capture_gameplay_foreground.gd','--','--fixture='+str(a.fixture.resolve()),'--output-directory='+str(run)],False)
 actual=json.loads((run/'candidate-landmarks.json').read_text());assert actual['size']==[640,480]
 observed={(v['part'],v['vertex']):v['screen'] for v in actual['landmarks']};failures=[];max_errors=[0,0]
 for v in fixture['landmarks']:
  if not v['rendered']:continue
  screen=observed[(v['part'],v['vertex'])]
  for axis in (0,1):
   error=abs(screen[axis]-v['screen'][axis]);max_errors[axis]=max(max_errors[axis],error)
   if error>v['bounds'][axis]:failures.append({'part':v['part'],'vertex':v['vertex'],'axis':axis,'error':error,'bound':v['bounds'][axis]})
 def mask(path):
  image=Image.open(path).convert('RGB');assert image.size==(640,480)
  return Image.frombytes('L',image.size,bytes(255 if pixel!=(0,0,0) else 0 for pixel in image.getdata()))
 sm=mask(source);cm=mask(run/'candidate-foreground.png');radius=fixture['silhouette_radius_chebyshev'];kernel=radius*2+1
 outside_source=ImageChops.subtract(cm,sm.filter(ImageFilter.MaxFilter(kernel)));outside_candidate=ImageChops.subtract(sm,cm.filter(ImageFilter.MaxFilter(kernel)))
 missing_candidate=sum(v!=0 for v in outside_candidate.getdata());extra_candidate=sum(v!=0 for v in outside_source.getdata());nonblack=sum(v!=0 for v in cm.getdata())
 summary={'raw_landmarks':len(observed),'compared_visible_landmarks':sum(v['rendered'] for v in fixture['landmarks']),'max_pixel_errors':max_errors,'landmark_failures':failures,'radius_chebyshev':radius,'source_outside_candidate_dilation':missing_candidate,'candidate_outside_source_dilation':extra_candidate,'candidate_nonblack_pixels':nonblack,'pass':not failures and not missing_candidate and not extra_candidate and nonblack>0}
 (run/'comparison.json').write_text(json.dumps(summary,indent=2));print(run);print(json.dumps(summary))
 if not summary['pass']:raise SystemExit(1)
if __name__=='__main__':main()
