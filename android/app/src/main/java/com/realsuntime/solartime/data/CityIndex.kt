package com.realsuntime.solartime.data

import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * 由经纬度查出所在城市。
 *
 * 内置一张主要城市表（省会与常见地级市、各国主要城市），按球面距离取最近的一个：
 * 无需网络、无需定位权限，小组件每分钟刷新也不会产生请求。
 * 最近城市仍超过 [MAX_DISTANCE_KM] 时返回 null，避免在荒郊给出误导性的城市名。
 *
 * 城市名只区分中文与英文；繁体环境沿用它（表中的中文名是简体）。
 */
object CityIndex {

    data class NearbyCity(val name: String, val distanceKm: Double)

    private const val MAX_DISTANCE_KM = 160.0
    private const val EARTH_RADIUS_KM = 6371.0

    private class Entry(
        val latitude: Double,
        val longitude: Double,
        val nameZh: String,
        val nameEn: String,
    )

    /** 每行格式：中文名|纬度|经度|英文名。 */
    private val RAW = """
        北京|39.90|116.41|Beijing
        天津|39.13|117.20|Tianjin
        石家庄|38.04|114.51|Shijiazhuang
        唐山|39.63|118.18|Tangshan
        保定|38.87|115.46|Baoding
        邯郸|36.63|114.54|Handan
        秦皇岛|39.94|119.60|Qinhuangdao
        张家口|40.77|114.89|Zhangjiakou
        承德|40.95|117.96|Chengde
        太原|37.87|112.55|Taiyuan
        大同|40.08|113.30|Datong
        临汾|36.09|111.52|Linfen
        运城|35.03|111.00|Yuncheng
        长治|36.20|113.12|Changzhi
        呼和浩特|40.84|111.75|Hohhot
        包头|40.66|109.84|Baotou
        鄂尔多斯|39.61|109.78|Ordos
        赤峰|42.26|118.89|Chifeng
        海拉尔|49.21|119.77|Hailar
        沈阳|41.80|123.43|Shenyang
        大连|38.91|121.61|Dalian
        鞍山|41.11|123.00|Anshan
        锦州|41.10|121.13|Jinzhou
        丹东|40.00|124.35|Dandong
        长春|43.82|125.32|Changchun
        吉林|43.84|126.55|Jilin
        延吉|42.90|129.51|Yanji
        哈尔滨|45.80|126.54|Harbin
        齐齐哈尔|47.35|123.92|Qiqihar
        大庆|46.59|125.10|Daqing
        牡丹江|44.55|129.63|Mudanjiang
        佳木斯|46.80|130.32|Jiamusi
        上海|31.23|121.47|Shanghai
        南京|32.06|118.80|Nanjing
        苏州|31.30|120.58|Suzhou
        无锡|31.49|120.31|Wuxi
        常州|31.81|119.97|Changzhou
        南通|31.98|120.89|Nantong
        徐州|34.26|117.19|Xuzhou
        扬州|32.39|119.42|Yangzhou
        镇江|32.19|119.42|Zhenjiang
        盐城|33.35|120.16|Yancheng
        淮安|33.61|119.02|Huai'an
        连云港|34.60|119.22|Lianyungang
        杭州|30.27|120.15|Hangzhou
        宁波|29.87|121.55|Ningbo
        温州|27.99|120.70|Wenzhou
        绍兴|30.00|120.58|Shaoxing
        嘉兴|30.75|120.76|Jiaxing
        金华|29.08|119.65|Jinhua
        台州|28.66|121.42|Taizhou
        湖州|30.89|120.09|Huzhou
        合肥|31.82|117.23|Hefei
        芜湖|31.35|118.43|Wuhu
        蚌埠|32.92|117.39|Bengbu
        阜阳|32.89|115.81|Fuyang
        安庆|30.54|117.06|Anqing
        马鞍山|31.67|118.51|Ma'anshan
        福州|26.07|119.30|Fuzhou
        厦门|24.48|118.09|Xiamen
        泉州|24.87|118.68|Quanzhou
        莆田|25.45|119.01|Putian
        南昌|28.68|115.86|Nanchang
        赣州|25.83|114.93|Ganzhou
        九江|29.71|116.00|Jiujiang
        上饶|28.45|117.94|Shangrao
        景德镇|29.27|117.18|Jingdezhen
        济南|36.65|117.12|Jinan
        青岛|36.07|120.38|Qingdao
        烟台|37.46|121.45|Yantai
        威海|37.51|122.12|Weihai
        淄博|36.81|118.05|Zibo
        潍坊|36.71|119.16|Weifang
        临沂|35.05|118.35|Linyi
        泰安|36.20|117.09|Tai'an
        济宁|35.41|116.59|Jining
        菏泽|35.23|115.48|Heze
        聊城|36.46|115.99|Liaocheng
        德州|37.44|116.36|Dezhou
        东营|37.43|118.67|Dongying
        日照|35.42|119.53|Rizhao
        郑州|34.75|113.63|Zhengzhou
        洛阳|34.62|112.45|Luoyang
        开封|34.80|114.31|Kaifeng
        新乡|35.30|113.93|Xinxiang
        武汉|30.59|114.31|Wuhan
        宜昌|30.69|111.29|Yichang
        襄阳|32.01|112.12|Xiangyang
        荆州|30.33|112.24|Jingzhou
        十堰|32.63|110.80|Shiyan
        长沙|28.23|112.94|Changsha
        株洲|27.83|113.13|Zhuzhou
        岳阳|29.36|113.13|Yueyang
        衡阳|26.89|112.57|Hengyang
        常德|29.03|111.70|Changde
        怀化|27.55|109.98|Huaihua
        郴州|25.77|113.01|Chenzhou
        广州|23.13|113.26|Guangzhou
        深圳|22.54|114.06|Shenzhen
        东莞|23.02|113.75|Dongguan
        佛山|23.02|113.12|Foshan
        珠海|22.27|113.58|Zhuhai
        中山|22.52|113.39|Zhongshan
        江门|22.58|113.08|Jiangmen
        惠州|23.11|114.42|Huizhou
        汕头|23.35|116.68|Shantou
        湛江|21.27|110.36|Zhanjiang
        韶关|24.81|113.60|Shaoguan
        肇庆|23.05|112.47|Zhaoqing
        南宁|22.82|108.37|Nanning
        桂林|25.23|110.18|Guilin
        柳州|24.33|109.41|Liuzhou
        北海|21.48|109.12|Beihai
        海口|20.04|110.32|Haikou
        三亚|18.25|109.51|Sanya
        重庆|29.56|106.55|Chongqing
        成都|30.57|104.07|Chengdu
        绵阳|31.47|104.68|Mianyang
        南充|30.84|106.11|Nanchong
        宜宾|28.77|104.64|Yibin
        泸州|28.87|105.44|Luzhou
        攀枝花|26.58|101.72|Panzhihua
        贵阳|26.65|106.63|Guiyang
        遵义|27.73|106.93|Zunyi
        昆明|25.04|102.72|Kunming
        曲靖|25.49|103.80|Qujing
        大理|25.61|100.27|Dali
        丽江|26.86|100.23|Lijiang
        景洪|22.01|100.80|Jinghong
        拉萨|29.65|91.17|Lhasa
        日喀则|29.27|88.88|Shigatse
        西安|34.34|108.94|Xi'an
        宝鸡|34.36|107.24|Baoji
        延安|36.59|109.49|Yan'an
        汉中|33.07|107.02|Hanzhong
        兰州|36.06|103.83|Lanzhou
        天水|34.58|105.72|Tianshui
        西宁|36.62|101.78|Xining
        银川|38.49|106.23|Yinchuan
        乌鲁木齐|43.83|87.62|Urumqi
        克拉玛依|45.58|84.89|Karamay
        伊宁|43.91|81.28|Yining
        库尔勒|41.73|86.17|Korla
        阿克苏|41.17|80.26|Aksu
        喀什|39.47|75.99|Kashgar
        和田|37.11|79.92|Hotan
        石河子|44.31|86.08|Shihezi
        香港|22.32|114.17|Hong Kong
        澳门|22.20|113.54|Macau
        台北|25.03|121.57|Taipei
        台中|24.15|120.67|Taichung
        高雄|22.63|120.30|Kaohsiung
        东京|35.68|139.69|Tokyo
        大阪|34.69|135.50|Osaka
        札幌|43.06|141.35|Sapporo
        首尔|37.57|126.98|Seoul
        釜山|35.18|129.08|Busan
        平壤|39.03|125.75|Pyongyang
        新加坡|1.35|103.82|Singapore
        曼谷|13.76|100.50|Bangkok
        吉隆坡|3.14|101.69|Kuala Lumpur
        雅加达|-6.21|106.85|Jakarta
        马尼拉|14.60|120.98|Manila
        河内|21.03|105.85|Hanoi
        胡志明市|10.82|106.63|Ho Chi Minh City
        金边|11.56|104.92|Phnom Penh
        万象|17.97|102.63|Vientiane
        仰光|16.87|96.20|Yangon
        达卡|23.81|90.41|Dhaka
        新德里|28.61|77.21|New Delhi
        孟买|19.08|72.88|Mumbai
        班加罗尔|12.97|77.59|Bengaluru
        加德满都|27.72|85.32|Kathmandu
        科伦坡|6.93|79.85|Colombo
        伊斯兰堡|33.69|73.06|Islamabad
        卡拉奇|24.86|67.01|Karachi
        迪拜|25.20|55.27|Dubai
        多哈|25.29|51.53|Doha
        利雅得|24.71|46.68|Riyadh
        德黑兰|35.69|51.39|Tehran
        伊斯坦布尔|41.01|28.98|Istanbul
        莫斯科|55.76|37.62|Moscow
        圣彼得堡|59.93|30.36|St. Petersburg
        新西伯利亚|55.01|82.93|Novosibirsk
        伊尔库茨克|52.29|104.28|Irkutsk
        符拉迪沃斯托克|43.12|131.89|Vladivostok
        阿拉木图|43.24|76.89|Almaty
        塔什干|41.30|69.24|Tashkent
        乌兰巴托|47.89|106.91|Ulaanbaatar
        悉尼|-33.87|151.21|Sydney
        墨尔本|-37.81|144.96|Melbourne
        布里斯班|-27.47|153.03|Brisbane
        珀斯|-31.95|115.86|Perth
        奥克兰|-36.85|174.76|Auckland
        惠灵顿|-41.29|174.78|Wellington
        伦敦|51.51|-0.13|London
        巴黎|48.86|2.35|Paris
        柏林|52.52|13.40|Berlin
        慕尼黑|48.14|11.58|Munich
        法兰克福|50.11|8.68|Frankfurt
        罗马|41.90|12.50|Rome
        米兰|45.46|9.19|Milan
        马德里|40.42|-3.70|Madrid
        巴塞罗那|41.39|2.17|Barcelona
        里斯本|38.72|-9.14|Lisbon
        阿姆斯特丹|52.37|4.90|Amsterdam
        布鲁塞尔|50.85|4.35|Brussels
        苏黎世|47.38|8.54|Zurich
        维也纳|48.21|16.37|Vienna
        布拉格|50.08|14.44|Prague
        华沙|52.23|21.01|Warsaw
        斯德哥尔摩|59.33|18.07|Stockholm
        奥斯陆|59.91|10.75|Oslo
        哥本哈根|55.68|12.57|Copenhagen
        赫尔辛基|60.17|24.94|Helsinki
        都柏林|53.35|-6.26|Dublin
        雅典|37.98|23.73|Athens
        基辅|50.45|30.52|Kyiv
        布达佩斯|47.50|19.04|Budapest
        布加勒斯特|44.43|26.10|Bucharest
        纽约|40.71|-74.01|New York
        洛杉矶|34.05|-118.24|Los Angeles
        旧金山|37.77|-122.42|San Francisco
        西雅图|47.61|-122.33|Seattle
        芝加哥|41.88|-87.63|Chicago
        波士顿|42.36|-71.06|Boston
        华盛顿|38.91|-77.04|Washington, D.C.
        迈阿密|25.76|-80.19|Miami
        达拉斯|32.78|-96.80|Dallas
        休斯敦|29.76|-95.37|Houston
        丹佛|39.74|-104.99|Denver
        凤凰城|33.45|-112.07|Phoenix
        拉斯维加斯|36.17|-115.14|Las Vegas
        檀香山|21.31|-157.86|Honolulu
        温哥华|49.28|-123.12|Vancouver
        多伦多|43.65|-79.38|Toronto
        蒙特利尔|45.50|-73.57|Montreal
        墨西哥城|19.43|-99.13|Mexico City
        圣保罗|-23.55|-46.63|Sao Paulo
        里约热内卢|-22.91|-43.17|Rio de Janeiro
        布宜诺斯艾利斯|-34.60|-58.38|Buenos Aires
        圣地亚哥|-33.45|-70.67|Santiago
        利马|-12.05|-77.04|Lima
        波哥大|4.71|-74.07|Bogota
        开罗|30.04|31.24|Cairo
        开普敦|-33.92|18.42|Cape Town
        约翰内斯堡|-26.20|28.05|Johannesburg
        内罗毕|-1.29|36.82|Nairobi
        拉各斯|6.52|3.38|Lagos
        卡萨布兰卡|33.57|-7.59|Casablanca
    """.trimIndent()

    private val entries: List<Entry> by lazy {
        RAW.lines().filter { it.isNotBlank() }.map { line ->
            val parts = line.split('|')
            Entry(parts[1].toDouble(), parts[2].toDouble(), parts[0], parts[3])
        }
    }

    /** 最近的城市；[language] 为系统语言（"zh" 开头用中文名）。超出判定半径时返回 null。 */
    fun nearest(latitude: Double, longitude: Double, language: String): NearbyCity? {
        var best: Entry? = null
        var bestKm = Double.MAX_VALUE
        for (entry in entries) {
            val km = distanceKm(latitude, longitude, entry.latitude, entry.longitude)
            if (km < bestKm) {
                bestKm = km
                best = entry
            }
        }
        val found = best ?: return null
        if (bestKm > MAX_DISTANCE_KM) return null
        val name = if (language.startsWith("zh")) found.nameZh else found.nameEn
        return NearbyCity(name, bestKm)
    }

    /** 球面距离（Haversine）。 */
    internal fun distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val h = sin(dLat / 2).pow(2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2).pow(2)
        return 2 * EARTH_RADIUS_KM * asin(sqrt(h.coerceIn(0.0, 1.0)))
    }
}
