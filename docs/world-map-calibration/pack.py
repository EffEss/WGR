from pathlib import Path
import sys,json,base64
if len(sys.argv) != 2:
    sys.exit("Usage: python pack.py PATH_TO_SCRATCH")
root = Path(sys.argv[1]).resolve()
import numpy as np
from shapely import make_valid, segmentize, transform
from shapely.affinity import translate
from shapely.geometry import box,shape,Polygon
from shapely.geometry.polygon import orient

# Coastline fit measured on Sirocco's 640x480 wmerc still and animation.
LONGITUDE_SEAM=75.4
HEIGHT=480
WIDTH=640
EQUATOR=240.16
MERCATOR_SCALE=2.6645
QUANTIZATION=8

def world_y(lat):
 latitude=np.clip(lat,-85,85)
 mercator=np.degrees(np.arcsinh(np.tan(np.radians(latitude))))
 # Continue the outline past the Mercator limit without a singularity at the poles.
 polar_tail=np.sign(lat)*np.maximum(0,np.abs(lat)-85)*2.2
 return HEIGHT-EQUATOR+MERCATOR_SCALE*(mercator+polar_tail)

def project(points):
 x=(points[:,0]-LONGITUDE_SEAM)*(WIDTH/360)
 y=world_y(points[:,1])
 return np.column_stack((x,y))

def polygons(geometry):
 if isinstance(geometry,Polygon) and not geometry.is_empty:
  yield geometry
 elif hasattr(geometry,"geoms"):
  for member in geometry.geoms:
   yield from polygons(member)

def quantize(ring):
 pts=[]
 for x,y in ring.coords:
  point=(round(x*QUANTIZATION),round(y*QUANTIZATION))
  if not pts or point!=pts[-1]: pts.append(point)
 if pts and pts[0]==pts[-1]: pts.pop()
 return pts

def varint(out, value):
 while value>=128:
  out.append((value&127)|128)
  value >>= 7
 out.append(value)

def pack(parts):
 out=bytearray()
 varint(out,len(parts))
 for part in parts:
  varint(out,len(part))
  for ring in part:
   varint(out,len(ring))
   px,py=0,0
   for x,y in ring:
    for delta in (x-px,y-py):
     varint(out,2*delta if delta>=0 else -2*delta-1)
    px,py=x,y
 return base64.b64encode(out).decode("ascii")

source=json.loads((root/"countries.geojson").read_text(encoding="utf8"))
output=[]
slab=box(0,-400,WIDTH,900)
lost=[]
count=0
for feature in source["features"]:
 props=feature["properties"]
 name=props["NAME_LONG"]
 geom=transform(segmentize(shape(feature["geometry"]),1),project)
 parts=[]
 for shift in (0,WIDTH):
  for poly in polygons(make_valid(translate(geom,xoff=shift)).intersection(slab)):
   poly=orient(poly.simplify(.22,preserve_topology=True))
   exterior=quantize(poly.exterior)
   if len(exterior)<3:
    center=poly.representative_point()
    # Keep microstates/territories clickable after quantization.
    if poly.area < geom.area*.4: continue
    x,y=round(center.x*QUANTIZATION),round(center.y*QUANTIZATION)
    exterior=[(x,y-1),(x+1,y),(x,y+1),(x-1,y)]
   holes=[quantize(ring) for ring in poly.interiors]
   parts.append([exterior,*[ring for ring in holes if len(ring)>=3]])
 if not parts and not geom.is_empty:
  center=geom.representative_point()
  x,y=round((center.x%WIDTH)*QUANTIZATION),round(center.y*QUANTIZATION)
  parts=[[[ (x,y-1),(x+1,y),(x,y+1),(x-1,y) ]]]
 if parts:
  output.append((name,pack(parts)))
  count += sum(len(ring) for part in parts for ring in part)
 else: lost.append(name)
assert not lost,lost
out="\n".join(json.dumps(row,ensure_ascii=True,separators=(",",":")) for row in sorted(output))
(root/"world-country-data.json").write_text("[\n"+",\n".join(out.splitlines())+"\n]",encoding="utf8")
print(len(output),"countries and territories;",count,"projected vertices;",len(out),"inline bytes")
print("Polar map bounds",world_y(-90),world_y(90))

