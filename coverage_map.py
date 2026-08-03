#!/usr/bin/env python3
"""Draw this repo's per-state coverage as maps. Three of them, same geometry, same three tiers.

One per section of README.md, which answers the same questions in prose and tables; these put
the answers on geometry, so a glance replaces a table read.

  coverage  can we fetch all four datasets -- point cloud, terrain, plots, house structures?
            green  all four are scriptable today                                        (5)
            orange elevation works, but one of the four is missing at the source         (4)
            red    no bulk LiDAR endpoint at all -- these states are cadastre-only       (7)

  lidar     what elevation can a script actually fetch in bulk?
            green  point cloud + terrain                                                 (7)
            orange open, but no bulk endpoint -- interactive portal only                 (7)
            red    terrain only -- the state publishes no point cloud                    (2)

  alkis     what does the state's cadastre actually contain?
            green  full vector ALKIS ohne Eigentuemer                                   (14)
            orange raster cadastral map only -- a picture of the parcels, not geometry   (2)
            red    not open data                                                         (0)

Colour is per-map, not per-tier, because "worst" is a different question on each. The lidar
map inverts the other two: red is the state with no point cloud to fetch, orange the one
behind a portal, since a portal state still has every product -- just not scriptably -- while
a state that publishes no point cloud has nothing more to give however you ask.

Red never means "closed" except on the alkis map. All 16 states publish elevation openly, and
orange on the alkis map is likewise not a delivery problem: BY and RP publish their cadastre
as raster, so the download works and the geometry simply is not in it. The legends say so,
because "not supported" would be wrong in every one of those cases.

Inputs are read from bundeslaender.geojson's own properties (lidar_las, lidar_dgm1,
lidar_script, alkis, alkis_engine, alkis_spatial) so the maps cannot drift from the GeoJSON.
Only building footprints need a table here -- see HOUSES below.

Boundaries come from bundeslaender.geojson (CRS84 lon/lat), so run
bundeslaender_to_geojson.py first if it is missing.

Usage : ./coverage_map.py [coverage|lidar|alkis|all] [out.svg] [bundeslaender.geojson]

  ./coverage_map.py            # coverage_map.svg + .png
  ./coverage_map.py lidar      # lidar_map.svg + .png
  ./coverage_map.py alkis      # alkis_map.svg + .png
  ./coverage_map.py all        # all three, to their default names

Stdlib only. A PNG is written beside each SVG if rsvg-convert, Chromium or qlmanage is found.
"""
import json
import math
import os
import shutil
import subprocess
import sys
from xml.sax.saxutils import escape

# Scriptable building footprints, from hauskoordinaten-hausumringe.md (probed 2026-07-28).
# This is the one input the GeoJSON does not carry. "True" means a direct anonymous URL or a
# feed/WFS a script can drive -- not merely that the data is open.
#
# Note the overlap that makes the green tier bigger than it looks: ALKIS carries AX_Gebaeude,
# so any state with full ALKIS already ships footprints inside the parcel package. The states
# below that are True *without* full ALKIS (by, rp, st) have a standalone HU product instead.
HOUSES = {
    "bw": True,   # hu_bw.zip, direct
    "by": True,   # 7 Regierungsbezirk ZIPs off the KML index
    "be": True,   # ALKIS gebaeude WFS + HK-DE-format ZIP
    "bb": True,   # inside the per-Landkreis ALKIS Shape packages
    "hb": True,   # WFS only (wfs_alkis_hausumringe)
    "hh": True,   # inside the quarterly ALKIS GML
    "he": False,  # Downloadcenter needs a free account; ALKIS API exposes parcels, not buildings
    "mv": True,   # dedicated Hausumringe Atom -> hu-mv.zip
    "ni": True,   # priced as HU, but footprints come via the ALKIS gebaeude WFS
    "nw": True,   # gru_vereinfacht GeoPackage per Kreis + gebref
    "rp": True,   # HAUSUMRINGE_RP.zip with a .meta4
    "sl": True,   # inside the per-Landkreis ALKIS packages
    "sn": True,   # hu_sn_shape.zip (ranged GET -- the share 401s on HEAD)
    "st": True,   # Hausumringe.zip, direct; also ave:GebaeudeBauwerk in the ALKIS WFS
    "sh": True,   # inside the statewide ALKIS GeoJSON
    "th": True,   # inside the per-Flur ALKIS Shape/NAS packages (standalone HU/HK are
                  # CAPTCHA-gated, but that is a second route, not the only one)
}
# th used to be False here, justified by the standalone HU/HK products being CAPTCHA-gated and
# by th landing red anyway for want of bulk elevation. Both halves are gone: download_th_lidar.sh
# fetches the elevation, and "inside the ALKIS package" is exactly what already counts as True
# for bb, sl, sh and hh. Judging th by a stricter rule than its neighbours was the bug.

