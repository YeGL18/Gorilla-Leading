import Foundation
import MapKit

/// 香港的士牌地方試題地點 — 道路
struct HKTaxiExamLocations {
    struct Location {
        let name: String
        let coordinate: CLLocationCoordinate2D
        let category: Category

        enum Category: String, CaseIterable {
            case road = "道路"
            case hospital = "醫院"
            case government = "政府機構"
            case hotel = "酒店"
            case landmark = "地標"
            case transport = "交通設施"
            case education = "教育"
            case shopping = "購物"
            case religious = "宗教"
            case park = "公園"
        }
    }

    // MARK: - 道路

    static let roads: [Location] = [
        // 港島主要道路
        Location(name: "莊士敦道", coordinate: .init(latitude: 22.2785, longitude: 114.1715), category: .road),
        Location(name: "德輔道中", coordinate: .init(latitude: 22.2810, longitude: 114.1580), category: .road),
        Location(name: "德輔道西", coordinate: .init(latitude: 22.2870, longitude: 114.1480), category: .road),
        Location(name: "皇后大道中", coordinate: .init(latitude: 22.2865, longitude: 114.1550), category: .road),
        Location(name: "皇后大道東", coordinate: .init(latitude: 22.2755, longitude: 114.1710), category: .road),
        Location(name: "皇后大道西", coordinate: .init(latitude: 22.2880, longitude: 114.1440), category: .road),
        Location(name: "軒尼詩道", coordinate: .init(latitude: 22.2780, longitude: 114.1700), category: .road),
        Location(name: "告士打道", coordinate: .init(latitude: 22.2790, longitude: 114.1790), category: .road),
        Location(name: "干諾道中", coordinate: .init(latitude: 22.2830, longitude: 114.1590), category: .road),
        Location(name: "干諾道西", coordinate: .init(latitude: 22.2880, longitude: 114.1500), category: .road),
        Location(name: "堅尼地城", coordinate: .init(latitude: 22.2860, longitude: 114.1290), category: .road),
        Location(name: "薄扶林道", coordinate: .init(latitude: 22.2720, longitude: 114.1340), category: .road),
        Location(name: "香港仔大道", coordinate: .init(latitude: 22.2480, longitude: 114.1550), category: .road),
        Location(name: "黃竹坑道", coordinate: .init(latitude: 22.2470, longitude: 114.1680), category: .road),
        Location(name: "石排灣道", coordinate: .init(latitude: 22.2490, longitude: 114.1510), category: .road),
        Location(name: "銅鑼灣道", coordinate: .init(latitude: 22.2800, longitude: 114.1850), category: .road),
        Location(name: "英皇道", coordinate: .init(latitude: 22.2870, longitude: 114.1950), category: .road),
        Location(name: "筲箕灣道", coordinate: .init(latitude: 22.2790, longitude: 114.2160), category: .road),
        Location(name: "柴灣道", coordinate: .init(latitude: 22.2640, longitude: 114.2380), category: .road),
        Location(name: "東區走廊", coordinate: .init(latitude: 22.2850, longitude: 114.2080), category: .road),
        Location(name: "摩理臣山道", coordinate: .init(latitude: 22.2720, longitude: 114.1800), category: .road),
        Location(name: "禮頓道", coordinate: .init(latitude: 22.2770, longitude: 114.1810), category: .road),
        Location(name: "大坑道", coordinate: .init(latitude: 22.2770, longitude: 114.1890), category: .road),
        Location(name: "司徒拔道", coordinate: .init(latitude: 22.2680, longitude: 114.1810), category: .road),
        Location(name: "黃泥涌道", coordinate: .init(latitude: 22.2700, longitude: 114.1840), category: .road),
        Location(name: "跑馬地馬場", coordinate: .init(latitude: 22.2710, longitude: 114.1830), category: .road),
        Location(name: "赤柱大街", coordinate: .init(latitude: 22.2190, longitude: 114.2130), category: .road),
        Location(name: "淺水灣道", coordinate: .init(latitude: 22.2380, longitude: 114.1930), category: .road),
        Location(name: "深水灣道", coordinate: .init(latitude: 22.2440, longitude: 114.1890), category: .road),

        // 九龍主要道路
        Location(name: "彌敦道", coordinate: .init(latitude: 22.3100, longitude: 114.1700), category: .road),
        Location(name: "馬頭圍道", coordinate: .init(latitude: 22.3170, longitude: 114.1820), category: .road),
        Location(name: "漆咸道南", coordinate: .init(latitude: 22.2980, longitude: 114.1730), category: .road),
        Location(name: "漆咸道北", coordinate: .init(latitude: 22.3060, longitude: 114.1780), category: .road),
        Location(name: "佐敦道", coordinate: .init(latitude: 22.3060, longitude: 114.1710), category: .road),
        Location(name: "柯士甸道", coordinate: .init(latitude: 22.3020, longitude: 114.1700), category: .road),
        Location(name: "加士居道", coordinate: .init(latitude: 22.3050, longitude: 114.1720), category: .road),
        Location(name: "窩打老道", coordinate: .init(latitude: 22.3130, longitude: 114.1720), category: .road),
        Location(name: "亞皆老街", coordinate: .init(latitude: 22.3180, longitude: 114.1730), category: .road),
        Location(name: "太子道西", coordinate: .init(latitude: 22.3230, longitude: 114.1690), category: .road),
        Location(name: "太子道東", coordinate: .init(latitude: 22.3230, longitude: 114.1830), category: .road),
        Location(name: "界限街", coordinate: .init(latitude: 22.3270, longitude: 114.1690), category: .road),
        Location(name: "大角咀道", coordinate: .init(latitude: 22.3230, longitude: 114.1610), category: .road),
        Location(name: "長沙灣道", coordinate: .init(latitude: 22.3350, longitude: 114.1550), category: .road),
        Location(name: "青山道", coordinate: .init(latitude: 22.3340, longitude: 114.1600), category: .road),
        Location(name: "荔枝角道", coordinate: .init(latitude: 22.3320, longitude: 114.1520), category: .road),
        Location(name: "南昌街", coordinate: .init(latitude: 22.3320, longitude: 114.1620), category: .road),
        Location(name: "大埔道", coordinate: .init(latitude: 22.3300, longitude: 114.1630), category: .road),
        Location(name: "石硤尾街", coordinate: .init(latitude: 22.3330, longitude: 114.1670), category: .road),
        Location(name: "新蒲崗", coordinate: .init(latitude: 22.3340, longitude: 114.1940), category: .road),
        Location(name: "彩虹道", coordinate: .init(latitude: 22.3340, longitude: 114.1980), category: .road),
        Location(name: "觀塘道", coordinate: .init(latitude: 22.3120, longitude: 114.2260), category: .road),
        Location(name: "牛頭角道", coordinate: .init(latitude: 22.3190, longitude: 114.2210), category: .road),
        Location(name: "偉業街", coordinate: .init(latitude: 22.3130, longitude: 114.2150), category: .road),
        Location(name: "啟祥道", coordinate: .init(latitude: 22.3120, longitude: 114.2100), category: .road),
        Location(name: "清水灣道", coordinate: .init(latitude: 22.3290, longitude: 114.2140), category: .road),
        Location(name: "龍翔道", coordinate: .init(latitude: 22.3400, longitude: 114.1800), category: .road),
        Location(name: "呈祥道", coordinate: .init(latitude: 22.3420, longitude: 114.1660), category: .road),
        Location(name: "紅磡道", coordinate: .init(latitude: 22.3050, longitude: 114.1850), category: .road),
        Location(name: "暢通道", coordinate: .init(latitude: 22.3180, longitude: 114.1690), category: .road),
        Location(name: "公主道", coordinate: .init(latitude: 22.3130, longitude: 114.1760), category: .road),

        // 新界主要道路
        Location(name: "清松觀道", coordinate: .init(latitude: 22.3960, longitude: 114.0070), category: .road),
        Location(name: "青山公路", coordinate: .init(latitude: 22.3800, longitude: 114.0300), category: .road),
        Location(name: "屯門公路", coordinate: .init(latitude: 22.3800, longitude: 114.0200), category: .road),
        Location(name: "元朗大馬路", coordinate: .init(latitude: 22.4450, longitude: 114.0350), category: .road),
        Location(name: "大埔公路", coordinate: .init(latitude: 22.3700, longitude: 114.1300), category: .road),
        Location(name: "沙田正街", coordinate: .init(latitude: 22.3810, longitude: 114.1880), category: .road),
        Location(name: "獅子山隧道公路", coordinate: .init(latitude: 22.3500, longitude: 114.1800), category: .road),
        Location(name: "大老山隧道", coordinate: .init(latitude: 22.3510, longitude: 114.2100), category: .road),
        Location(name: "城門隧道", coordinate: .init(latitude: 22.3730, longitude: 114.1480), category: .road),
        Location(name: "青馬大橋", coordinate: .init(latitude: 22.3520, longitude: 114.0740), category: .road),
        Location(name: "汀九橋", coordinate: .init(latitude: 22.3640, longitude: 114.0640), category: .road),
        Location(name: "西隧", coordinate: .init(latitude: 22.2920, longitude: 114.1430), category: .road),
        Location(name: "紅隧", coordinate: .init(latitude: 22.3020, longitude: 114.1800), category: .road),
        Location(name: "東隧", coordinate: .init(latitude: 22.2830, longitude: 114.2020), category: .road),

        // 尖沙咀
        Location(name: "彌敦道（尖沙咀段）", coordinate: .init(latitude: 22.2980, longitude: 114.1720), category: .road),
        Location(name: "廣東道", coordinate: .init(latitude: 22.2980, longitude: 114.1690), category: .road),
        Location(name: "梳士巴利道", coordinate: .init(latitude: 22.2940, longitude: 114.1720), category: .road),
        Location(name: "麼地道", coordinate: .init(latitude: 22.2960, longitude: 114.1760), category: .road),
        Location(name: "金馬倫道", coordinate: .init(latitude: 22.2990, longitude: 114.1730), category: .road),
        Location(name: "加拿分道", coordinate: .init(latitude: 22.3000, longitude: 114.1740), category: .road),
        Location(name: "碧仙桃路", coordinate: .init(latitude: 22.3000, longitude: 114.1720), category: .road),
    ]

