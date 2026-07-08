import Foundation
import SwiftUI

struct SavedFilterSettings: Codable {
    var levelIDs: [String]
    var tagID: String
    var includeUntried: Bool
    var includeReview: Bool
    var includeMastered: Bool
}

enum AppTab: Hashable {
    case practice
    case filter
    case list
    case pdf
    case tag
    case settings
}

@MainActor
final class KanjiStore: ObservableObject {
    @Published var cards: [KanjiCard] = []
    @Published var currentIndex: Int = 0
    @Published var currentCardID: String? = nil
    @Published var reviewIDs: Set<String> = []
    @Published var masteredIDs: Set<String> = []
    @Published var masteredUntil: [String: TimeInterval] = [:]
    @Published var tags: [KanjiTag] = []

    @Published var selectedLevelFilterIDs: Set<String> = ["all"] {
        didSet { saveFilterSettings() }
    }
    @Published var selectedTagFilterID: String = "all" {
        didSet { saveFilterSettings() }
    }
    @Published var includeUntried: Bool = true {
        didSet { saveFilterSettings() }
    }
    @Published var includeReview: Bool = true {
        didSet { saveFilterSettings() }
    }
    @Published var includeMastered: Bool = false {
        didSet { saveFilterSettings() }
    }

    @Published var sortOrder: KanjiSortOrder = .original {
        didSet {
            saveSortOrder()
            lockCurrentCardIfNeeded()
        }
    }

    @Published var prioritizeAnswered: Bool = true {
        didSet {
            savePrioritizeAnswered()
            lockCurrentCardIfNeeded()
        }
    }

    @Published var lastMessage: String = ""
    @Published var selectedTab: AppTab = .practice

    // 絞り込み外のパーツ漢字を一時的に表示するためのID。
    // 絞り込み条件そのものは変更・保存しない。
    @Published var linkedCardID: String? = nil

    private let cardsKey = "kanji_cards_json_v4"
    private let reviewKey = "kanji_review_ids_v4"
    private let masteredKey = "kanji_mastered_ids_v1"
    private let masteredUntilKey = "kanji_mastered_until_v1"
    private let tagsKey = "kanji_tags_v4"
    private let tagsFileName = "kanji_tags_v5.json"

    private let filterLevelKey = "kanji_filter_level_v1"
    private let filterLevelsKey = "kanji_filter_levels_v2"
    private let filterTagKey = "kanji_filter_tag_v1"
    private let filterUntriedKey = "kanji_filter_untried_v1"
    private let filterReviewKey = "kanji_filter_review_v1"
    private let filterMasteredKey = "kanji_filter_mastered_v1"
    private let filterSettingsFileName = "kanji_filter_settings_v2.json"
    private let sortOrderKey = "kanji_sort_order_v1"
    private let prioritizeAnsweredKey = "kanji_prioritize_answered_v1"

    init() {
        loadCards()
        loadReviewIDs()
        loadMasteredIDs()
        loadMasteredUntil()
        loadTags()
        loadFilterSettings()
        loadSortOrder()
        loadPrioritizeAnswered()
        lockCurrentCardIfNeeded()
    }

    var levelFilterOptions: [KanjiLevelFilter] {
        let existingLevels = Set(cards.map { $0.level ?? "" })

        return KanjiLevelFilter.defaults.filter { filter in
            if filter.id == "all" {
                return true
            }
            guard let codes = filter.codes else {
                return true
            }

            if filter.id == "CH" {
                return existingLevels.contains { $0.hasPrefix("CH") || $0.hasPrefix("C") }
            }
            if filter.id == "H" {
                return existingLevels.contains { $0.hasPrefix("H") || $0.hasPrefix("K") }
            }
            if filter.id == "X1" {
                return existingLevels.contains { $0.hasPrefix("X") }
            }
            if filter.id == "J" {
                return existingLevels.contains { $0.hasPrefix("J") }
            }
            if filter.id == "none" {
                return existingLevels.contains("")
            }

            return !existingLevels.isDisjoint(with: codes)
        }
    }

    var selectedLevelFilters: [KanjiLevelFilter] {
        if selectedLevelFilterIDs.contains("all") || selectedLevelFilterIDs.isEmpty {
            return [.all]
        }

        return levelFilterOptions.filter { selectedLevelFilterIDs.contains($0.id) && $0.id != "all" }
    }