# (stroke, fill). Which tier gets which colour is a per-map decision -- see each map's legend
# in MAPS below -- because "worst" is not the same question on every map.
PALETTE = {
    "green":  ("#2e7d32", "#a5d6a7"),
    "orange": ("#e65100", "#ffcc80"),
    "red":    ("#b71c1c", "#ef9a9a"),
}

# Labels that do not fit inside their own polygon: (dx, dy) in output px from the centroid,
# drawn with a leader line back to it. The city-states, plus Saarland.
OFFSET_LABELS = {
    "be": (82, -20),
    "hh": (-52, -20),
    "hb": (-54, -8),
    "sl": (-46, 6),
}

# Labels that fit, but land on something: Berlin sits almost exactly on Brandenburg's
# centroid, so BB's own label has to step aside. No leader line -- it stays inside BB.
NUDGE = {"bb": (20, 82)}

W, H, PAD = 620, 800, 14
LEGEND_H = 118

# Both maps label states with the repo-wide ID, so both say so. See "The state ID" in
# README.md -- the ID is the ISO 3166-2 code minus the DE- prefix, and the same string
# indexes the GeoJSON, sample_squares.tsv, download_alkis.sh and the output trees.
FOOTNOTE = "Labels are state IDs — ISO 3166-2 without the DE- prefix."


def classify_coverage(props, key):
    """Return (tier, detail) for the all-four-datasets map.

    lidar_dgm1/lidar_las say the state *publishes* the product; lidar_script says this repo
    can actually fetch it in bulk. The map is about what we can fetch, so both are required --
    that gap is the whole reason seven states are red while publishing elevation openly.
    """
    scripted = bool(props.get("lidar_script"))
    have = {
        "point cloud": scripted and bool(props.get("lidar_las")),
        "terrain": scripted and bool(props.get("lidar_dgm1")),
        "plots": props.get("alkis") == "full",
        "houses": HOUSES[key],
    }
    missing = [k for k, v in have.items() if not v]
    detail = ", ".join(k for k, v in have.items() if v) or "none"
    if missing:
        detail += f" (missing: {', '.join(missing)})"
    if not missing:
        return "full", detail
    # No elevation at all is a different kind of gap from missing one product.
    if not have["point cloud"] and not have["terrain"]:
        return "none", detail
    return "partial", detail


def classify_lidar(props, key):
    """Return (tier, detail) for the elevation map.

    The split that matters is not open/closed -- all 16 publish elevation openly -- but
    whether a script can reach it in bulk, and then whether both products are there to reach.
    See this map's legend in MAPS for which tier gets which colour; it is not the same
    assignment as the other two maps.
    """
    script = props.get("lidar_script")
    if not script:
        return "none", f"no bulk endpoint. {props.get('lidar_note') or ''}".strip()
    have = [n for n, ok in (("point cloud", props.get("lidar_las")),
                            ("terrain", props.get("lidar_dgm1"))) if ok]
    bbox = "BBOX supported" if props.get("lidar_bbox") else "no BBOX support"
    detail = f"{script} — {' + '.join(have)}; {bbox}"
    return ("full" if len(have) == 2 else "partial"), detail


