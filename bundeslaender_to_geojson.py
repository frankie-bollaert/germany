#!/usr/bin/env python3
"""Build a Bundesland-boundary GeoJSON carrying this repo's LiDAR and ALKIS coverage.

The point is a map you can style: which states have a working downloader, which publish the
data openly but resist bulk access, and which publish nothing. That question is answered in
prose across README_download.md; this puts the same answer on geometry.

Boundaries come from BKG VG2500 (1:2,500,000 Verwaltungsgebiete), refetched on every run
rather than vendored — the same rule the download_* scripts follow for their file lists.
VG2500 splits each Land into land and water polygons; only GF=9 (the land body) is kept, so
Baden-Wuerttemberg does not arrive as a separate Bodensee feature.

Usage : ./bundeslaender_to_geojson.py bundeslaender.geojson [sample_squares.tsv]

Needs curl, unzip and ogr2ogr (GDAL). Output is CRS84 lon/lat per RFC 7946, matching
sample_squares.geojson, so the two overlay directly.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

VG2500 = ("https://daten.gdz.bkg.bund.de/produkte/vg/vg2500/aktuell/"
          "vg2500_12-31.utm32s.gpkg.zip")

# Coverage as recorded in README_download.md (verified live 2026-08-04).
# Those two documents remain the prose source of truth; this is their machine-readable form.
#
#   lidar_dgm1 / lidar_las : does the state publish it openly at all
#   lidar_script           : the downloader in this repo, or None if there is no endpoint
#   lidar_offline          : a confirmed bulk route with no endpoint behind it -- today only
#                            Hessen's hard disk. None everywhere else. A state is reachable in
#                            bulk if it has EITHER a script or an offline route; the maps
#                            colour by that, and mark the offline ones so green does not read
#                            as "scripted". Priced or sample-only routes do not qualify --
#                            see the st entry.
#   lidar_bbox             : does that downloader accept BBOX
#   lidar_note             : how the state is reached, or why it cannot be
#   alkis                  : full | partial | none  (oE = ohne Eigentuemer; owners are never open)
#   alkis_engine           : which of the four download engines the state needs
#   alkis_spatial          : how finely a 5x5 km sample can be cut from what it publishes
#                            exact | tile | flur | gemeinde | gemarkung | package | none
COVERAGE = {
    "sh": dict(name_short="Schleswig-Holstein",
               lidar_dgm1=True, lidar_las=False, lidar_script="download_sh_lidar.sh",
               lidar_bbox=True,
               lidar_note="GeoJSON tile index of 18,685 DGM1 tiles, each with a direct link; "
                          "ASCII XYZ, ~515 GB statewide. About 1.7% of index entries are stale "
                          "and the portal serves an error body for them. No point cloud "
                          "published.",
               alkis="full", alkis_engine="aria2", alkis_spatial="package"),
    "hh": dict(name_short="Hamburg",
               lidar_dgm1=True, lidar_las=False, lidar_script="download_hh_lidar.sh",
               lidar_bbox=True,
               lidar_note="Directory listings 403, but the archives themselves are anonymous "
                          "and honour Range; the file list comes from the Transparenzportal "
                          "CKAN API. DGM1 in 9 vintages (2022 is GeoTIFF, earlier XYZ) plus "
                          "the image-derived bDOM. No point cloud published.",
               alkis="full", alkis_engine="aria2", alkis_spatial="package"),
    "ni": dict(name_short="Niedersachsen",
               lidar_dgm1=True, lidar_las=False, lidar_script="download_ni_lidar.sh",
               lidar_bbox=True, lidar_note=None,
               alkis="full", alkis_engine="wfs2", alkis_spatial="exact"),
    "hb": dict(name_short="Bremen",
               lidar_dgm1=False, lidar_las=False, lidar_script=None, lidar_bbox=None,
               lidar_note="No open LiDAR bulk product identified.",
               alkis="full", alkis_engine="wfs1", alkis_spatial="exact"),
    "nw": dict(name_short="Nordrhein-Westfalen",
               lidar_dgm1=True, lidar_las=True, lidar_script="download_nrw_lidar.sh",
               lidar_bbox=True, lidar_note=None,
               alkis="full", alkis_engine="aria2", alkis_spatial="package"),
    # HE is the reason lidar_offline exists. HVBG confirmed by email (2026-08-04) that it will
    # copy the statewide laser scan onto a hard disk you post them, free -- and DGM1 is free in
    # the storefront. Both products are therefore obtainable whole, which is what these maps
    # are asked to show, so HE is green with lidar_script=None. The absence of an endpoint is
    # carried by lidar_offline and the * on the label, not by a worse colour: "we cannot
    # automate it" and "you cannot have it" are different claims and only the first is true.
    "he": dict(name_short="Hessen",
               lidar_dgm1=True, lidar_las=True, lidar_script=None, lidar_bbox=None,
               lidar_offline="point cloud on a hard disk posted to HVBG; DGM1 through the free "
                             "gds.hessen.de storefront",
               lidar_note="Both products are free and obtainable statewide, neither through an "
                          "endpoint: the laser scan is copied onto a hard disk you post to "
                          "HVBG, and DGM1 is a zero-price Intershop cart with no static index. "
                          "Manual either way, so there is no script.",
               alkis="full", alkis_engine="ogcapi", alkis_spatial="exact"),
    "rp": dict(name_short="Rheinland-Pfalz",
               lidar_dgm1=True, lidar_las=True, lidar_script="download_rlp_lidar.sh",
               lidar_bbox=False,
               lidar_note="Downloader exists but is the only one without BBOX; its Metalink "
                          "filenames already carry UTM km, so adding it is mechanical.",
               alkis="partial", alkis_engine="metalink", alkis_spatial="tile"),
    "bw": dict(name_short="Baden-Wuerttemberg",
               lidar_dgm1=True, lidar_las=False, lidar_script="download_bw_lidar.sh",
               lidar_bbox=True, lidar_note=None,
               alkis="full", alkis_engine="aria2", alkis_spatial="gemarkung"),
    "by": dict(name_short="Bayern",
               lidar_dgm1=True, lidar_las=True, lidar_script="download_by_lidar.sh",
               lidar_bbox=True, lidar_note=None,
               alkis="partial", alkis_engine="aria2", alkis_spatial="package"),
    # The 2025 laser scan is open and statewide in the LVGL Nextcloud share, DGM1 and DOM1
    # alongside it. All three are now wired into download_sl_lidar.sh, so the green tier no
    # longer overstates the repo -- the caveat that used to live here is gone.
    "sl": dict(name_short="Saarland",
               lidar_dgm1=True, lidar_las=True, lidar_script="download_sl_lidar.sh",
               lidar_bbox=True,
               lidar_note="Point cloud, DGM1 and DOM1 are all scripted out of the public LVGL "
                          "Nextcloud share (laz and GeoTIFF, one ZIP per Landkreis).",
               alkis="full", alkis_engine="aria2", alkis_spatial="package"),
    "be": dict(name_short="Berlin",
               lidar_dgm1=True, lidar_las=True, lidar_script="download_be_lidar.sh",
               lidar_bbox=True,
               lidar_note="BBOX cuts dgm1 only; las is packaged as whole city regions.",
               alkis="full", alkis_engine="wfs2", alkis_spatial="exact"),
    "bb": dict(name_short="Brandenburg",
               lidar_dgm1=True, lidar_las=True, lidar_script="download_bb_lidar.sh",
               lidar_bbox=True, lidar_note=None,
               alkis="full", alkis_engine="aria2", alkis_spatial="package"),
    "mv": dict(name_short="Mecklenburg-Vorpommern",
               lidar_dgm1=True, lidar_las=True, lidar_script="download_mv_lidar.sh",
               lidar_bbox=True, lidar_note=None,
               alkis="full", alkis_engine="aria2", alkis_spatial="gemeinde"),
    "sn": dict(name_short="Sachsen",
               lidar_dgm1=True, lidar_las=True, lidar_script="download_sn_lidar.sh",
               lidar_bbox=True, lidar_note=None,
               alkis="full", alkis_engine="aria2", alkis_spatial="package"),
    "st": dict(name_short="Sachsen-Anhalt",
               lidar_dgm1=True, lidar_las=True, lidar_script=None, lidar_bbox=None,
               # download_st_lidar.sh exists but stays lidar_script=None on purpose: it fetches
               # the two published sample areas (~0.1% of the state), and this field feeds a map
               # about bulk access to a whole state. See README, "Sachsen-Anhalt: samples, not a
               # state".
               #
               # ST gets no lidar_offline either, though "auf Antrag" is superficially the same
               # shape as Hessen's disk. Two differences, and either one is disqualifying: it is
               # 190 EUR per Datensatz rather than free, and it is an offer to be applied for
               # rather than an arrangement anyone has confirmed. lidar_offline records routes
               # that were actually walked, not ones a price list implies.
               lidar_note="Statewide 3D-Messdaten is priced and on request; only two sample "
                          "areas are open (download_st_lidar.sh). DGM1 UI caps selection at 5 tiles.",
               # ALKIS-vereinfacht 2.0 over an anonymous WFS 2.0 (ST_LVermGeo_ALKIS_WFS_OpenData):
               # parcels, buildings and Nutzung, no Punktinformationen. Verified 2026-07-29.
               alkis="full", alkis_engine="wfs2", alkis_spatial="exact"),
    "th": dict(name_short="Thueringen",
               lidar_dgm1=True, lidar_las=True, lidar_script="download_th_lidar.sh",
               lidar_bbox=True, lidar_note=None,
               alkis="full", alkis_engine="aria2", alkis_spatial="flur"),
}

ARS_TO_KEY = {"01": "sh", "02": "hh", "03": "ni", "04": "hb", "05": "nw", "06": "he",
              "07": "rp", "08": "bw", "09": "by", "10": "sl", "11": "be", "12": "bb",
              "13": "mv", "14": "sn", "15": "st", "16": "th"}


def status(c):
    """One field a map can colour by, without unpacking the booleans.

    "lidar" means the whole state is obtainable, by script or by the one confirmed offline
    route -- the same test the maps apply.
    """
    lidar = c["lidar_script"] is not None or c.get("lidar_offline") is not None
    alkis = c["alkis"] != "none"
    if lidar and alkis:
        return "lidar+alkis"
    if alkis:
        return "alkis only"
    if lidar:
        return "lidar only"
    return "neither"


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else "bundeslaender.geojson"
    tsv_path = sys.argv[2] if len(sys.argv) > 2 else "sample_squares.tsv"

    squares = {}
    if os.path.exists(tsv_path):
        with open(tsv_path, encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("#") or not line.strip():
                    continue
                key, epsg, bbox, place, why = line.rstrip("\n").split("\t")
                squares[key] = dict(sample_bbox=bbox, sample_epsg=int(epsg), sample_place=place)

    tmp = tempfile.mkdtemp(prefix="vg2500.")
    try:
        zip_path = os.path.join(tmp, "vg2500.zip")
        subprocess.run(["curl", "-fsSL", "-o", zip_path, VG2500], check=True)
        subprocess.run(["unzip", "-o", "-q", zip_path, "-d", tmp], check=True)
        gpkg = next((os.path.join(r, f) for r, _, fs in os.walk(tmp)
                     for f in fs if f.endswith(".gpkg")), None)
        if not gpkg:
            sys.exit("ERROR: no .gpkg inside the VG2500 archive")

        raw = os.path.join(tmp, "lan.geojson")
        # GF=9 is the land body; GF=8 rows are water (Bodensee, coastal) and would duplicate states.
        # 5 decimals is ~1 m. VG2500 is generalised to 1:2,500,000, so its own positional
        # accuracy is hundreds of metres; ogr2ogr's default 7 decimals (~1 cm) would triple
        # the file size to record noise.
        subprocess.run(["ogr2ogr", "-f", "GeoJSON", "-t_srs", "OGC:CRS84",
                        "-where", "GF=9", "-select", "ARS,GEN,NUTS,BEZ",
                        "-lco", "COORDINATE_PRECISION=5",
                        raw, gpkg, "vg2500_lan"], check=True)
        doc = json.load(open(raw, encoding="utf-8"))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if len(doc["features"]) != 16:
        sys.exit(f"ERROR: expected 16 Laender with GF=9, got {len(doc['features'])}")

    features = []
    for f in doc["features"]:
        p = f["properties"]
        key = ARS_TO_KEY.get(p["ARS"])
        if key is None:
            sys.exit(f"ERROR: unmapped ARS {p['ARS']!r} ({p.get('GEN')})")
        c = COVERAGE[key]
        props = {
            "key": key,
            "name": p["GEN"],
            "bez": p["BEZ"],
            "ars": p["ARS"],
            "nuts": p["NUTS"],
            "status": status(c),
            "lidar_dgm1": c["lidar_dgm1"],
            "lidar_las": c["lidar_las"],
            "lidar_script": c["lidar_script"],
            "lidar_offline": c.get("lidar_offline"),
            "lidar_bbox": c["lidar_bbox"],
            "lidar_note": c["lidar_note"],
            "alkis": c["alkis"],
            "alkis_engine": c["alkis_engine"],
            "alkis_spatial": c["alkis_spatial"],
        }
        props.update(squares.get(key, {}))
        features.append({"type": "Feature", "properties": props, "geometry": f["geometry"]})

    features.sort(key=lambda f: f["properties"]["ars"])
    out = {"type": "FeatureCollection", "name": "bundeslaender",
           "bbox": doc.get("bbox"), "features": features}
    if out["bbox"] is None:
        del out["bbox"]
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1)
        fh.write("\n")

    by_status = {}
    for f in features:
        by_status[f["properties"]["status"]] = by_status.get(f["properties"]["status"], 0) + 1
    print(f"{len(features)} Laender -> {out_path}")
    for k in sorted(by_status):
        print(f"  {k}: {by_status[k]}")


if __name__ == "__main__":
    main()
