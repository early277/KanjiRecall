import Foundation

struct KanjiTag: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var kanjiIDs: [String]
    var source: String?
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String, kanjiIDs: [String], source: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kanjiIDs = kanjiIDs
        self.source = source
        self.createdAt = createdAt
    }
}

struct ExtractedKanji: Identifiable, Hashable {
    var id: String { kanji }
    var kanji: String
    var count: Int
    var cardID: String?
    var level: String?

    var isRegistered: Bool {
        cardID != nil
    }
}