# How finely download_alkis.sh can cut what a state publishes, spelled out for the tooltip.
SPATIAL = {
    "exact": "any bbox (service query)",
    "tile": "1 km tile",
    "flur": "per Flur",
    "gemeinde": "per Gemeinde",
    "gemarkung": "per Gemarkung",
    "package": "whole package only",
    "none": "n/a",
}


def classify_alkis(props, key):
    """Return (tier, detail) for the cadastre map, straight off the GeoJSON's alkis fields.

    'partial' is not a delivery problem here -- BY and RP publish their cadastre as raster
    (Parzellarkarte / Liegenschaftskarte) with no bulk vector parcels. The download works
    fine; what arrives is a picture of the parcels, not their geometry.
    """
    tier = {"full": "full", "partial": "partial", "none": "none"}[props["alkis"]]
    if tier == "none":
        return tier, "not open data -- parcels need a formal request"
    what = "full vector oE" if tier == "full" else "raster cadastral map only"
    return tier, (f"{what}; {props.get('alkis_engine') or '-'} engine, "
                  f"{SPATIAL.get(props.get('alkis_spatial'), '?')}")


# Each map is a classifier plus the words and colours that go under it. Same geometry, same
# renderer. Legend rows are (tier, colour, label) and render top-to-bottom in this order.
MAPS = {
    "coverage": dict(
        out="coverage_map.svg",
        classify=classify_coverage,
        heading="Point cloud + terrain + plots + house structures",
        legend=[("full", "green", "all four datasets"),
                ("partial", "orange", "missing one of the four"),
                ("none", "red", "no bulk LiDAR - cadastre only")],
    ),
    "lidar": dict(
        out="lidar_map.svg",
        classify=classify_lidar,
        heading="LiDAR / terrain — what a script can fetch in bulk",
        # Red is "terrain only" here, not "no bulk endpoint" -- the inverse of the other two
        # maps. A state with no point cloud published has nothing more to give; one behind a
        # portal has all of it, just not scriptably, so it is the milder of the two.
        legend=[("full", "green", "point cloud + terrain"),
                ("none", "orange", "open, but no bulk endpoint — portal only"),
                ("partial", "red", "terrain only — no point cloud published")],
    ),
    "alkis": dict(
        out="alkis_map.svg",
        classify=classify_alkis,
        heading="ALKIS cadastre - parcels, buildings, land use",
        legend=[("full", "green", "full vector cadastre (oE)"),
                ("partial", "orange", "raster cadastral map only"),
                ("none", "red", "not open data")],
    ),
}


def rings(geom):
    """Yield every exterior ring; holes are dropped (none matter at this scale)."""
    if geom["type"] == "Polygon":
        polys = [geom["coordinates"]]
    else:
        polys = geom["coordinates"]
    for poly in polys:
        if poly:
            yield poly[0]


def simplify(pts, tol):
    """Douglas-Peucker. Keeps the SVG small enough to read as text."""
    if len(pts) < 3:
        return pts
    ax, ay = pts[0]
    bx, by = pts[-1]
    dx, dy = bx - ax, by - ay
    span = math.hypot(dx, dy)
    worst, idx = -1.0, 0
    for i in range(1, len(pts) - 1):
        px, py = pts[i]
        if span == 0:
            d = math.hypot(px - ax, py - ay)
        else:
            d = abs(dy * px - dx * py + bx * ay - by * ax) / span
        if d > worst:
            worst, idx = d, i
    if worst <= tol:
        return [pts[0], pts[-1]]
    return simplify(pts[:idx + 1], tol)[:-1] + simplify(pts[idx:], tol)