    // MARK: - 醫院

    static let hospitals: [Location] = [
        // 港島
        Location(name: "瑪麗醫院", coordinate: .init(latitude: 22.2700, longitude: 114.1310), category: .hospital),
        Location(name: "東區醫院", coordinate: .init(latitude: 22.2640, longitude: 114.2280), category: .hospital),
        Location(name: "律敦治醫院", coordinate: .init(latitude: 22.2800, longitude: 114.1770), category: .hospital),
        Location(name: "鄧肇堅醫院", coordinate: .init(latitude: 22.2810, longitude: 114.1750), category: .hospital),
        Location(name: "養和醫院", coordinate: .init(latitude: 22.2700, longitude: 114.1830), category: .hospital),
        Location(name: "港怡醫院", coordinate: .init(latitude: 22.2680, longitude: 114.1880), category: .hospital),
        Location(name: "聖保祿醫院", coordinate: .init(latitude: 22.2810, longitude: 114.1830), category: .hospital),
        Location(name: "嘉諾撒醫院", coordinate: .init(latitude: 22.2820, longitude: 114.1820), category: .hospital),
        Location(name: "明愛醫院", coordinate: .init(latitude: 22.2740, longitude: 114.1490), category: .hospital),

        // 九龍
        Location(name: "伊利沙伯醫院", coordinate: .init(latitude: 22.3090, longitude: 114.1710), category: .hospital),
        Location(name: "廣華醫院", coordinate: .init(latitude: 22.3140, longitude: 114.1700), category: .hospital),
        Location(name: "東華醫院", coordinate: .init(latitude: 22.2830, longitude: 114.1500), category: .hospital),
        Location(name: "瑪嘉烈醫院", coordinate: .init(latitude: 22.3400, longitude: 114.1300), category: .hospital),
        Location(name: "仁濟醫院", coordinate: .init(latitude: 22.3700, longitude: 114.1200), category: .hospital),
        Location(name: "基督教聯合醫院", coordinate: .init(latitude: 22.3180, longitude: 114.2280), category: .hospital),
        Location(name: "聖德肋撒醫院", coordinate: .init(latitude: 22.3180, longitude: 114.1830), category: .hospital),
        Location(name: "播道醫院", coordinate: .init(latitude: 22.3200, longitude: 114.1820), category: .hospital),
        Location(name: "浸信會醫院", coordinate: .init(latitude: 22.3220, longitude: 114.1770), category: .hospital),
        Location(name: "寶血醫院", coordinate: .init(latitude: 22.3280, longitude: 114.1710), category: .hospital),
        Location(name: "明德醫院", coordinate: .init(latitude: 22.3270, longitude: 114.1590), category: .hospital),

        // 新界
        Location(name: "威爾斯親王醫院", coordinate: .init(latitude: 22.3810, longitude: 114.1950), category: .hospital),
        Location(name: "屯門醫院", coordinate: .init(latitude: 22.3930, longitude: 114.0040), category: .hospital),
        Location(name: "博愛醫院", coordinate: .init(latitude: 22.4450, longitude: 114.0300), category: .hospital),
        Location(name: "北區醫院", coordinate: .init(latitude: 22.4960, longitude: 114.1400), category: .hospital),
        Location(name: "仁愛醫院", coordinate: .init(latitude: 22.4550, longitude: 114.0300), category: .hospital),
    ]