    var selectedTag: KanjiTag? {
        guard selectedTagFilterID != "all" else { return nil }
        return tags.first(where: { $0.id == selectedTagFilterID })
    }

    var activeCards: [KanjiCard] {
        let tagIDSet = selectedTag.map { Set($0.kanjiIDs) }
        let useAllLevels = selectedLevelFilterIDs.contains("all") || selectedLevelFilterIDs.isEmpty

        // 重要:
        // selectedLevelFilters / levelFilterOptions は内部で cards を見るため、
        // filter の1件ごとに呼ぶと O(n^2) になり、一覧表示が極端に重くなる。
        // ここで1回だけ作って使い回す。
        let selectedFilters = useAllLevels ? [] : selectedLevelFilters

        let filtered = cards.filter { card in
            if !useAllLevels && !selectedFilters.contains(where: { $0.matches(card.level) }) {
                return false
            }

            if let tagIDSet, !tagIDSet.contains(card.id) {
                return false
            }

            switch status(for: card) {
            case .untried:
                return includeUntried
            case .review:
                return includeReview
            case .mastered:
                return includeMastered || isMasteredDue(card)
            }
        }

        return sortedActiveCards(filtered)
    }

    var filterSummary: String {
        var items: [String] = []

        let levelTitles = selectedLevelFilters
            .filter { $0.id != "all" }
            .map { $0.title }

        if !levelTitles.isEmpty {
            items.append("レベル: " + levelTitles.joined(separator: "・"))
        }

        if let selectedTag {
            items.append("タグ: \(selectedTag.name)")
        }

        var statusItems: [String] = []
        if includeUntried { statusItems.append("未出題") }
        if includeReview { statusItems.append("書けない") }
        if includeMastered { statusItems.append("書ける") }
        items.append("状態: \(statusItems.isEmpty ? "なし" : statusItems.joined(separator: "・"))")
        if sortOrder != .original {
            items.append("並び順: \(sortOrder.title)")
        }
        if prioritizeAnswered {
            items.append("回答済み優先")
        }

        return items.joined(separator: " / ")
    }

    var currentCard: KanjiCard? {
        if let linkedCardID,
           let linkedCard = cards.first(where: { $0.id == linkedCardID }) {
            return linkedCard
        }

        let list = activeCards
        guard !list.isEmpty else { return nil }

        if let currentCardID,
           let card = list.first(where: { $0.id == currentCardID }) {
            return card
        }

        let index = min(currentIndex, list.count - 1)
        return list[index]
    }

    var progressText: String {
        if let linkedCardID,
           let linkedCard = cards.first(where: { $0.id == linkedCardID }),
           !activeCards.contains(where: { $0.id == linkedCard.id }) {
            return "リンク表示 / \(activeCards.count)"
        }

        let list = activeCards
        guard !list.isEmpty else { return "0 / 0" }

        if let currentCardID,
           let index = list.firstIndex(where: { $0.id == currentCardID }) {
            return "\(index + 1) / \(list.count)"
        }

        return "\(min(currentIndex + 1, list.count)) / \(list.count)"
    }

    func status(for card: KanjiCard) -> CardStudyStatus {
        if reviewIDs.contains(card.id) {
            return .review
        }
        if masteredIDs.contains(card.id) {
            return .mastered
        }
        return .untried
    }

    func statusText(for card: KanjiCard) -> String {
        switch status(for: card) {
        case .untried:
            return "未出題"
        case .review:
            return "書けない"
        case .mastered:
            return masteryStatusText(for: card)
        }
    }

    func loadCards() {
        if let data = UserDefaults.standard.data(forKey: cardsKey),
           let decoded = try? JSONDecoder().decode([KanjiCard].self, from: data),
           !decoded.isEmpty {
            cards = decoded
            return
        }

        if let oldData = UserDefaults.standard.data(forKey: "kanji_cards_json_v2"),
           let oldDecoded = try? JSONDecoder().decode([KanjiCard].self, from: oldData),
           !oldDecoded.isEmpty {
            cards = oldDecoded
            saveCards()
            return
        }

        guard let url = Bundle.main.url(forResource: "kanji_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([KanjiCard].self, from: data) else {
            cards = []
            return
        }
        cards = decoded
    }

