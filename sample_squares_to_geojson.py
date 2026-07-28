#!/usr/bin/env python3
"""Build a WGS84 GeoJSON from sample_squares.tsv — the map-viewable form of the squares.

GeoJSON (RFC 7946) is defined in CRS84 lon/lat, but the squares are UTM rectangles in two
different zones. Reprojecting only the 4 corners would draw straight lon/lat lines across
edges that are very slightly curved, so each edge is densified to 1 km before transforming.

Usage : ./sample_squares_to_geojson.py sample_squares.tsv sample_squares.geojson

Needs gdaltransform (GDAL). Output is deterministic — rerun it after editing the TSV and
commit both, or the GeoJSON silently goes stale.
"""
import json
import subprocess
import sys

STEP_KM = 1  # densify each 5 km edge to 1 km so the reprojected ring follows the true edge

rows = []
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        if line.startswith("#") or not line.strip():
            continue
        key, epsg, bbox, place, why = line.rstrip("\n").split("\t")
        mine, minn, maxe, maxn = (int(v) for v in bbox.split(","))
        rows.append(dict(key=key, epsg=epsg, bbox=bbox, place=place, why=why,
                         mine=mine, minn=minn, maxe=maxe, maxn=maxn))


def ring_km(r):
    """Closed ring, counter-clockwise (RFC 7946 exterior winding), densified to STEP_KM."""
    pts = []
    for e in range(r["mine"], r["maxe"], STEP_KM):          # south edge, west -> east
        pts.append((e, r["minn"]))
    for n in range(r["minn"], r["maxn"], STEP_KM):          # east edge, south -> north
        pts.append((r["maxe"], n))
    for e in range(r["maxe"], r["mine"], -STEP_KM):         # north edge, east -> west
        pts.append((e, r["maxn"]))
    for n in range(r["maxn"], r["minn"], -STEP_KM):         # west edge, north -> south
        pts.append((r["mine"], n))
    pts.append((r["mine"], r["minn"]))                      # close
    return pts


# One gdaltransform call per CRS rather than per square. OGC:CRS84 is used instead of
# EPSG:4326 so the output is unambiguously lon,lat rather than authority order lat,lon.
for epsg in sorted({r["epsg"] for r in rows}):
    group = [r for r in rows if r["epsg"] == epsg]
    stdin, index = [], []
    for r in group:
        for e, n in ring_km(r):
            stdin.append(f"{e * 1000} {n * 1000}")
            index.append(r["key"])
    out = subprocess.run(
        ["gdaltransform", "-s_srs", f"EPSG:{epsg}", "-t_srs", "OGC:CRS84"],
        input="\n".join(stdin), capture_output=True, text=True, check=True).stdout
    coords = [l.split() for l in out.splitlines() if l.strip()]
    if len(coords) != len(index):
        sys.exit(f"ERROR: gdaltransform returned {len(coords)} points, expected {len(index)}")
    for r in group:
        r["ll"] = [[round(float(c[0]), 7), round(float(c[1]), 7)]
                   for c, k in zip(coords, index) if k == r["key"]]

features = []
for r in rows:
    lons = [p[0] for p in r["ll"]]
    lats = [p[1] for p in r["ll"]]
    features.append({
        "type": "Feature",
        "bbox": [min(lons), min(lats), max(lons), max(lats)],
        "geometry": {"type": "Polygon", "coordinates": [r["ll"]]},
        "properties": {
            "key": r["key"],
            "place": r["place"],
            "why": r["why"],
            "utm_epsg": int(r["epsg"]),
            "utm_bbox_km": r["bbox"],
            "bbox_env": f'BBOX="{r["bbox"]}"',
            "size_km": 5,
        },
    })

all_lons = [p[0] for r in rows for p in r["ll"]]
all_lats = [p[1] for r in rows for p in r["ll"]]
doc = {
    "type": "FeatureCollection",
    "name": "sample_squares",
    "bbox": [min(all_lons), min(all_lats), max(all_lons), max(all_lats)],
    "features": features,
}
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    json.dump(doc, fh, ensure_ascii=False, indent=1)
    fh.write("\n")
print(f"{len(features)} squares -> {sys.argv[2]}")