    // MARK: - 政府機構

    static let government: [Location] = [
        Location(name: "入境事務處", coordinate: .init(latitude: 22.3160, longitude: 114.1720), category: .government),
        Location(name: "入境事務處（灣仔）", coordinate: .init(latitude: 22.2780, longitude: 114.1730), category: .government),
        Location(name: "稅務大樓", coordinate: .init(latitude: 22.3070, longitude: 114.1750), category: .government),
        Location(name: "政府合署", coordinate: .init(latitude: 22.2850, longitude: 114.1570), category: .government),
        Location(name: "懲教署", coordinate: .init(latitude: 22.2820, longitude: 114.1570), category: .government),
        Location(name: "高等法院", coordinate: .init(latitude: 22.2800, longitude: 114.1570), category: .government),
        Location(name: "區域法院", coordinate: .init(latitude: 22.2810, longitude: 114.1580), category: .government),
        Location(name: "中央政府合署", coordinate: .init(latitude: 22.2830, longitude: 114.1560), category: .government),
        Location(name: "人民入境事務處大樓", coordinate: .init(latitude: 22.3160, longitude: 114.1720), category: .government),
        Location(name: "香港大會堂", coordinate: .init(latitude: 22.2860, longitude: 114.1610), category: .government),
        Location(name: "政府總部", coordinate: .init(latitude: 22.2820, longitude: 114.1620), category: .government),
        Location(name: "立法會", coordinate: .init(latitude: 22.2820, longitude: 114.1620), category: .government),
        Location(name: "添馬艦政府總部", coordinate: .init(latitude: 22.2810, longitude: 114.1640), category: .government),
        Location(name: "郵政總局", coordinate: .init(latitude: 22.2860, longitude: 114.1560), category: .government),
        Location(name: "消防總局", coordinate: .init(latitude: 22.2830, longitude: 114.1530), category: .government),
        Location(name: "警察總部", coordinate: .init(latitude: 22.2740, longitude: 114.1740), category: .government),
        Location(name: "灣仔政府合署", coordinate: .init(latitude: 22.2760, longitude: 114.1720), category: .government),
        Location(name: "九龍政府合署", coordinate: .init(latitude: 22.3120, longitude: 114.1710), category: .government),
        Location(name: "社會福利署", coordinate: .init(latitude: 22.2830, longitude: 114.1550), category: .government),
        Location(name: "房屋署", coordinate: .init(latitude: 22.3180, longitude: 114.1700), category: .government),
    ]