    func saveCards() {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        UserDefaults.standard.set(data, forKey: cardsKey)
    }

    func importCards(from data: Data) throws {
        let decoded = try JSONDecoder().decode([KanjiCard].self, from: data)
        try validateImportedCards(decoded)

        cards = decoded
        currentIndex = 0
        currentCardID = nil
        linkedCardID = nil
        selectedLevelFilterIDs = ["all"]
        selectedTagFilterID = "all"
        includeUntried = true
        includeReview = true
        includeMastered = false
        saveCards()
        saveFilterSettings()
        lastMessage = "\(decoded.count)件の漢字データを読み込みました。"
    }

    func resetCardsToBundle() {
        UserDefaults.standard.removeObject(forKey: cardsKey)
        currentIndex = 0
        currentCardID = nil
        linkedCardID = nil
        selectedLevelFilterIDs = ["all"]
        selectedTagFilterID = "all"
        includeUntried = true
        includeReview = true
        includeMastered = false
        loadCards()
        saveFilterSettings()
        lastMessage = "初期データに戻しました。"
    }

    func loadReviewIDs() {
        let array = UserDefaults.standard.stringArray(forKey: reviewKey)
            ?? UserDefaults.standard.stringArray(forKey: "kanji_review_ids_v3")
            ?? UserDefaults.standard.stringArray(forKey: "kanji_review_ids_v2")
            ?? []
        reviewIDs = Set(array)
    }

    func saveReviewIDs() {
        UserDefaults.standard.set(Array(reviewIDs), forKey: reviewKey)
    }

    func loadMasteredIDs() {
        let array = UserDefaults.standard.stringArray(forKey: masteredKey) ?? []
        masteredIDs = Set(array)
    }

    func saveMasteredIDs() {
        UserDefaults.standard.set(Array(masteredIDs), forKey: masteredKey)
    }

    func loadMasteredUntil() {
        let dictionary = UserDefaults.standard.dictionary(forKey: masteredUntilKey) as? [String: Double] ?? [:]
        masteredUntil = dictionary
    }

    func saveMasteredUntil() {
        UserDefaults.standard.set(masteredUntil, forKey: masteredUntilKey)
    }

    func loadTags() {
        if let data = try? Data(contentsOf: tagsFileURL),
           let decoded = try? JSONDecoder().decode([KanjiTag].self, from: data) {
            tags = decoded
            return
        }

        if let data = UserDefaults.standard.data(forKey: tagsKey),
           let decoded = try? JSONDecoder().decode([KanjiTag].self, from: data) {
            tags = decoded
            saveTags()
            return
        }

        if let oldData = UserDefaults.standard.data(forKey: "kanji_tags_v3"),
           let oldDecoded = try? JSONDecoder().decode([KanjiTag].self, from: oldData) {
            tags = oldDecoded
            saveTags()
            return
        }

        if let oldData = UserDefaults.standard.data(forKey: "kanji_tags_v2"),
           let oldDecoded = try? JSONDecoder().decode([KanjiTag].self, from: oldData) {
            tags = oldDecoded
            saveTags()
            return
        }

        tags = []
    }

    func saveTags() {
        guard let data = try? JSONEncoder().encode(tags) else { return }

        do {
            let directory = tagsFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: tagsFileURL, options: [.atomic])
        } catch {
            // ファイル保存に失敗しても、UserDefaults側をバックアップとして残す。
        }

