"""Prepare the two CC0 Poly Haven base-color maps for the Android build."""
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

DEST = Path(__file__).resolve().parents[1] / "client" / "assets" / "surfaces"


def fetch(url):
    request = Request(url, headers={"User-Agent": "DistrictRun-Android-AssetBuild/1.0"})
    with urlopen(request, timeout=45) as response:
        return response.read()


DEST.mkdir(parents=True, exist_ok=True)
for name in ("asphalt_04", "beige_wall_001"):
    metadata = json.loads(fetch(f"https://api.polyhaven.com/files/{name}"))
    maps = metadata.get("diff") or metadata["Diffuse"]
    jpg = maps["1k"]["jpg"]
    data = fetch(jpg["url"])
    if hashlib.md5(data).hexdigest() != jpg["md5"]:
        raise ValueError(f"Download checksum mismatch: {name}")
    (DEST / f"{name}.jpg").write_bytes(data)
