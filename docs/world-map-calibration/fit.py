from pathlib import Path
import sys, json, math
if len(sys.argv) != 2:
    sys.exit("Usage: python fit.py PATH_TO_SCRATCH")
root = Path(sys.argv[1]).resolve()
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt,map_coordinates
from scipy.optimize import differential_evolution,minimize
from shapely import segmentize
from shapely.geometry import shape
geo=json.loads((root/"countries.geojson").read_text(encoding="utf8"))
points=[]
for f in geo["features"]:
 geom=segmentize(shape(f["geometry"]),.33)
 for polygon in geom.geoms if geom.geom_type=="MultiPolygon" else [geom]:
  points.extend(polygon.exterior.coords)
p=np.unique(np.array(points).round(4),axis=0)
p=p[(p[:,1] > -68) & (p[:,1]<73)]
subset=np.random.default_rng(4).choice(len(p),min(len(p),16000),replace=False)
p=p[subset]
unwrapped=(p[:,0]-80)%360
merc=np.rad2deg(np.arcsinh(np.tan(np.deg2rad(p[:,1]))))
def fit(which):
 img=Image.open(root/which).convert("RGB")
 data=np.asarray(img)
 darkness=(data.max(axis=2)<30)&(np.ptp(data.astype("int16"),axis=2)<20)
 dist=distance_transform_edt(~darkness)
 dist=np.minimum(dist,8)
 def f(v):
  lon_origin,sx,cy,sy=v
  px=(unwrapped+80-lon_origin)*sx
  py=cy-sy*merc
  eligible=(px>5)&(px<635)&(py>12)&(py<459)
  return map_coordinates(dist,np.array([py[eligible],px[eligible]]),order=1).mean()
 res=differential_evolution(f,[(75,85),(1.72,1.83),(228,245),(2.47,2.75)],popsize=12,tol=.0001,seed=83)
 print(which,res.x,res.fun, "width",360*res.x[1])
 canvas=img.resize((1280,960)).convert("RGB")
 draw=ImageDraw.Draw(canvas)
 for feature in geo["features"]:
  ge=feature["geometry"]
  polys=ge["coordinates"] if ge["type"]=="MultiPolygon" else [ge["coordinates"]]
  for poly in polys:
   for ring in poly:
    segments=[[]]
    for lng,lat in ring:
     x=(((lng-80)%360)+80-res.x[0])*res.x[1]
     y=res.x[2]-res.x[3]*math.degrees(math.asinh(math.tan(math.radians(max(-85,min(85,lat))))))
     if segments[-1] and abs(x-segments[-1][-1][0])>320:
      segments.append([])
     segments[-1].append((x,y))
    for seg in segments:
     if len(seg)>1: draw.line([(2*x,2*y) for x,y in seg],fill="#00f5f0",width=1)
 canvas.save(root/("fit-"+which+".png"))
 return res.x.tolist()
if __name__=="__main__":
 (root/"fit.json").write_text(json.dumps({name:fit(name) for name in ("world.gif","world_ir.gif","world_loop.gif")}))