        UserDefaults.standard.set(data, forKey: tagsKey)
    }

    private var tagsFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return base
            .appendingPathComponent("KanjiRecall", isDirectory: true)
            .appendingPathComponent(tagsFileName)
    }

    func loadFilterSettings() {
        let defaults = UserDefaults.standard
        let fileSettings = loadFilterSettingsFromFile()

        if let fileSettings {
            selectedLevelFilterIDs = Set(fileSettings.levelIDs)
            selectedTagFilterID = fileSettings.tagID.isEmpty ? "all" : fileSettings.tagID
            includeUntried = fileSettings.includeUntried
            includeReview = fileSettings.includeReview
            includeMastered = fileSettings.includeMastered
        } else {
            if let savedLevels = defaults.stringArray(forKey: filterLevelsKey), !savedLevels.isEmpty {
                selectedLevelFilterIDs = Set(savedLevels)
            } else if let savedLevel = defaults.string(forKey: filterLevelKey), !savedLevel.isEmpty {
                selectedLevelFilterIDs = [savedLevel]
            } else {
                selectedLevelFilterIDs = ["all"]
            }

            if let savedTag = defaults.string(forKey: filterTagKey), !savedTag.isEmpty {
                // タグ本体の読み込みに失敗した場合でも、保存済みのタグID自体は保持する。
                // 後でタグ本体が読めたときに復元できるよう、ここでは安易に all に戻さない。
                selectedTagFilterID = savedTag
            }

            if defaults.object(forKey: filterUntriedKey) != nil {
                includeUntried = defaults.bool(forKey: filterUntriedKey)
            }
            if defaults.object(forKey: filterReviewKey) != nil {
                includeReview = defaults.bool(forKey: filterReviewKey)
            }
            if defaults.object(forKey: filterMasteredKey) != nil {
                includeMastered = defaults.bool(forKey: filterMasteredKey)
            }
        }

        let oldJISLevelIDs = Set(["J1", "J2", "J3", "J4"])
        if !selectedLevelFilterIDs.isDisjoint(with: oldJISLevelIDs) {
            selectedLevelFilterIDs.subtract(oldJISLevelIDs)
            selectedLevelFilterIDs.insert("J")
        }

        let validLevelIDs = Set(levelFilterOptions.map { $0.id })
        selectedLevelFilterIDs = selectedLevelFilterIDs.filter { validLevelIDs.contains($0) }
        if selectedLevelFilterIDs.isEmpty {
            selectedLevelFilterIDs = ["all"]
        }

        if !includeUntried && !includeReview && !includeMastered {
            includeUntried = true
            includeReview = true
            includeMastered = false
        }
    }

    func saveFilterSettings() {
        let defaults = UserDefaults.standard
        let levels = Array(selectedLevelFilterIDs).sorted()

        defaults.set(levels, forKey: filterLevelsKey)
        defaults.set(levels.first ?? "all", forKey: filterLevelKey)
        defaults.set(selectedTagFilterID, forKey: filterTagKey)
        defaults.set(includeUntried, forKey: filterUntriedKey)
        defaults.set(includeReview, forKey: filterReviewKey)
        defaults.set(includeMastered, forKey: filterMasteredKey)

        let settings = SavedFilterSettings(
            levelIDs: levels,
            tagID: selectedTagFilterID,
            includeUntried: includeUntried,
            includeReview: includeReview,
            includeMastered: includeMastered
        )

        saveFilterSettingsToFile(settings)
    }

    private func loadFilterSettingsFromFile() -> SavedFilterSettings? {
        guard let data = try? Data(contentsOf: filterSettingsFileURL) else {
            return nil
        }

        return try? JSONDecoder().decode(SavedFilterSettings.self, from: data)
    }

    private func saveFilterSettingsToFile(_ settings: SavedFilterSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }

        do {
            let directory = filterSettingsFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: filterSettingsFileURL, options: [.atomic])
        } catch {
            // UserDefaults側にも保存しているため、ここではUIを止めない。
        }
    }

    private var filterSettingsFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return base
            .appendingPathComponent("KanjiRecall", isDirectory: true)
            .appendingPathComponent(filterSettingsFileName)
    }

    func isLevelFilterSelected(_ option: KanjiLevelFilter) -> Bool {
        selectedLevelFilterIDs.contains(option.id)
    }

    func applyLevelFilters(_ ids: Set<String>) {
        linkedCardID = nil

        let validIDs = Set(levelFilterOptions.map { $0.id })
        var cleaned = ids.filter { validIDs.contains($0) }

        if cleaned.isEmpty || cleaned.contains("all") {
            cleaned = ["all"]
        }

        selectedLevelFilterIDs = cleaned
        currentIndex = 0
        currentCardID = nil
        saveFilterSettings()
        lockCurrentCardIfNeeded()
    }

    func toggleLevelFilter(_ option: KanjiLevelFilter) {
        linkedCardID = nil

        if option.id == "all" {
            selectedLevelFilterIDs = ["all"]
            currentIndex = 0
            currentCardID = nil
            saveFilterSettings()
            lockCurrentCardIfNeeded()
            return
        }

        var ids = selectedLevelFilterIDs
        ids.remove("all")

        if ids.contains(option.id) {
            ids.remove(option.id)
        } else {
            ids.insert(option.id)
        }

        if ids.isEmpty {
            ids.insert("all")
        }

        selectedLevelFilterIDs = ids
        currentIndex = 0
        currentCardID = nil
        saveFilterSettings()
        lockCurrentCardIfNeeded()
    }

    private func matchesSelectedLevelFilters(_ level: String?) -> Bool {
        if selectedLevelFilterIDs.contains("all") || selectedLevelFilterIDs.isEmpty {
            return true
        }

        let filters = selectedLevelFilters
        return filters.contains { $0.matches(level) }
    }

    func addOrReplaceTag(name: String, kanjiIDs: [String], source: String? = nil) {
        let uniqueIDs = uniqueOrdered(kanjiIDs)
        if let index = tags.firstIndex(where: { $0.name == name }) {
            tags[index].kanjiIDs = uniqueIDs
            tags[index].source = source
            tags[index].createdAt = Date()
            selectedTagFilterID = tags[index].id
        } else {
            let tag = KanjiTag(name: name, kanjiIDs: uniqueIDs, source: source)
            tags.insert(tag, at: 0)
            selectedTagFilterID = tag.id
        }
        currentIndex = 0
        currentCardID = nil
        saveTags()
        saveFilterSettings()
        lastMessage = "タグ「\(name)」に \(uniqueIDs.count) 件を登録しました。"
    }

    func deleteTag(_ tag: KanjiTag) {
        tags.removeAll { $0.id == tag.id }
        if selectedTagFilterID == tag.id {
            selectedTagFilterID = "all"
        }
        saveTags()
        saveFilterSettings()
    }

    func resetFilters() {
        linkedCardID = nil
        selectedLevelFilterIDs = ["all"]
        selectedTagFilterID = "all"
        includeUntried = true
        includeReview = true
        includeMastered = false
        currentIndex = 0
        currentCardID = nil
        saveFilterSettings()
        lockCurrentCardIfNeeded()
    }

    func clearLinkedCard() {
        linkedCardID = nil
    }

    func filterDidChange() {
        linkedCardID = nil
        currentCardID = nil
        currentIndex = 0
        saveFilterSettings()
        lockCurrentCardIfNeeded()
    }

    func markCorrect(_ card: KanjiCard, retention: MasteryRetention) {
        let oldID = card.id
        let preferredNextID = nextCandidateID(after: oldID)
        setMastered(card, retention: retention)
        advanceAfterStateChange(oldID: oldID, preferredNextID: preferredNextID)
    }

    func markWrong(_ card: KanjiCard) {
        let oldID = card.id
        let preferredNextID = nextCandidateID(after: oldID)
        setStatus(.review, for: card)
        advanceAfterStateChange(oldID: oldID, preferredNextID: preferredNextID)
    }

    func setStatus(_ status: CardStudyStatus, for card: KanjiCard) {
        var review = reviewIDs
        var mastered = masteredIDs

        switch status {
        case .untried:
            review.remove(card.id)
            mastered.remove(card.id)
            masteredUntil.removeValue(forKey: card.id)
        case .review:
            mastered.remove(card.id)
            masteredUntil.removeValue(forKey: card.id)
            review.insert(card.id)
        case .mastered:
            review.remove(card.id)
            mastered.insert(card.id)
            masteredUntil.removeValue(forKey: card.id)
        }

        reviewIDs = review
        masteredIDs = mastered
        saveReviewIDs()
        saveMasteredIDs()
        saveMasteredUntil()
    }

    func setMastered(_ card: KanjiCard, retention: MasteryRetention) {
        var review = reviewIDs
        var mastered = masteredIDs
        var until = masteredUntil

        review.remove(card.id)
        mastered.insert(card.id)

        if let date = retention.nextReviewDate {
            until[card.id] = date.timeIntervalSince1970
        } else {
            until.removeValue(forKey: card.id)
        }

        reviewIDs = review
        masteredIDs = mastered
        masteredUntil = until

        saveReviewIDs()
        saveMasteredIDs()
        saveMasteredUntil()
    }

    func toggleReview(_ card: KanjiCard) {
        if reviewIDs.contains(card.id) {
            setStatus(.untried, for: card)
        } else {
            setStatus(.review, for: card)
        }
    }

    func resetReview() {
        linkedCardID = nil
        reviewIDs.removeAll()
        saveReviewIDs()
        currentIndex = 0
        lastMessage = "書けないリストを空にしました。"
    }

    func resetStudyState() {
        linkedCardID = nil
        reviewIDs.removeAll()
        masteredIDs.removeAll()
        masteredUntil.removeAll()
        saveReviewIDs()
        saveMasteredIDs()
        saveMasteredUntil()
        currentIndex = 0
        lastMessage = "出題状態をリセットしました。"
    }

    func next() {
        linkedCardID = nil
        let list = activeCards
        guard !list.isEmpty else {
            currentIndex = 0
            currentCardID = nil
            return
        }

        let baseIndex = currentActiveIndex(in: list) ?? min(currentIndex, list.count - 1)
        let newIndex = (baseIndex + 1) % list.count
        currentIndex = newIndex
        currentCardID = list[newIndex].id
    }

    func previous() {
        linkedCardID = nil
        let list = activeCards
        guard !list.isEmpty else {
            currentIndex = 0
            currentCardID = nil
            return
        }

        let baseIndex = currentActiveIndex(in: list) ?? min(currentIndex, list.count - 1)
        let newIndex = (baseIndex - 1 + list.count) % list.count
        currentIndex = newIndex
        currentCardID = list[newIndex].id
    }

    func jump(to card: KanjiCard) {
        // 絞り込み条件は変更しない。
        // 一覧からの遷移では、カードは activeCards 内にあるため、その添字へ移動する。
        // パーツリンクなどで現在の絞り込み外のカードへ飛ぶ場合は、一時表示として扱う。
        let list = activeCards

        if let index = list.firstIndex(where: { $0.id == card.id }) {
            linkedCardID = nil
            currentIndex = index
            currentCardID = card.id
        } else {
            linkedCardID = card.id
            currentCardID = nil
        }

        selectedTab = .practice
    }

    func jumpToKanji(_ kanji: String) {
        guard let card = card(forKanji: kanji) else { return }
        jump(to: card)
    }

    func card(forKanji kanji: String) -> KanjiCard? {
        cards.first(where: { $0.kanji == kanji })
    }

    func isKnownKanji(_ value: String) -> Bool {
        value.count == 1 && card(forKanji: value) != nil
    }

    func levelName(for level: String?) -> String {
        levelDisplayName(level)
    }

    func compactLevelName(for level: String?) -> String {
        switch level {
        case "S1": return "小1"
        case "S2": return "小2"
        case "S3": return "小3"
        case "S4": return "小4"
        case "S5": return "小5"
        case "S6": return "小6"
        case "JH": return "中"
        case "HS": return "高"
        case "GEN": return "般"
        case "J", "J1", "J2", "J3", "J4": return "他"
        default:
            let name = levelDisplayName(level)
            return name
                .replacingOccurrences(of: "小学", with: "小")
                .replacingOccurrences(of: "年生", with: "")
                .replacingOccurrences(of: "中学生", with: "中")
                .replacingOccurrences(of: "高校", with: "高")
                .replacingOccurrences(of: "一般", with: "般")
                .replacingOccurrences(of: "その他", with: "他")
        }
    }

    func compactStatusText(for card: KanjiCard) -> String {
        switch status(for: card) {
        case .untried:
            return "未出題"
        case .review:
            return "書けない"
        case .mastered:
            guard let timeInterval = masteredUntil[card.id] else {
                return "書ける：ずっと"
            }

            let nextDate = Date(timeIntervalSince1970: timeInterval)
            if nextDate <= Date() {
                return "書ける：再出題"
            }

            let days = Calendar.current.dateComponents([.day], from: Date(), to: nextDate).day ?? 0

            if days <= 1 {
                return "書ける：明日まで"
            }
            if days <= 8 {
                return "書ける：1週間後まで"
            }
            if days <= 32 {
                return "書ける：1か月後まで"
            }

            return "書ける：\(days)日後まで"
        }
    }

    func isMasteredDue(_ card: KanjiCard) -> Bool {
        guard masteredIDs.contains(card.id) else {
            return false
        }

        guard let timeInterval = masteredUntil[card.id] else {
            return false
        }

        return Date(timeIntervalSince1970: timeInterval) <= Date()
    }

    func masteryStatusText(for card: KanjiCard) -> String {
        guard masteredIDs.contains(card.id) else {
            return statusText(for: card)
        }

        guard let timeInterval = masteredUntil[card.id] else {
            return "書ける：ずっと"
        }

        let nextDate = Date(timeIntervalSince1970: timeInterval)
        if nextDate <= Date() {
            return "書ける：再出題"
        }

        let days = Calendar.current.dateComponents([.day], from: Date(), to: nextDate).day ?? 0

        if days <= 1 {
            return "書ける：明日"
        }
        if days <= 8 {
            return "書ける：約1週間"
        }
        if days <= 32 {
            return "書ける：約1か月"
        }

        return "書ける：\(days)日後"
    }

    func lockCurrentCardIfNeeded() {
        guard linkedCardID == nil else { return }
        let list = activeCards
        guard !list.isEmpty else {
            currentIndex = 0
            currentCardID = nil
            return
        }

        if let currentCardID,
           let index = list.firstIndex(where: { $0.id == currentCardID }) {
            currentIndex = index
            return
        }

        let index = min(currentIndex, list.count - 1)
        currentIndex = index
        currentCardID = list[index].id
    }

    private func currentActiveIndex(in list: [KanjiCard]? = nil) -> Int? {
        let list = list ?? activeCards
        if let currentCardID,
           let index = list.firstIndex(where: { $0.id == currentCardID }) {
            return index
        }
        if currentIndex >= 0 && currentIndex < list.count {
            return currentIndex
        }
        return nil
    }

    private func nextCandidateID(after oldID: String) -> String? {
        let list = activeCards
        guard !list.isEmpty else { return nil }
        guard let oldIndex = list.firstIndex(where: { $0.id == oldID }) else {
            return currentCardID
        }
        if list.count == 1 { return nil }
        return list[(oldIndex + 1) % list.count].id
    }

    private func advanceAfterStateChange(oldID: String, preferredNextID: String?) {
        linkedCardID = nil
        let list = activeCards

        guard !list.isEmpty else {
            currentIndex = 0
            currentCardID = nil
            return
        }

        if let preferredNextID,
           let index = list.firstIndex(where: { $0.id == preferredNextID }) {
            currentIndex = index
            currentCardID = preferredNextID
            return
        }

        if let index = list.firstIndex(where: { $0.id == oldID }) {
            currentIndex = index
            currentCardID = oldID
            return
        }

        let index = min(currentIndex, list.count - 1)
        currentIndex = index
        currentCardID = list[index].id
    }

    private func sortedActiveCards(_ input: [KanjiCard]) -> [KanjiCard] {
        var originalIndex: [String: Int] = [:]
        for (offset, card) in cards.enumerated() where originalIndex[card.id] == nil {
            originalIndex[card.id] = offset
        }

        let originalOrder: (KanjiCard, KanjiCard) -> Bool = { lhs, rhs in
            (originalIndex[lhs.id] ?? Int.max) < (originalIndex[rhs.id] ?? Int.max)
        }

        let sorted: [KanjiCard]
        switch sortOrder {
        case .original:
            sorted = input.sorted(by: originalOrder)
        case .tagFrequency:
            if let selectedTag {
                var tagIndex: [String: Int] = [:]
                for (offset, id) in selectedTag.kanjiIDs.enumerated() where tagIndex[id] == nil {
                    tagIndex[id] = offset
                }
                sorted = input.sorted { lhs, rhs in
                    let li = tagIndex[lhs.id] ?? Int.max
                    let ri = tagIndex[rhs.id] ?? Int.max
                    if li != ri { return li < ri }
                    return originalOrder(lhs, rhs)
                }
            } else {
                sorted = input.sorted(by: originalOrder)
            }
        case .level:
            sorted = input.sorted { lhs, rhs in
                let lr = kanjiLevelSortRank(lhs.level)
                let rr = kanjiLevelSortRank(rhs.level)
                if lr != rr { return lr < rr }
                return originalOrder(lhs, rhs)
            }
        case .kanji:
            sorted = input.sorted { lhs, rhs in
                if lhs.kanji != rhs.kanji { return lhs.kanji < rhs.kanji }
                return originalOrder(lhs, rhs)
            }
        }

        guard prioritizeAnswered else {
            return sorted
        }

        return sorted.enumerated()
            .sorted { lhs, rhs in
                let lp = answeredPriorityRank(for: lhs.element)
                let rp = answeredPriorityRank(for: rhs.element)
                if lp != rp { return lp < rp }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    private func answeredPriorityRank(for card: KanjiCard) -> Int {
        switch status(for: card) {
        case .review, .mastered:
            return 0
        case .untried:
            return 1
        }
    }

    private func loadSortOrder() {
        let raw = UserDefaults.standard.string(forKey: sortOrderKey) ?? KanjiSortOrder.original.rawValue
        sortOrder = KanjiSortOrder(rawValue: raw) ?? .original
    }

    private func saveSortOrder() {
        UserDefaults.standard.set(sortOrder.rawValue, forKey: sortOrderKey)
    }

    private func loadPrioritizeAnswered() {
        if UserDefaults.standard.object(forKey: prioritizeAnsweredKey) == nil {
            prioritizeAnswered = true
        } else {
            prioritizeAnswered = UserDefaults.standard.bool(forKey: prioritizeAnsweredKey)
        }
    }

    private func savePrioritizeAnswered() {
        UserDefaults.standard.set(prioritizeAnswered, forKey: prioritizeAnsweredKey)
    }

    private func validateImportedCards(_ importedCards: [KanjiCard]) throws {
        guard !importedCards.isEmpty else {
            throw KanjiImportError.empty
        }

        var seenIDs = Set<String>()
        var seenKanji = Set<String>()

        for (index, card) in importedCards.enumerated() {
            let line = index + 1

            if card.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw KanjiImportError.invalid("\(line)件目: idが空です。")
            }
            if card.kanji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw KanjiImportError.invalid("\(line)件目: kanjiが空です。")
            }
            if card.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw KanjiImportError.invalid("\(line)件目（\(card.kanji)）: questionが空です。")
            }
            if card.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw KanjiImportError.invalid("\(line)件目（\(card.kanji)）: targetTextが空です。")
            }
            if card.question.components(separatedBy: "{target}").count - 1 != 1 {
                throw KanjiImportError.invalid("\(line)件目（\(card.kanji)）: question内の{target}は1個にしてください。")
            }
            if seenIDs.contains(card.id) {
                throw KanjiImportError.invalid("\(line)件目（\(card.kanji)）: idが重複しています: \(card.id)")
            }
            if seenKanji.contains(card.kanji) {
                throw KanjiImportError.invalid("\(line)件目: 漢字が重複しています: \(card.kanji)")
            }

            seenIDs.insert(card.id)
            seenKanji.insert(card.kanji)
        }
    }

    private func uniqueOrdered(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            if !seen.contains(value) {
                seen.insert(value)
                result.append(value)
            }
        }

        return result
    }
}

enum MasteryRetention: CaseIterable, Identifiable {
    case tomorrow
    case week
    case month
    case permanent

    var id: String {
        switch self {
        case .tomorrow: return "tomorrow"
        case .week: return "week"
        case .month: return "month"
        case .permanent: return "permanent"
        }
    }

    var title: String {
        switch self {
        case .tomorrow: return "明日"
        case .week: return "1週間後"
        case .month: return "1か月後"
        case .permanent: return "ずっと"
        }
    }

    var nextReviewDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: Date())
        case .week:
            return calendar.date(byAdding: .day, value: 7, to: Date())
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: Date())
        case .permanent:
            return nil
        }
    }
}

enum CardStudyStatus {
    case untried
    case review
    case mastered
}

enum KanjiImportError: LocalizedError {
    case empty
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "JSONに漢字データがありません。"
        case .invalid(let message):
            return message
        }
    }
}
