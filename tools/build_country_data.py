#!/usr/bin/env python3
"""
Build a lightweight country border JSON for MapCam bundle.
Reads Natural Earth GeoJSON and outputs countries.min.json with:
  - iso, name, bbox, polys (outer rings only, 2-decimal precision, deduped)
"""

import json
import os
import sys

INPUT_PATH = "/tmp/ne_50m_admin_0_countries.geojson"
FALLBACK_PATH = "/tmp/ne_110m_admin_0_countries.geojson"
OUTPUT_DIR = "/Users/harasakidaisaku/mapcam/MapCam/Resources"
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "countries.min.json")


def round2(coord):
    return [round(coord[0], 2), round(coord[1], 2)]


def dedup_ring(ring):
    """Remove consecutive duplicate points from a ring."""
    if not ring:
        return ring
    result = [ring[0]]
    for pt in ring[1:]:
        if pt != result[-1]:
            result.append(pt)
    return result


def process_ring(raw_ring):
    """Round coordinates, dedup, and validate minimum point count."""
    rounded = [round2(c) for c in raw_ring]
    deduped = dedup_ring(rounded)
    # Need at least 4 points (closed ring: first == last counts as 3 unique + close)
    if len(deduped) < 4:
        return None
    return deduped


def extract_polys(geometry):
    """Extract outer rings from Polygon or MultiPolygon geometry."""
    polys = []
    gtype = geometry["type"]
    coords = geometry["coordinates"]

    if gtype == "Polygon":
        # coords = [outer_ring, hole1, hole2, ...]
        outer = process_ring(coords[0])
        if outer is not None:
            polys.append(outer)
    elif gtype == "MultiPolygon":
        # coords = [[[outer, hole,...], ...], ...]
        for polygon in coords:
            outer = process_ring(polygon[0])
            if outer is not None:
                polys.append(outer)

    return polys


def compute_bbox(polys):
    """Compute [minLon, minLat, maxLon, maxLat] from all polys."""
    min_lon = min_lat = float("inf")
    max_lon = max_lat = float("-inf")
    for ring in polys:
        for lon, lat in ring:
            if lon < min_lon:
                min_lon = lon
            if lon > max_lon:
                max_lon = lon
            if lat < min_lat:
                min_lat = lat
            if lat > max_lat:
                max_lat = lat
    return [min_lon, min_lat, max_lon, max_lat]


def main():
    # Determine input file
    if os.path.exists(INPUT_PATH):
        input_path = INPUT_PATH
        print(f"Using 50m dataset: {input_path}")
    elif os.path.exists(FALLBACK_PATH):
        input_path = FALLBACK_PATH
        print(f"50m not found, using 110m fallback: {input_path}")
    else:
        print(f"ERROR: Neither {INPUT_PATH} nor {FALLBACK_PATH} found.", file=sys.stderr)
        sys.exit(1)

    with open(input_path, "r", encoding="utf-8") as f:
        geojson = json.load(f)

    features = geojson.get("features", [])
    print(f"Input features: {len(features)}")

    countries = []
    skipped = 0

    for feat in features:
        props = feat.get("properties", {})
        geometry = feat.get("geometry")

        if geometry is None:
            skipped += 1
            continue

        # ISO code: prefer ISO_A3, fall back to ADM0_A3 if "-99"
        iso = props.get("ISO_A3", "-99")
        if iso == "-99":
            iso = props.get("ADM0_A3", "-99")

        name = props.get("NAME", "")

        gtype = geometry.get("type", "")
        if gtype not in ("Polygon", "MultiPolygon"):
            skipped += 1
            continue

        polys = extract_polys(geometry)
        if not polys:
            skipped += 1
            continue

        bbox = compute_bbox(polys)

        countries.append({
            "iso": iso,
            "name": name,
            "bbox": bbox,
            "polys": polys,
        })

    print(f"Countries processed: {len(countries)}, skipped: {skipped}")

    output = {"countries": countries}

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(output, f, separators=(",", ":"), ensure_ascii=False)

    size = os.path.getsize(OUTPUT_PATH)
    print(f"Written: {OUTPUT_PATH} ({size:,} bytes)")


if __name__ == "__main__":
    main()