    // MARK: - 酒店

    static let hotels: [Location] = [
        Location(name: "半島酒店", coordinate: .init(latitude: 22.2950, longitude: 114.1720), category: .hotel),
        Location(name: "洲際酒店", coordinate: .init(latitude: 22.2940, longitude: 114.1720), category: .hotel),
        Location(name: "凱悅酒店（尖沙咀）", coordinate: .init(latitude: 22.2980, longitude: 114.1740), category: .hotel),
        Location(name: "喜來登酒店", coordinate: .init(latitude: 22.2960, longitude: 114.1720), category: .hotel),
        Location(name: "香格里拉酒店", coordinate: .init(latitude: 22.2780, longitude: 114.1690), category: .hotel),
        Location(name: "文華東方酒店", coordinate: .init(latitude: 22.2820, longitude: 114.1580), category: .hotel),
        Location(name: "港島香格里拉", coordinate: .init(latitude: 22.2780, longitude: 114.1680), category: .hotel),
        Location(name: "君悅酒店", coordinate: .init(latitude: 22.2820, longitude: 114.1720), category: .hotel),
        Location(name: "萬豪酒店", coordinate: .init(latitude: 22.2800, longitude: 114.1700), category: .hotel),
        Location(name: "日航酒店", coordinate: .init(latitude: 22.2840, longitude: 114.1750), category: .hotel),
        Location(name: "帝苑酒店", coordinate: .init(latitude: 22.2960, longitude: 114.1760), category: .hotel),
        Location(name: "海景嘉福酒店", coordinate: .init(latitude: 22.2940, longitude: 114.1760), category: .hotel),
        Location(name: "九龍酒店", coordinate: .init(latitude: 22.2980, longitude: 114.1710), category: .hotel),
        Location(name: "富豪酒店（九龍）", coordinate: .init(latitude: 22.3140, longitude: 114.1710), category: .hotel),
        Location(name: "帝都酒店", coordinate: .init(latitude: 22.3810, longitude: 114.1880), category: .hotel),
        Location(name: "帝京酒店", coordinate: .init(latitude: 22.3220, longitude: 114.1710), category: .hotel),
        Location(name: "九龍香格里拉", coordinate: .init(latitude: 22.2960, longitude: 114.1750), category: .hotel),
        Location(name: "唯港薈", coordinate: .init(latitude: 22.2970, longitude: 114.1740), category: .hotel),
        Location(name: "香港洲際酒店", coordinate: .init(latitude: 22.2940, longitude: 114.1720), category: .hotel),
        Location(name: "香港麗思卡爾頓", coordinate: .init(latitude: 22.3040, longitude: 114.1610), category: .hotel),
    ]

