"""Generate harmony/entry/src/main/ets/core/CityIndex.ets from the Android city table.

Keeping a single source of truth is impractical here because the Kotlin file is
compiled by Gradle and the ArkTS file by hvigor, so the table is copied verbatim
by this script. Run it whenever android CityIndex.RAW changes.
"""

import re
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
ANDROID = ROOT / "android/app/src/main/java/com/realsuntime/solartime/data/CityIndex.kt"
TARGET = ROOT / "harmony/entry/src/main/ets/core/CityIndex.ets"

source = ANDROID.read_text(encoding="utf-8")
match = re.search(r'private val RAW = """(.*?)"""\.trimIndent', source, re.S)
if not match:
    raise SystemExit("RAW table not found in CityIndex.kt")
raw = "\n".join(line.strip() for line in match.group(1).strip("\n").splitlines() if line.strip())
rows = [line for line in raw.splitlines() if line]
for row in rows:
    if len(row.split("|")) != 4:
        raise SystemExit(f"bad row: {row}")

body = f"""/**
 * 由经纬度查出所在城市。
 *
 * 内置一张主要城市表（省会与常见地级市、各国主要城市），按球面距离取最近的一个：
 * 无需网络、无需定位权限，桌面卡片每分钟刷新也不会产生请求。
 * 最近城市仍超过 MAX_DISTANCE_KM 时返回 null，避免在荒郊给出误导性的城市名。
 *
 * 城市名只区分中文与英文；繁体环境沿用它（表中的中文名是简体）。
 * 数据由 Tools/gen-city-index.py 从 Android 端同一张表同步而来。
 */

const MAX_DISTANCE_KM: number = 160.0;
const EARTH_RADIUS_KM: number = 6371.0;

export class NearbyCity {{
  name: string;
  distanceKm: number;

  constructor(name: string, distanceKm: number) {{
    this.name = name;
    this.distanceKm = distanceKm;
  }}
}}

class CityEntry {{
  latitude: number;
  longitude: number;
  nameZh: string;
  nameEn: string;

  constructor(latitude: number, longitude: number, nameZh: string, nameEn: string) {{
    this.latitude = latitude;
    this.longitude = longitude;
    this.nameZh = nameZh;
    this.nameEn = nameEn;
  }}
}}

/** 每行格式：中文名|纬度|经度|英文名。 */
const RAW: string = `
{raw}
`;

const ENTRIES: CityEntry[] = RAW.split('\\n')
  .map((line: string): string => line.trim())
  .filter((line: string): boolean => line.length > 0)
  .map((line: string): CityEntry => {{
    const parts: string[] = line.split('|');
    return new CityEntry(Number.parseFloat(parts[1]), Number.parseFloat(parts[2]), parts[0], parts[3]);
  }});

export class CityIndex {{
  /** 球面距离（Haversine），单位公里。 */
  static distanceKm(lat1: number, lon1: number, lat2: number, lon2: number): number {{
    const dLat: number = (lat2 - lat1) * Math.PI / 180.0;
    const dLon: number = (lon2 - lon1) * Math.PI / 180.0;
    const h: number = Math.pow(Math.sin(dLat / 2), 2) +
      Math.cos(lat1 * Math.PI / 180.0) * Math.cos(lat2 * Math.PI / 180.0) * Math.pow(Math.sin(dLon / 2), 2);
    return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(Math.max(0.0, Math.min(1.0, h))));
  }}

  /** 最近的城市；language 以 zh 开头用中文名。超出判定半径时返回 null。 */
  static nearest(latitude: number, longitude: number, language: string): NearbyCity | null {{
    let best: CityEntry | null = null;
    let bestKm: number = Number.MAX_VALUE;
    for (const entry of ENTRIES) {{
      const km: number = CityIndex.distanceKm(latitude, longitude, entry.latitude, entry.longitude);
      if (km < bestKm) {{
        bestKm = km;
        best = entry;
      }}
    }}
    if (best === null || bestKm > MAX_DISTANCE_KM) {{
      return null;
    }}
    const name: string = language.startsWith('zh') ? best.nameZh : best.nameEn;
    return new NearbyCity(name, bestKm);
  }}

  static size(): number {{
    return ENTRIES.length;
  }}
}}
"""

TARGET.write_text(body, encoding="utf-8")
print(f"wrote {TARGET} with {len(rows)} cities")
