# Download the full native-land.ca territories dataset and convert to a
# feature class, for local intersections against ecoregions and Priority
# Landscapes (#28). Languages are out of scope -- confirmed only
# territories are needed. Name is the Nation's display name; description
# holds its native-land.ca page URL, used as the hyperlink in report cards.
#
# One GET for the full dataset, not per-landscape queries -- their docs ask
# callers to avoid repeated calls where a single bulk pull works. The
# response is a GeoJSON FeatureCollection, saved to disk, then converted
# with JSONToFeatures.
#
# API key: read from <output_dir>/native_land_api_key.txt (plain text, one
# line) -- lives outside the repo like all data_prep output, so it's never
# committed. Sign up for a key at native-land.ca.
#
# Source CRS is WGS84 (GeoJSON's default, per spec) -- reprojected to this
# project's standard Albers before saving, like every other source in this
# pipeline.

import arcpy
import json
import os
import time
import requests

arcpy.env.overwriteOutput = True
start_time = time.time()

output_dir = r"C:\Users\marc.edwards\Documents\PROJECTS\ERAPs_v2\data_prep"

reference_layer = os.path.join(output_dir, "ecoregions.gdb", "ecoregions_ctef_v2_2_terrestrial")
target_sr = arcpy.Describe(reference_layer).spatialReference

API_URL = "https://native-land.ca/api/polygons/geojson/territories"

api_key_path = os.path.join(output_dir, "native_land_api_key.txt")
with open(api_key_path, "r") as f:
    api_key = f.read().strip()

scratch_dir = os.path.join(output_dir, "scratch")
if not os.path.exists(scratch_dir):
    os.makedirs(scratch_dir)

out_gdb = os.path.join(output_dir, "indigenous_territories.gdb")
if not arcpy.Exists(out_gdb):
    arcpy.management.CreateFileGDB(output_dir, "indigenous_territories.gdb")

print("downloading territories...")
resp = requests.get(API_URL, params={"key": api_key}, timeout=120)
resp.raise_for_status()
payload = resp.json()

geojson_path = os.path.join(scratch_dir, "native_land_territories.geojson")
with open(geojson_path, "w", encoding="utf-8") as f:
    json.dump(payload, f)
print(f"  {len(payload.get('features', []))} features -> {geojson_path}")

wgs84_fc = os.path.join(out_gdb, "territories_wgs84")
arcpy.conversion.JSONToFeatures(geojson_path, wgs84_fc)
if arcpy.Describe(wgs84_fc).spatialReference.name == "Unknown":
    arcpy.management.DefineProjection(wgs84_fc, arcpy.SpatialReference(4326))

out_fc = os.path.join(out_gdb, "territories")
arcpy.management.Project(wgs84_fc, out_fc, target_sr)
arcpy.management.Delete(wgs84_fc)

count = int(arcpy.management.GetCount(out_fc)[0])
curved = 0
with arcpy.da.SearchCursor(out_fc, ["SHAPE@"]) as cursor:
    for (shape,) in cursor:
        if shape is not None and shape.hasCurves:
            curved += 1
print(f"wrote {out_fc}: {count} features, {curved} curved, CRS={arcpy.Describe(out_fc).spatialReference.name}")

print("\ntotal elapsed:", round(time.time() - start_time, 1), "sec")