    // MARK: - 地標

    static let landmarks: [Location] = [
        Location(name: "和昌大押", coordinate: .init(latitude: 22.2785, longitude: 114.1720), category: .landmark),
        Location(name: "天星碼頭", coordinate: .init(latitude: 22.2890, longitude: 114.1600), category: .landmark),
        Location(name: "中環碼頭", coordinate: .init(latitude: 22.2880, longitude: 114.1570), category: .landmark),
        Location(name: "尖沙咀鐘樓", coordinate: .init(latitude: 22.2930, longitude: 114.1700), category: .landmark),
        Location(name: "金紫荊廣場", coordinate: .init(latitude: 22.2820, longitude: 114.1730), category: .landmark),
        Location(name: "太平山頂", coordinate: .init(latitude: 22.2760, longitude: 114.1500), category: .landmark),
        Location(name: "凌霄閣", coordinate: .init(latitude: 22.2760, longitude: 114.1500), category: .landmark),
        Location(name: "維多利亞公園", coordinate: .init(latitude: 22.2810, longitude: 114.1880), category: .landmark),
        Location(name: "黃大仙祠", coordinate: .init(latitude: 22.3410, longitude: 114.1930), category: .landmark),
        Location(name: "志蓮淨苑", coordinate: .init(latitude: 22.3380, longitude: 114.2000), category: .landmark),
        Location(name: "天壇大佛", coordinate: .init(latitude: 22.2540, longitude: 114.0060), category: .landmark),
        Location(name: "大嶼山寶蓮寺", coordinate: .init(latitude: 22.2540, longitude: 114.0060), category: .landmark),
        Location(name: "青馬大橋", coordinate: .init(latitude: 22.3520, longitude: 114.0740), category: .landmark),
        Location(name: "昂坪360", coordinate: .init(latitude: 22.2600, longitude: 114.0150), category: .landmark),
        Location(name: "香港公園", coordinate: .init(latitude: 22.2780, longitude: 114.1640), category: .landmark),
        Location(name: "海洋公園", coordinate: .init(latitude: 22.2390, longitude: 114.1740), category: .landmark),
        Location(name: "迪士尼樂園", coordinate: .init(latitude: 22.3130, longitude: 114.0450), category: .landmark),
        Location(name: "星光大道", coordinate: .init(latitude: 22.2930, longitude: 114.1740), category: .landmark),
        Location(name: "西九文化區", coordinate: .init(latitude: 22.3030, longitude: 114.1600), category: .landmark),
        Location(name: "M+博物館", coordinate: .init(latitude: 22.3030, longitude: 114.1600), category: .landmark),
        Location(name: "香港藝術館", coordinate: .init(latitude: 22.2940, longitude: 114.1700), category: .landmark),
        Location(name: "香港太空館", coordinate: .init(latitude: 22.2940, longitude: 114.1710), category: .landmark),
        Location(name: "香港歷史博物館", coordinate: .init(latitude: 22.3020, longitude: 114.1760), category: .landmark),
        Location(name: "香港科學館", coordinate: .init(latitude: 22.3020, longitude: 114.1770), category: .landmark),
        Location(name: "紅磡體育館", coordinate: .init(latitude: 22.3030, longitude: 114.1810), category: .landmark),
        Location(name: "啟德郵輪碼頭", coordinate: .init(latitude: 22.3100, longitude: 114.2120), category: .landmark),
        Location(name: "中環廣場", coordinate: .init(latitude: 22.2820, longitude: 114.1730), category: .landmark),
        Location(name: "國際金融中心", coordinate: .init(latitude: 22.2850, longitude: 114.1580), category: .landmark),
        Location(name: "環球貿易廣場", coordinate: .init(latitude: 22.3040, longitude: 114.1610), category: .landmark),
        Location(name: "中銀大廈", coordinate: .init(latitude: 22.2790, longitude: 114.1620), category: .landmark),
        Location(name: "匯豐總行", coordinate: .init(latitude: 22.2810, longitude: 114.1590), category: .landmark),
        Location(name: "長江集團中心", coordinate: .init(latitude: 22.2800, longitude: 114.1610), category: .landmark),
        Location(name: "怡和大廈", coordinate: .init(latitude: 22.2850, longitude: 114.1580), category: .landmark),
        Location(name: "交易廣場", coordinate: .init(latitude: 22.2850, longitude: 114.1580), category: .landmark),
        Location(name: "太古廣場", coordinate: .init(latitude: 22.2780, longitude: 114.1660), category: .landmark),
        Location(name: "時代廣場", coordinate: .init(latitude: 22.2780, longitude: 114.1810), category: .landmark),
        Location(name: "崇光百貨", coordinate: .init(latitude: 22.2810, longitude: 114.1810), category: .landmark),
        Location(name: "海港城", coordinate: .init(latitude: 22.2960, longitude: 114.1690), category: .landmark),
        Location(name: "朗豪坊", coordinate: .init(latitude: 22.3190, longitude: 114.1690), category: .landmark),
        Location(name: "又一城", coordinate: .init(latitude: 22.3380, longitude: 114.1750), category: .landmark),
        Location(name: "apm", coordinate: .init(latitude: 22.3120, longitude: 114.2260), category: .landmark),
        Location(name: "德福廣場", coordinate: .init(latitude: 22.3180, longitude: 114.2160), category: .landmark),
    ]

