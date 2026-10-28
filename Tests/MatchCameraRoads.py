"""Offline association using official HK1980 coordinates and route identifiers."""
import json
import math
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path


def objects(path):
    for _, element in ET.iterparse(path, events=("end",)):
        if element.tag.endswith("}GenericCityObject"):
            fields = {}
            points = []
            for node in element:
                if "name" in node.attrib:
                    fields[node.attrib["name"]] = "".join(node.itertext()).strip()
            for node in element.iter():
                if node.tag.endswith("}posList"):
                    values = list(map(float, node.text.split()))
                    points = list(zip(values[::2], values[1::2]))
            yield fields, points
            element.clear()


def project(point, line):
    best = (float("inf"), 0.0)
    travelled = 0.0
    for a, b in zip(line, line[1:]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        t = min(1, max(0, ((point[0]-a[0])*dx + (point[1]-a[1])*dy) / length**2)) if length else 0
        distance = math.hypot(point[0]-a[0]-t*dx, point[1]-a[1]-t*dy)
        if distance < best[0]:
            best = (distance, travelled + t*length)
        travelled += length
    return best


def normalize(text):
    return re.sub(r"[^A-Z0-9]", "", text.upper())


def road_name_matches(camera, fields):
    for key in ("STREET_ENAME", "ALIAS_ENAME"):
        name = fields.get(key, "")
        if len(name) > 3 and normalize(camera["english"]).startswith(normalize(name)):
            return True
    for key in ("STREET_CNAME", "ALIAS_CNAME"):
        name = fields.get(key, "")
        if len(name) > 1 and camera["name"].startswith(name):
            return True
    return False


def applicable_limits(point, road, limits):
    _, chainage = project(point, road)
    matches = []
    for fields, geometry in limits:
        if fields.get("REMARKS", "").strip() or len(geometry) < 2:
            continue
        speed = re.fullmatch(r"(\d+) km/h", fields.get("SPEED_LIMIT", ""))
        if not speed or not 10 <= int(speed[1]) <= 110:
            continue
        # A shared route ID is insufficient: the camera must be within this
        # particular restriction's extent along that route, not its next section.
        positions = [project(p, road)[1] for p in geometry]
        if min(positions)-5 <= chainage <= max(positions)+5 and project(point, geometry)[0] <= 60:
            matches.append((int(speed[1]), fields["SPEED_LIMIT_ID"]))
    return matches


def main():
    path = Path(__file__).resolve().parents[1] / "GorillaTranslate/Resources/traffic_cameras.json"
    catalog = json.loads(path.read_text())
    cameras = catalog["cameras"]
    positions = {}
    for kind in ("sec", "rlc"):
        xml = subprocess.check_output(["unzip", "-p", f"/private/tmp/hk-{kind}.kmz"])
        for marker in ET.fromstring(xml).iter("{http://www.opengis.net/kml/2.2}Placemark"):
            data = {e.attrib["name"]: e.text for e in marker.iter("{http://www.opengis.net/kml/2.2}SimpleData")}
            positions[f"{kind}-{data[kind.upper()+'_ID']}"] = (float(data["X_COOR"]), float(data["Y_COOR"]))
    limits = {}
    for fields, points in objects("/private/tmp/hk-speed-limit.gml"):
        limits.setdefault(fields["ROAD_ROUTE_ID"], []).append((fields, points))
    roads = {c["id"]: [] for c in cameras}
    for fields, points in objects("/private/tmp/hk-centerline.gml"):
        if len(points) < 2:
            continue
        xs, ys = zip(*points)
        left, right, bottom, top = min(xs)-45, max(xs)+45, min(ys)-45, max(ys)+45
        for camera in cameras:
            x, y = positions[camera["id"]]
            if not left <= x <= right or not bottom <= y <= top:
                continue
            if road_name_matches(camera, fields):
                distance = project((x, y), points)[0]
                if distance <= 45:
                    roads[camera["id"]].append((distance, fields, points))
    for camera in cameras:
        for key in ("roadSpeedLimitKmh", "roadSpeedMatchDistance", "roadRouteID", "roadSpeedLimitID", "matchedRoadName"):
            camera.pop(key, None)
        candidates = sorted(roads[camera["id"]], key=lambda r: r[0])
        matches = []
        unresolved = False
        for distance, road, geometry in candidates:
            if distance > candidates[0][0] + 8:
                continue
            applicable = applicable_limits(positions[camera["id"]], geometry, limits.get(road["ROUTE_ID"], []))
            if not applicable:
                unresolved = True
            matches.extend((speed, identifier, distance, road) for speed, identifier in applicable)
        if not unresolved and matches and len({m[0] for m in matches}) == 1:
            speed, identifier, distance, road = min(matches, key=lambda m: m[2])
            camera.update(roadSpeedLimitKmh=speed, roadSpeedMatchDistance=round(distance, 2),
                          roadRouteID=road["ROUTE_ID"], roadSpeedLimitID=identifier,
                          matchedRoadName=road.get("STREET_CNAME", ""))
    catalog["speedLimitSource"] = "https://static.data.gov.hk/td/road-network-v2/SPEED_LIMIT.gml"
    catalog["roadSource"] = "https://static.data.gov.hk/td/road-network-v2/CENTERLINE.gml"
    catalog["speedLimitAssociation"] = "Matching street name, HK1980 road centerline within 45 m, shared ROUTE_ID, restriction chainage extent; conflicts excluded. Road reference, not enforcement setting."
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    print(f"Road-associated references: {sum('roadSpeedLimitKmh' in c for c in cameras)}/{len(cameras)}", flush=True)


if __name__ == "__main__":
    main()
