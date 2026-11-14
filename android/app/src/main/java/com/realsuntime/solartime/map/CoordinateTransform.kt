package com.realsuntime.solartime.map

/**
 * WGS-84 与 GCJ-02（火星坐标）互转。
 *
 * 高德等国内底图使用 GCJ-02，而 GPS 与真太阳时计算必须使用 WGS-84，
 * 因此只在绘制地图这一层做转换，数据层始终保持 WGS-84。
 */
object CoordinateTransform {

    private const val PI = Math.PI
    private const val AXIS = 6378245.0
    private const val ECCENTRICITY = 0.00669342162296594323

    /**
     * GCJ-02 的适用边界，境外不加偏移。
     *
     * 注意这**不是**时区口径：判断「该用哪个标准时区」请用
     * `SolarTimeMath.isInChinaBbox`（经度 73–135、纬度 18–54），两条边界本来就不同。
     */
    fun isInChina(latitude: Double, longitude: Double): Boolean =
        longitude >= 72.004 && longitude <= 137.8347 && latitude >= 0.8293 && latitude <= 55.8271

    fun wgs84ToGcj02(latitude: Double, longitude: Double): Pair<Double, Double> {
        if (!isInChina(latitude, longitude)) return latitude to longitude

        var deltaLat = transformLatitude(longitude - 105.0, latitude - 35.0)
        var deltaLon = transformLongitude(longitude - 105.0, latitude - 35.0)

        val radLat = latitude / 180.0 * PI
        val sinLat = kotlin.math.sin(radLat)
        val magic = 1 - ECCENTRICITY * sinLat * sinLat
        val sqrtMagic = kotlin.math.sqrt(magic)
        deltaLat = deltaLat * 180.0 / (AXIS * (1 - ECCENTRICITY) / (magic * sqrtMagic) * PI)
        deltaLon = deltaLon * 180.0 / (AXIS / sqrtMagic * kotlin.math.cos(radLat) * PI)

        return latitude + deltaLat to longitude + deltaLon
    }

    /** 迭代逼近求逆，往返误差可忽略。 */
    fun gcj02ToWgs84(latitude: Double, longitude: Double): Pair<Double, Double> {
        if (!isInChina(latitude, longitude)) return latitude to longitude

        var guessLat = latitude
        var guessLon = longitude
        repeat(6) {
            val (gcjLat, gcjLon) = wgs84ToGcj02(guessLat, guessLon)
            guessLat += latitude - gcjLat
            guessLon += longitude - gcjLon
        }
        return guessLat to guessLon
    }

    private fun transformLatitude(x: Double, y: Double): Double {
        var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * kotlin.math.sqrt(kotlin.math.abs(x))
        result += (20.0 * kotlin.math.sin(6.0 * x * PI) + 20.0 * kotlin.math.sin(2.0 * x * PI)) * 2.0 / 3.0
        result += (20.0 * kotlin.math.sin(y * PI) + 40.0 * kotlin.math.sin(y / 3.0 * PI)) * 2.0 / 3.0
        result += (160.0 * kotlin.math.sin(y / 12.0 * PI) + 320.0 * kotlin.math.sin(y * PI / 30.0)) * 2.0 / 3.0
        return result
    }

    private fun transformLongitude(x: Double, y: Double): Double {
        var result = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * kotlin.math.sqrt(kotlin.math.abs(x))
        result += (20.0 * kotlin.math.sin(6.0 * x * PI) + 20.0 * kotlin.math.sin(2.0 * x * PI)) * 2.0 / 3.0
        result += (20.0 * kotlin.math.sin(x * PI) + 40.0 * kotlin.math.sin(x / 3.0 * PI)) * 2.0 / 3.0
        result += (150.0 * kotlin.math.sin(x / 12.0 * PI) + 300.0 * kotlin.math.sin(x / 30.0 * PI)) * 2.0 / 3.0
        return result
    }
}
