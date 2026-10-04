import CoreLocation
import Foundation

/// OpenPOI API(https://openpoiapi.com)クライアント。
///
/// 日本全国約337万件の POI(Overture Maps + 食品営業許可オープンデータ)。
/// API キー不要・無料。レート制限は全体で 200req/s と十分に太い。
/// 利用条件の出典表記は、アプリ内ヘルプとサポートページに
/// 「OpenPOI API」+ 出典ページ(attribution.html)へのリンクで満たす。
///
/// カテゴリ指定パラメータは無いため、center+radius で取得してから
/// レスポンスの `category` をクライアント側でジャンル照合する。
enum OpenPOIService {

    private struct Response: Decodable {
        let results: [POI]
    }

    struct POI: Decodable {
        let name: String
        let lat: Double
        let lng: Double
        let category: String?
        let source: String?
    }

    /// 周辺スポットを距離順で返す。失敗・圏外(海外等)・該当なしのときは空配列。
    /// 呼び出し側は空なら Apple(MKLocalSearch)へフォールバックする。
    static func fetchNearby(location: CLLocation, genre: POIGenre, count: Int) async -> [NearbyPlace] {
        guard genre != .none, count > 0,
              let allowed = genre.openPOICategories else { return [] }

        var comps = URLComponents(string: "https://api.openpoiapi.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "center",
                         value: "\(location.coordinate.longitude),\(location.coordinate.latitude)"),
            URLQueryItem(name: "radius", value: "500"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        guard let url = comps.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let parsed = try JSONDecoder().decode(Response.self, from: data)

            let sorted = parsed.results
                .filter { poi in
                    !poi.name.isEmpty
                        && (allowed.isEmpty || allowed.contains(poi.category ?? ""))
                        && !Self.looksCorporate(poi.name)
                        && !Self.containsPrivateUseChars(poi.name)
                        && !(poi.source == "jff" && Self.looksPersonalName(poi.name))
                        && !(poi.source == "jff" && Self.looksNoSpacePersonalName(poi.name))
                }
                .map { poi in
                    NearbyPlace(name: poi.name,
                                distance: CLLocation(latitude: poi.lat, longitude: poi.lng)
                                    .distance(from: location))
                }
                .sorted { $0.distance < $1.distance }

            // 同名の重複を除く(Overture と食品営業許可の二重登録・チェーン店対策)
            var seen = Set<String>()
            var unique: [NearbyPlace] = []
            for place in sorted where seen.insert(place.name).inserted {
                unique.append(place)
            }
            return Array(unique.prefix(count))
        } catch {
            return []
        }
    }
    /// 食品営業許可データ由来の「法人名」エントリを弾く。
    /// 営業許可の名義が運営会社(株式会社〇〇)で登録されているものは店名として焼き込めない。
    private static let corporateMarkers = [
        "株式会社", "有限会社", "合同会社", "合資会社", "（株）", "(株)", "㈱", "㈲", "（有）", "(有)",
    ]
    private static func looksCorporate(_ name: String) -> Bool {
        corporateMarkers.contains { name.contains($0) }
    }

    /// 「姓 名」形式の個人名を弾く(食品営業許可データ限定で適用)。
    /// スナック等は営業許可が経営者の個人名義で登録されていることが多く、
    /// そのまま焼き込むと他人の氏名が写真に入ってしまう。
    /// 天文館の実データ(約600件)で検証済み: 個人名はすべて「漢字姓+スペース+名」形式で、
    /// 正当な店名の誤爆は「漢字2語」の屋号のみ(安全側に倒して除外する)。
    /// 私用領域(外字)は旧字体の氏名に現れるためパターンにも含める。
    private static let personalNamePattern =
        "^[一-龥々\u{E000}-\u{F8FF}]{1,4}[ \u{3000}]+[一-龥々ぁ-んァ-ヶー\u{E000}-\u{F8FF}]{1,4}$"
    private static func looksPersonalName(_ name: String) -> Bool {
        name.range(of: personalNamePattern, options: .regularExpression) != nil
    }

    /// 私用領域(外字)を含む名前を弾く。端末フォントに無く豆腐(□)で描画されるため、
    /// 個人名かどうかに関わらず焼き込みに使えない。
    private static func containsPrivateUseChars(_ name: String) -> Bool {
        name.unicodeScalars.contains { (0xE000...0xF8FF).contains($0.value) }
    }

    /// スペースなしのフルネーム(「藤田恵美子」形式)を弾く。
    /// 47都道府県の繁華街サンプリング(約2,800件のjffエントリ)で検証し、
    /// この規則の追加除外は実在の個人名2件のみ・店名の誤爆ゼロだった。
    /// 条件: 漢字のみ・3〜6文字・常用姓で始まり残り1〜3文字・店舗語を含まない。
    private static func looksNoSpacePersonalName(_ name: String) -> Bool {
        guard name.range(of: "^[一-龥々]{3,6}$", options: .regularExpression) != nil,
              name.range(of: shopWordPattern, options: .regularExpression) == nil else { return false }
        let count = name.count
        for surname in Self.commonSurnames where name.hasPrefix(surname) {
            let rest = count - surname.count
            if (1...3).contains(rest) { return true }
        }
        return false
    }

