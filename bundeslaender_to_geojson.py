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
#   lidar_las_paid /       : the product cannot be downloaded, but the state will sell it, for
#   lidar_dgm1_paid          the whole state. This COUNTS as obtainable -- the maps ask whether
#                            the data can be had, and an invoice is a way of having it -- so a
#                            paid route colours the same green a script does, and the state is
#                            marked with a EUR sign instead. lidar_las/lidar_dgm1 stay False
#                            where nothing is published: those fields ask what is open, and a
#                            quotation is not, however cheap.
#   lidar_paid_note        : that route -- product, price, terms, who to ask. Shown in the
#                            tooltip, because "green" alone would read as "free download".
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
               lidar_bbox=True,
               # NI is the state that showed why "publishes no point cloud" and "has no point
               # cloud" had to be told apart. LGLN flew the scan the open DGM1 is derived from
               # and sells it as the Laserscan-Punktwolke; it is simply not open data. Both
               # products can be had for the whole state -- one by script, one by invoice --
               # so NI is green, with the EUR sign carrying the difference.
               lidar_las_paid=True,
               lidar_paid_note="LGLN sells the classified ALS Laserscan-Punktwolke "
                               "(3D-Messdaten) under the KOVerm fee schedule: 1 km2 LAZ 1.2 "
                               "tiles, >=4 pts/m2, quote on request, delivered by download or "
                               "on a posted data carrier. Not CC BY like the DGM1 -- it comes "
                               "under the LGLN AGNB. Ask geoService-3D@lgln.niedersachsen.de.",
               lidar_note="STAC catalogue exposes dgm1 only, already COG. The point cloud "
                          "behind it is a priced LGLN product, not open data.",
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
    # The 3DM tiles this repo probed are dead, but they were never the point cloud product.
    # LGL keeps it under Laserscandaten: ALS_2 is the whole state from the 2016-2021 campaign
    # and is Open Data by licence -- what costs money is the handling, not the rights. So BW's
    # gap was never "no point cloud", it was "no endpoint", and under a rule that counts paid
    # routes it is green with a EUR sign, exactly like NI.
    "bw": dict(name_short="Baden-Wuerttemberg",
               lidar_dgm1=True, lidar_las=False, lidar_script="download_bw_lidar.sh",
               lidar_bbox=True,
               lidar_las_paid=True,
               lidar_paid_note="LGL's ALS_2 covers all of Baden-Wuerttemberg from the "
                               "2016-2021 campaign at >=8 pts/m2, in LAZ, LAS or XYZ-ASCII, "
                               "and is licensed Open Data -- but it ships on an email order "
                               "with an effort-based Service-Entgelt, minimum 60 EUR plus VAT. "
                               "ALS_3 (the 2022-2029 recapture) is the same arrangement and "
                               "still in progress; ALS_1 (2000-2005, 0.8 pts/m2) is historic "
                               "and no longer maintained. Ask geodaten@lgl.bwl.de.",
               lidar_note="DGM1 is scripted. The point cloud is not published for download at "
                          "all -- the dead 3DM tiles were a red herring -- but LGL sells the "
                          "statewide ALS_2 for a handling fee.",
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
               # ST gets no lidar_offline: that field is for FREE routes with no endpoint, and
               # Hessen is still the only one. ST's route is a priced one, which is what the
               # two _paid flags are for. Both products are on the price list -- the point
               # cloud as 3D-Messdaten, DGM and DOM derived from it and sold separately -- so
               # ST is obtainable whole, for money, and green with a EUR sign.
               lidar_las_paid=True, lidar_dgm1_paid=True,
               lidar_paid_note="LVermGeo sells the statewide 3D-Messdaten point cloud (LAS 1.2 "
                               "or LAZ, 4-8 pts/m2, reflown on a 6-year cycle) at 190 EUR je "
                               "Datensatz, auf Antrag; DGM and DOM are derived from it and "
                               "sold separately. What is free is two sample areas and a UI "
                               "that caps a DGM1 selection at 5 tiles.",
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

    "lidar" means the whole state is obtainable, by any confirmed route: a script, the one
    free offline route (HE), or a purchase -- the same test the maps apply.
    """
    lidar = (c["lidar_script"] is not None or c.get("lidar_offline") is not None
             or c.get("lidar_las_paid") or c.get("lidar_dgm1_paid"))
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
            "lidar_las_paid": bool(c.get("lidar_las_paid")),
            "lidar_dgm1_paid": bool(c.get("lidar_dgm1_paid")),
            "lidar_paid_note": c.get("lidar_paid_note"),
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