    // MARK: - 交通設施

    static let transport: [Location] = [
        Location(name: "香港站", coordinate: .init(latitude: 22.2850, longitude: 114.1580), category: .transport),
        Location(name: "中環站", coordinate: .init(latitude: 22.2820, longitude: 114.1590), category: .transport),
        Location(name: "金鐘站", coordinate: .init(latitude: 22.2790, longitude: 114.1650), category: .transport),
        Location(name: "灣仔站", coordinate: .init(latitude: 22.2780, longitude: 114.1730), category: .transport),
        Location(name: "銅鑼灣站", coordinate: .init(latitude: 22.2800, longitude: 114.1820), category: .transport),
        Location(name: "天后站", coordinate: .init(latitude: 22.2860, longitude: 114.1910), category: .transport),
        Location(name: "北角站", coordinate: .init(latitude: 22.2910, longitude: 114.1990), category: .transport),
        Location(name: "太古站", coordinate: .init(latitude: 22.2880, longitude: 114.2110), category: .transport),
        Location(name: "西灣河站", coordinate: .init(latitude: 22.2820, longitude: 114.2190), category: .transport),
        Location(name: "筲箕灣站", coordinate: .init(latitude: 22.2790, longitude: 114.2240), category: .transport),
        Location(name: "杏花邨站", coordinate: .init(latitude: 22.2700, longitude: 114.2370), category: .transport),
        Location(name: "尖沙咀站", coordinate: .init(latitude: 22.2980, longitude: 114.1720), category: .transport),
        Location(name: "尖東站", coordinate: .init(latitude: 22.2950, longitude: 114.1760), category: .transport),
        Location(name: "旺角站", coordinate: .init(latitude: 22.3190, longitude: 114.1690), category: .transport),
        Location(name: "太子站", coordinate: .init(latitude: 22.3240, longitude: 114.1680), category: .transport),
        Location(name: "深水埗站", coordinate: .init(latitude: 22.3300, longitude: 114.1620), category: .transport),
        Location(name: "長沙灣站", coordinate: .init(latitude: 22.3360, longitude: 114.1570), category: .transport),
        Location(name: "荔枝角站", coordinate: .init(latitude: 22.3380, longitude: 114.1500), category: .transport),
        Location(name: "美孚站", coordinate: .init(latitude: 22.3370, longitude: 114.1420), category: .transport),
        Location(name: "九龍塘站", coordinate: .init(latitude: 22.3350, longitude: 114.1750), category: .transport),
        Location(name: "樂富站", coordinate: .init(latitude: 22.3370, longitude: 114.1870), category: .transport),
        Location(name: "黃大仙站", coordinate: .init(latitude: 22.3400, longitude: 114.1940), category: .transport),
        Location(name: "鑽石山站", coordinate: .init(latitude: 22.3390, longitude: 114.2010), category: .transport),
        Location(name: "彩虹站", coordinate: .init(latitude: 22.3360, longitude: 114.2070), category: .transport),
        Location(name: "九龍灣站", coordinate: .init(latitude: 22.3230, longitude: 114.2140), category: .transport),
        Location(name: "牛頭角站", coordinate: .init(latitude: 22.3170, longitude: 114.2200), category: .transport),
        Location(name: "觀塘站", coordinate: .init(latitude: 22.3120, longitude: 114.2260), category: .transport),
        Location(name: "油塘站", coordinate: .init(latitude: 22.3080, longitude: 114.2370), category: .transport),
        Location(name: "調景嶺站", coordinate: .init(latitude: 22.3040, longitude: 114.2500), category: .transport),
        Location(name: "沙田站", coordinate: .init(latitude: 22.3810, longitude: 114.1880), category: .transport),
        Location(name: "大埔墟站", coordinate: .init(latitude: 22.4430, longitude: 114.1680), category: .transport),
        Location(name: "上水站", coordinate: .init(latitude: 22.5030, longitude: 114.1300), category: .transport),
        Location(name: "落馬洲站", coordinate: .init(latitude: 22.5110, longitude: 114.0630), category: .transport),
        Location(name: "屯門站", coordinate: .init(latitude: 22.3910, longitude: 114.0000), category: .transport),
        Location(name: "天水圍站", coordinate: .init(latitude: 22.4450, longitude: 114.0050), category: .transport),
        Location(name: "元朗站", coordinate: .init(latitude: 22.4450, longitude: 114.0350), category: .transport),
        Location(name: "機場快綫香港站", coordinate: .init(latitude: 22.2850, longitude: 114.1580), category: .transport),
        Location(name: "機場快綫九龍站", coordinate: .init(latitude: 22.3040, longitude: 114.1620), category: .transport),
        Location(name: "機場快綫青衣站", coordinate: .init(latitude: 22.3580, longitude: 114.1070), category: .transport),
        Location(name: "香港國際機場", coordinate: .init(latitude: 22.3080, longitude: 113.9185), category: .transport),
        Location(name: "啟德郵輪碼頭", coordinate: .init(latitude: 22.3100, longitude: 114.2120), category: .transport),
        Location(name: "港澳碼頭", coordinate: .init(latitude: 22.2890, longitude: 114.1530), category: .transport),
        Location(name: "中國客運碼頭", coordinate: .init(latitude: 22.2980, longitude: 114.1670), category: .transport),
        Location(name: "紅磡站", coordinate: .init(latitude: 22.3040, longitude: 114.1810), category: .transport),
        Location(name: "會展站", coordinate: .init(latitude: 22.2820, longitude: 114.1730), category: .transport),
        Location(name: "柯士甸站", coordinate: .init(latitude: 22.3050, longitude: 114.1700), category: .transport),
    ]

