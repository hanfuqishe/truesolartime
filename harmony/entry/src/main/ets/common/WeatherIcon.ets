/**
 * 天气图标名 → 资源。图标由 Tools/gen-wx-icons.py 从 Android 的 VectorDrawable 转成 SVG，
 * 桌面卡片与主界面共用同一套，避免各写一份资源映射。
 */

export function weatherIcon(name: string): Resource {
  if (name === 'clear_day') {
    return $r('app.media.wx_clear_day');
  }
  if (name === 'clear_night') {
    return $r('app.media.wx_clear_night');
  }
  if (name === 'partly_day') {
    return $r('app.media.wx_partly_day');
  }
  if (name === 'partly_night') {
    return $r('app.media.wx_partly_night');
  }
  if (name === 'overcast') {
    return $r('app.media.wx_overcast');
  }
  if (name === 'fog') {
    return $r('app.media.wx_fog');
  }
  if (name === 'drizzle') {
    return $r('app.media.wx_drizzle');
  }
  if (name === 'rain') {
    return $r('app.media.wx_rain');
  }
  if (name === 'heavy_rain') {
    return $r('app.media.wx_heavy_rain');
  }
  if (name === 'showers') {
    return $r('app.media.wx_showers');
  }
  if (name === 'snow') {
    return $r('app.media.wx_snow');
  }
  if (name === 'heavy_snow') {
    return $r('app.media.wx_heavy_snow');
  }
  if (name === 'thunder') {
    return $r('app.media.wx_thunder');
  }
  return $r('app.media.wx_unknown');
}