def centroid(ring):
    """Area-weighted centroid of a ring (shoelace)."""
    a = cx = cy = 0.0
    for i in range(len(ring) - 1):
        x0, y0 = ring[i]
        x1, y1 = ring[i + 1]
        cross = x0 * y1 - x1 * y0
        a += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    if a == 0:
        return ring[0]
    return cx / (3 * a), cy / (3 * a)


def main():
    argv = sys.argv[1:]
    which = argv.pop(0) if argv and argv[0] in MAPS else "coverage"
    if argv and argv[0] in ("-h", "--help", "all"):
        if argv[0] == "all":
            for name in MAPS:
                sys.argv = [sys.argv[0], name]
                main()
            return
        sys.exit(__doc__)
    spec = MAPS[which]
    out = argv[0] if argv else spec["out"]
    src = argv[1] if len(argv) > 1 else "bundeslaender.geojson"
    if not os.path.exists(src):
        sys.exit(f"{src} not found -- run ./bundeslaender_to_geojson.py first")

    feats = json.load(open(src, encoding="utf-8"))["features"]

    # Equirectangular, scaled by cos(mid-latitude). Germany spans ~8 degrees of latitude, so
    # this is within a couple of percent of a proper conic -- fine for a thumbnail, and it
    # keeps the script dependency-free.
    lats = [c[1] for f in feats for r in rings(f["geometry"]) for c in r]
    lons = [c[0] for f in feats for r in rings(f["geometry"]) for c in r]
    kx = math.cos(math.radians((min(lats) + max(lats)) / 2))
    x0, x1 = min(lons) * kx, max(lons) * kx
    y0, y1 = min(lats), max(lats)
    scale = min((W - 2 * PAD) / (x1 - x0), (H - LEGEND_H - 2 * PAD) / (y1 - y0))
    ox = PAD + ((W - 2 * PAD) - (x1 - x0) * scale) / 2

    def project(lon, lat):
        return (ox + (lon * kx - x0) * scale, PAD + (y1 - lat) * scale)

    colour = {tier: PALETTE[name] for tier, name, _ in spec["legend"]}
    drawn, labels, counts = [], [], {"full": 0, "partial": 0, "none": 0}
    for f in feats:
        p = f["properties"]
        key = p["key"]
        tier, detail = spec["classify"](p, key)
        counts[tier] += 1
        stroke, fill = colour[tier]

        biggest, best_area = None, -1.0
        paths = []
        for ring in rings(f["geometry"]):
            pts = [project(c[0], c[1]) for c in ring]
            pts = simplify(pts, 0.55)
            if len(pts) < 4:
                continue
            area = abs(sum(pts[i][0] * pts[i + 1][1] - pts[i + 1][0] * pts[i][1]
                           for i in range(len(pts) - 1)) / 2)
            if area < 3:                      # drop specks: small islands, sandbanks
                continue
            if area > best_area:
                best_area, biggest = area, pts
            paths.append("M" + "L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + "Z")

        # detail can carry a state's free-text lidar_note, so it must be escaped.
        tip = escape(f"{p['name']} - {tier}: {detail}")
        drawn.append((best_area,
                      f'  <path d="{"".join(paths)}" fill="{fill}" stroke="{stroke}" '
                      f'stroke-width="1.1" stroke-linejoin="round"><title>{tip}</title></path>'))

        cx, cy = centroid(biggest)
        if key in OFFSET_LABELS:
            # Leader lines go in the label layer, not the fill layer: Berlin sits inside
            # Brandenburg and Hamburg inside Schleswig-Holstein, so anything drawn with the
            # polygons gets painted over by the state that encloses it.
            dx, dy = OFFSET_LABELS[key]
            lx, ly = cx + dx, cy + dy
            labels.append(f'  <line x1="{cx:.1f}" y1="{cy:.1f}" x2="{lx:.1f}" y2="{ly:.1f}" '
                          f'stroke="{stroke}" stroke-width="0.8"/>')
        else:
            dx, dy = NUDGE.get(key, (0, 0))
            lx, ly = cx + dx, cy + dy
        labels.append(f'  <text x="{lx:.1f}" y="{ly + 3.5:.1f}" fill="{stroke}">'
                      f'{key.upper()}</text>')

    # Largest first, so the enclosed city-states stay visible.
    body = [svg for _, svg in sorted(drawn, key=lambda d: -d[0])]

    ly = H - LEGEND_H + 30
    leg = [f'  <text x="{PAD}" y="{ly - 14}" class="h">{spec["heading"]}</text>']
    for i, (tier, name, text) in enumerate(spec["legend"]):
        text = f"{text} ({counts[tier]})"
        stroke, fill = PALETTE[name]
        y = ly + i * 20
        leg.append(f'  <rect x="{PAD}" y="{y - 9}" width="15" height="12" rx="2" '
                   f'fill="{fill}" stroke="{stroke}" stroke-width="1.1"/>')
        leg.append(f'  <text x="{PAD + 22}" y="{y}" class="l">{text}</text>')
    leg.append(f'  <text x="{PAD}" y="{ly + len(spec["legend"]) * 20 + 2}" class="f">'
               f'{FOOTNOTE}</text>')

    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" \
viewBox="0 0 {W} {H}" font-family="Helvetica,Arial,sans-serif">
  <style>
    text {{ font-size: 11px; font-weight: 600; text-anchor: middle; }}
    text.l {{ font-size: 12px; font-weight: 400; text-anchor: start; fill: #333; }}
    text.h {{ font-size: 12px; font-weight: 700; text-anchor: start; fill: #111; }}
    text.f {{ font-size: 10px; font-weight: 400; text-anchor: start; fill: #777; }}
  </style>
  <rect width="{W}" height="{H}" fill="#fff"/>
{chr(10).join(body)}
{chr(10).join(labels)}
{chr(10).join(leg)}
</svg>
'''
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(svg)
    print(f"{out}  {os.path.getsize(out) / 1024:.0f} KB  "
          f"({counts['full']} full / {counts['partial']} partial / {counts['none']} none)")

    rasterize(os.path.abspath(out), os.path.splitext(os.path.abspath(out))[0] + ".png")


# Chromium before qlmanage on purpose: qlmanage -t always writes a *square* thumbnail, so a
# 620x800 map comes back cropped and the legend is the part that gets cut.
CHROMIUM = ["/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "chromium", "google-chrome", "chromium-browser"]


def rasterize(svg, png):
    if shutil.which("rsvg-convert"):
        subprocess.run(["rsvg-convert", "-w", str(W * 2), svg, "-o", png], check=True)
    else:
        browser = next((b for b in CHROMIUM
                        if os.path.exists(b) or shutil.which(b)), None)
        if browser:
            subprocess.run([browser, "--headless", "--disable-gpu", "--hide-scrollbars",
                            "--force-device-scale-factor=2", f"--window-size={W},{H}",
                            f"--screenshot={png}", f"file://{svg}"],
                           check=True, capture_output=True)
        elif shutil.which("qlmanage"):
            subprocess.run(["qlmanage", "-t", "-s", str(W * 2),
                            "-o", os.path.dirname(png) or ".", svg],
                           check=True, capture_output=True)
            if os.path.exists(svg + ".png"):
                os.replace(svg + ".png", png)
            print("note: qlmanage crops to a square -- the legend may be cut off. "
                  "Install librsvg (brew install librsvg) for a faithful PNG.")
        else:
            print("no SVG rasterizer found (tried rsvg-convert, Chromium, qlmanage) "
                  "-- SVG written, PNG skipped")
            return
    if os.path.exists(png):
        print(f"{png}  {os.path.getsize(png) / 1024:.0f} KB")


if __name__ == "__main__":
    main()
