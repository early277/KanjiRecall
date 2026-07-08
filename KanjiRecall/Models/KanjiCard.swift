import Foundation

struct KanjiCard: Identifiable, Codable, Hashable {
    var id: String
    var level: String?
    var kanji: String
    var question: String
    var targetText: String
    var parts: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case level
        case kanji
        case question
        case targetText
        case parts
    }

    init(id: String? = nil, level: String? = nil, kanji: String, question: String, targetText: String, parts: [String]) {
        self.id = id ?? kanji
        self.level = level
        self.kanji = kanji
        self.question = question
        self.targetText = targetText
        self.parts = parts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedKanji = try container.decode(String.self, forKey: .kanji)
        self.kanji = decodedKanji
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? decodedKanji
        self.level = try container.decodeIfPresent(String.self, forKey: .level)
        self.question = try container.decode(String.self, forKey: .question)
        self.targetText = try container.decode(String.self, forKey: .targetText)
        self.parts = try container.decodeIfPresent([String].self, forKey: .parts) ?? []
    }

    var questionForSpeech: String {
        question.replacingOccurrences(of: "{target}", with: targetText)
    }
}



enum KanjiSortOrder: String, CaseIterable, Identifiable {
    case original
    case tagFrequency
    case level
    case kanji

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original:
            return "初期順"
        case .tagFrequency:
            return "タグ頻度順"
        case .level:
            return "レベル順"
        case .kanji:
            return "漢字コード順"
        }
    }
}

func kanjiLevelSortRank(_ level: String?) -> Int {
    guard let level, !level.isEmpty else { return 9990 }

    switch level {
    case "S1": return 10
    case "S2": return 20
    case "S3": return 30
    case "S4": return 40
    case "S5": return 50
    case "S6": return 60
    case "CH1", "C1": return 110
    case "CH2", "C2": return 120
    case "CH3", "C3", "JH": return 130
    case "H1", "K1", "HS": return 210
    case "H2", "K2", "GEN": return 220
    case "X1": return 300
    case "J", "J1", "J2", "J3", "J4": return 410
    default:
        if level.hasPrefix("CH") || level.hasPrefix("C") { return 190 }
        if level.hasPrefix("H") || level.hasPrefix("K") { return 290 }
        if level.hasPrefix("X") { return 390 }
        if level.hasPrefix("J") { return 410 }
        return 9000
    }
}

struct KanjiLevelFilter: Identifiable, Hashable {
    let id: String
    let title: String
    let codes: Set<String>?

    static let all = KanjiLevelFilter(id: "all", title: "すべて", codes: nil)

    static let defaults: [KanjiLevelFilter] = [
        .all,
        KanjiLevelFilter(id: "S1", title: "小学1年生", codes: ["S1"]),
        KanjiLevelFilter(id: "S2", title: "小学2年生", codes: ["S2"]),
        KanjiLevelFilter(id: "S3", title: "小学3年生", codes: ["S3"]),
        KanjiLevelFilter(id: "S4", title: "小学4年生", codes: ["S4"]),
        KanjiLevelFilter(id: "S5", title: "小学5年生", codes: ["S5"]),
        KanjiLevelFilter(id: "S6", title: "小学6年生", codes: ["S6"]),
        KanjiLevelFilter(id: "CH", title: "中学生", codes: ["CH1", "CH2", "CH3", "C1", "C2", "C3"]),
        KanjiLevelFilter(id: "H", title: "高校・一般", codes: ["H1", "H2", "K1", "K2"]),
        KanjiLevelFilter(id: "X1", title: "常用外", codes: ["X1"]),
        KanjiLevelFilter(id: "J", title: "その他", codes: ["J"]),
        KanjiLevelFilter(id: "none", title: "レベルなし", codes: [""])
    ]

    func matches(_ level: String?) -> Bool {
        guard let codes else { return true }

        let value = level ?? ""
        if codes.contains(value) {
            return true
        }

        // 保険: CH1/CH2/CH3, H1/H2, K1/K2 のような派生表記にも対応
        if id == "CH" && (value.hasPrefix("CH") || value.hasPrefix("C")) {
            return true
        }
        if id == "H" && (value.hasPrefix("H") || value.hasPrefix("K")) {
            return true
        }
        if id == "X1" && value.hasPrefix("X") {
            return true
        }
        if id == "J" && value.hasPrefix("J") {
            return true
        }

        return false
    }
}

func levelDisplayName(_ level: String?) -> String {
    guard let level, !level.isEmpty else { return "レベルなし" }

    switch level {
    case "S1": return "小学1年生"
    case "S2": return "小学2年生"
    case "S3": return "小学3年生"
    case "S4": return "小学4年生"
    case "S5": return "小学5年生"
    case "S6": return "小学6年生"
    case "CH1", "CH2", "CH3", "C1", "C2", "C3": return "中学生"
    case "H1", "H2", "K1", "K2": return "高校・一般"
    case "X1": return "常用外"
    case "J", "J1", "J2", "J3", "J4": return "その他"
    default:
        if level.hasPrefix("CH") || level.hasPrefix("C") {
            return "中学生"
        }
        if level.hasPrefix("H") || level.hasPrefix("K") {
            return "高校・一般"
        }
        if level.hasPrefix("X") {
            return "常用外"
        }
        if level.hasPrefix("J") {
            return "その他"
        }
        return level
    }
}