    /// 店舗・業態を示す語(これを含む名前は屋号とみなす)
    private static let shopWordPattern =
        "(店|屋|亭|庵|家|処|堂|軒|館|荘|園|農場|牧場|製麺|製菓|製パン|水産|青果|精肉|鮮魚|食堂|寿司|鮨|すし|焼|カフェ|喫茶|珈琲|ラーメン|そば|蕎麦|うどん|餃子|酒場|酒店|酒造|バル|キッチン|ダイニング|ホルモン|ベーカリー|パン|菓子|スナック|クラブ|ラウンジ|バー|丸|本舗|商店|書店|薬局|模型|時計|眼鏡|電器|会館|センター|ホテル|旅館)"

    /// 常用姓(全国上位 + 南九州・沖縄の地域姓)。スペースなし個人名の判定に使う。
    private static let commonSurnames: [String] = [
        "佐藤", "鈴木", "高橋", "田中", "渡辺", "伊藤", "山本", "中村", "小林", "加藤",
        "吉田", "山田", "佐々木", "山口", "松本", "井上", "木村", "斎藤", "清水", "山崎",
        "阿部", "森田", "池田", "橋本", "石川", "山下", "中島", "石井", "小川", "前田",
        "岡田", "長谷川", "藤田", "後藤", "近藤", "村上", "遠藤", "青木", "坂本", "斉藤",
        "福田", "太田", "西村", "藤井", "金子", "岡本", "藤原", "三浦", "中川", "中野",
        "原田", "松田", "竹内", "小野", "田村", "中山", "和田", "石田", "上田", "内田",
        "柴田", "酒井", "宮崎", "横山", "高木", "安藤", "宮本", "大野", "小島", "谷口",
        "今井", "工藤", "高田", "増田", "丸山", "杉山", "村田", "大塚", "新井", "小山",
        "平野", "藤本", "河野", "上野", "武田", "野口", "松井", "千葉", "岩崎", "菅原",
        "木下", "久保", "佐野", "野村", "松尾", "市川", "菊地", "杉本", "古川", "大西",
        "島田", "水野", "桜井", "高野", "渡部", "吉川", "山内", "西田", "飯田", "菊池",
        "西川", "小松", "北村", "安田", "五十嵐", "川口", "平田", "中田", "久保田", "服部",
        "岩田", "土屋", "川崎", "福島", "本田", "樋口", "田口", "永井", "山中", "森本",
        "土井", "矢野", "秋山", "石原", "松岡", "浜田", "馬場", "森山", "小沢", "栗原",
        "松下", "中西", "大石", "成田", "大久保", "松浦", "吉村", "望月", "荒木", "大橋",
        "篠原", "岡崎", "川上", "宮田", "広瀬", "石橋", "須藤", "萩原", "大谷", "平井",
        "浅野", "岡部", "堀内", "荒井", "大森", "松原", "小泉", "内藤", "川村", "白石",
        "坂口", "栗田", "片山", "山根", "吉岡", "植田", "奥村", "森谷", "神田", "熊谷",
        "堀口", "北川", "尾崎", "星野", "松村", "落合", "川島", "根本", "村松", "小田",
        "黒田", "塚本", "田辺", "吉原", "奥田", "岸本", "青山", "今村", "竹田", "金井",
        "杉浦", "細川", "杉原", "大島", "山岸", "西山", "小西", "大沢", "野田", "吉本",
        "竹本", "茂木", "浅井", "徳留", "鮫島", "川畑", "瀬戸口", "東郷", "別府", "堀之内",
        "有村", "四宮", "日高", "栫井", "諏訪下", "松野下", "前園", "伊集院", "金城", "大城",
        "比嘉", "宮城", "新垣", "玉城", "上原", "島袋", "平良", "山城", "知念", "仲宗根",
        "具志堅", "城間", "又吉", "砂川",
    ]
}

extension POIGenre {
    /// OpenPOI の category 語彙との対応(実データから採取した語彙に基づく)。
    /// nil = OpenPOI では探さない(駅・交通は語彙がないため Apple 検索のみ)。
    /// 空集合 = 全カテゴリ許可。
    var openPOICategories: Set<String>? {
        switch self {
        case .none:
            return nil
        case .all:
            return []
        case .food:
            return ["restaurant", "fast_food", "bar_izakaya", "cafe", "bakery"]
        case .cafe:
            return ["cafe", "bakery"]
        case .sightseeing:
            return ["tourism"]
        case .transport:
            return nil
        }
    }
}