    // MARK: - 教育

    static let education: [Location] = [
        Location(name: "香港大學", coordinate: .init(latitude: 22.2830, longitude: 114.1370), category: .education),
        Location(name: "香港中文大學", coordinate: .init(latitude: 22.4190, longitude: 114.2090), category: .education),
        Location(name: "香港科技大學", coordinate: .init(latitude: 22.3360, longitude: 114.2630), category: .education),
        Location(name: "香港理工大學", coordinate: .init(latitude: 22.3040, longitude: 114.1780), category: .education),
        Location(name: "香港城市大學", coordinate: .init(latitude: 22.3380, longitude: 114.1710), category: .education),
        Location(name: "浸會大學", coordinate: .init(latitude: 22.3380, longitude: 114.1770), category: .education),
        Location(name: "嶺南大學", coordinate: .init(latitude: 22.4110, longitude: 114.0270), category: .education),
        Location(name: "香港教育大學", coordinate: .init(latitude: 22.4680, longitude: 114.1940), category: .education),
        Location(name: "香港公開大學", coordinate: .init(latitude: 22.3180, longitude: 114.1750), category: .education),
    ]

    // MARK: - 宗教

    static let religious: [Location] = [
        Location(name: "文武廟", coordinate: .init(latitude: 22.2860, longitude: 114.1510), category: .religious),
        Location(name: "黃大仙祠", coordinate: .init(latitude: 22.3410, longitude: 114.1930), category: .religious),
        Location(name: "天后廟（銅鑼灣）", coordinate: .init(latitude: 22.2810, longitude: 114.1870), category: .religious),
        Location(name: "大坑蓮花宮", coordinate: .init(latitude: 22.2780, longitude: 114.1900), category: .religious),
        Location(name: "青松觀", coordinate: .init(latitude: 22.3960, longitude: 114.0070), category: .religious),
        Location(name: "妙法寺", coordinate: .init(latitude: 22.3940, longitude: 114.0150), category: .religious),
    ]

    // MARK: - 公園

    static let parks: [Location] = [
        Location(name: "維多利亞公園", coordinate: .init(latitude: 22.2810, longitude: 114.1880), category: .park),
        Location(name: "九龍公園", coordinate: .init(latitude: 22.3020, longitude: 114.1700), category: .park),
        Location(name: "香港公園", coordinate: .init(latitude: 22.2780, longitude: 114.1640), category: .park),
        Location(name: "摩士公園", coordinate: .init(latitude: 22.3370, longitude: 114.1920), category: .park),
        Location(name: "石硤尾公園", coordinate: .init(latitude: 22.3340, longitude: 114.1670), category: .park),
        Location(name: "荔枝角公園", coordinate: .init(latitude: 22.3370, longitude: 114.1470), category: .park),
        Location(name: "大埔海濱公園", coordinate: .init(latitude: 22.4460, longitude: 114.1660), category: .park),
        Location(name: "沙田公園", coordinate: .init(latitude: 22.3790, longitude: 114.1880), category: .park),
    ]

    // MARK: - 所有地點

    static let all: [Location] = roads + hospitals + government + hotels + landmarks + transport + education + religious + parks
}
