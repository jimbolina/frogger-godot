#!/usr/bin/env python3
"""Compare external map PNGs using masks declared before comparison.

Example:
  python tools/compare_map_captures.py --reference C:/captures/c.png
    --candidate C:/captures/g.png --masks C:/captures/masks.json
    --out-dir C:/captures/comparison

Mask JSON schema (pixel coordinates; rectangles have exclusive right/bottom):
  {"eligible_terrain": [{"rect": [0,0,640,480]}],
   "include": [{"polygon": [[0,0],[639,0],[639,479],[0,479]]}],
   "exclude": [{"rect": [0,0,640,40], "reason": "HUD"}],
   "raster_edge_policy": "eligible_union_silhouette",
   "landmarks": [{"name": "corner", "reference": [100,100],
                  "candidate": [101,100], "tolerance_px": 2}]}

eligible_terrain is the independently declared denominator. include is the
declared test area; exclusions require reasons. Never infer masks from errors.
The source eligible union silhouette receives a fixed two-pixel band; texture gradients
never generate exclusions. A pass requires >=1000 compared terrain pixels,
>=50% coverage of declared eligible terrain, >=95% pixels within eight per RGB
channel, and all declared landmarks within their stated tolerance (default 2).
Images, JSON masks and outputs must live outside this repository.
Exit 0 passes, 1 fails the comparison, 2 indicates invalid inputs.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops

REPOSITORY = Path(__file__).resolve().parent.parent


def external(path):
    resolved = Path(path).resolve()
    if resolved == REPOSITORY or REPOSITORY in resolved.parents:
        raise ValueError('capture inputs and outputs must be outside the repository: '+str(resolved))
    return resolved


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def shape_mask(size, shapes, reasons=False):
    if not isinstance(shapes, list):
        raise ValueError('mask shapes must be a list')
    mask = Image.new('L', size)
    draw = ImageDraw.Draw(mask)
    width, height = size
    for shape in shapes:
        if reasons and not str(shape.get('reason', '')).strip():
            raise ValueError('every exclusion requires a reason')
        if 'rect' in shape and 'polygon' not in shape:
            x0, y0, x1, y1 = shape['rect']
            if not all(isinstance(x, int) for x in (x0,y0,x1,y1)) or not (0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height):
                raise ValueError('rectangle outside image or empty')
            draw.rectangle((x0,y0,x1-1,y1-1), fill=255)
        elif 'polygon' in shape and 'rect' not in shape:
            points = shape['polygon']
            if len(points) < 3 or any(len(p) != 2 or not all(isinstance(x,int) for x in p) or not (0 <= p[0] < width and 0 <= p[1] < height) for p in points):
                raise ValueError('invalid polygon coordinates')
            draw.polygon([tuple(p) for p in points], fill=255)
        else:
            raise ValueError('each mask shape requires exactly one rect or polygon')
    return mask


def reference_edges(eligible):
    edges = ImageChops.subtract(eligible, eligible.filter(ImageFilter.MinFilter(3)))
    return edges.filter(ImageFilter.MaxFilter(5))


def pixel_values(image):
    return list(getattr(image, 'get_flattened_data', image.getdata)())


def compare(reference_path, candidate_path, masks_path, out_dir):
    output_names = ('metrics.json','difference.png','overlay.png','compared_mask.png','reference_edge_band.png')
    output_paths = {out_dir/name for name in output_names}
    if any(path in output_paths for path in (reference_path,candidate_path,masks_path)):
        raise ValueError('an output would overwrite a comparison input')
    declaration = json.loads(masks_path.read_text(encoding='utf-8'))
    reference = Image.open(reference_path).convert('RGB')
    candidate = Image.open(candidate_path).convert('RGB')
    if reference.size != candidate.size:
        raise ValueError('image dimensions differ; resampling is forbidden')
    eligible = shape_mask(reference.size, declaration['eligible_terrain'])
    inclusion = shape_mask(reference.size, declaration['include'])
    exclusion = shape_mask(reference.size, declaration['exclude'], True)
    if declaration.get('raster_edge_policy') != 'eligible_union_silhouette':
        raise ValueError('masks must declare eligible_union_silhouette raster edge policy')
    edge_band = reference_edges(eligible)
    eligibility = pixel_values(eligible)
    included = pixel_values(inclusion)
    excluded = pixel_values(exclusion)
    edges = pixel_values(edge_band)
    ref, cand = pixel_values(reference), pixel_values(candidate)
    compared = passing = maximum_error = total_error = 0
    channel_sums = [0,0,0]
    diff, overlay, tested = [], [], []
    eligible_count = sum(bool(value) for value in eligibility)
    eligible_inclusion = eligible_exclusion = eligible_edges = 0
    for i, (r,c) in enumerate(zip(ref,cand)):
        error = tuple(abs(a-b) for a,b in zip(r,c))
        selected = bool(eligibility[i] and included[i] and not excluded[i] and not edges[i])
        if eligibility[i]:
            eligible_inclusion += bool(included[i])
            eligible_exclusion += bool(included[i] and excluded[i])
            eligible_edges += bool(included[i] and not excluded[i] and edges[i])
        diff.append(tuple(min(255,v*8) for v in error) if selected else (0,0,0))
        tested.append(255 if selected else 0)
        if selected:
            compared += 1
            good = max(error) <= 8
            passing += good
            maximum_error = max(maximum_error,max(error))
            total_error += sum(error)
            channel_sums = [a+b for a,b in zip(channel_sums,error)]
            overlay.append(r if good else (255,0,255))
        else:
            overlay.append(tuple(v//4 for v in r))
    landmarks = []
    for landmark in declaration['landmarks']:
        reference_point, candidate_point = landmark['reference'], landmark['candidate']
        for point in (reference_point,candidate_point):
            if len(point) != 2 or not (0 <= point[0] < reference.width and 0 <= point[1] < reference.height):
                raise ValueError('landmark outside image')
        distance = math.dist(reference_point,candidate_point)
        tolerance = float(landmark.get('tolerance_px',2))
        if tolerance < 0 or not math.isfinite(tolerance):
            raise ValueError('invalid landmark tolerance')
        landmarks.append(dict(name=landmark['name'], reference=reference_point,
                              candidate=candidate_point, distance_px=distance,
                              tolerance_px=tolerance, passed=distance <= tolerance))
    coverage = compared/eligible_count if eligible_count else 0
    fraction = passing/compared if compared else 0
    checks = dict(minimum_pixels=compared >= 1000, minimum_coverage=coverage >= .5,
                  channel_agreement=fraction >= .95,
                  landmarks_declared=bool(landmarks), landmarks=all(x['passed'] for x in landmarks))
    metrics = dict(reference=str(reference_path), candidate=str(candidate_path), masks=str(masks_path),
                   reference_sha256=digest(reference_path), candidate_sha256=digest(candidate_path),
                   masks_sha256=digest(masks_path), dimensions=list(reference.size),
                   eligible_terrain_pixels=eligible_count, included_eligible_pixels=eligible_inclusion,
                   explicit_exclusion_pixels=eligible_exclusion, reference_edge_exclusion_pixels=eligible_edges,
                   compared_pixels=compared, coverage=coverage, passing_pixels=passing,
                   passing_fraction=fraction, maximum_channel_error=maximum_error,
                   mean_absolute_channel_error=total_error/(compared*3) if compared else None,
                   mean_channel_errors=[v/compared for v in channel_sums] if compared else None,
                   thresholds=dict(channel_error=8, passing_fraction=.95, minimum_coverage=.5,
                                   minimum_pixels=1000, reference_edge_band_px=2),
                   edge_policy='Source eligible union silhouette; internal seams tested; no image gradients',
                   landmarks=landmarks, checks=checks, passed=all(checks.values()))
    out_dir.mkdir(parents=True,exist_ok=True)
    (out_dir/'metrics.json').write_text(json.dumps(metrics,indent=2)+'\n',encoding='utf-8')
    for name,pixels in (('difference.png',diff), ('overlay.png',overlay)):
        im = Image.new('RGB',reference.size)
        im.putdata(pixels)
        im.save(out_dir/name)
    Image.frombytes('L',reference.size,bytes(tested)).save(out_dir/'compared_mask.png')
    edge_band.save(out_dir/'reference_edge_band.png')
    return metrics


def main():
    parser = argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--reference',required=True)
    parser.add_argument('--candidate',required=True)
    parser.add_argument('--masks',required=True,help='External JSON declaration; declare before seeing differences')
    parser.add_argument('--out-dir',required=True,help='External metrics and PNG output directory')
    args = parser.parse_args()
    try:
        metrics = compare(*(external(x) for x in (args.reference,args.candidate,args.masks,args.out_dir)))
    except (ValueError,KeyError,TypeError,OSError) as error:
        parser.exit(2,str(error)+'\n')
    print('%s: %d pixels, coverage %.2f%%, channel agreement %.2f%%; metrics %s' %
          ('PASS' if metrics['passed'] else 'FAIL',metrics['compared_pixels'],
           metrics['coverage']*100,metrics['passing_fraction']*100,Path(args.out_dir)/'metrics.json'))
    return 0 if metrics['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
