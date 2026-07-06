import SwiftUI

struct TagListView: View {
    @EnvironmentObject private var store: KanjiStore

    var body: some View {
        NavigationStack {
            List {
                if store.tags.isEmpty {
                    ContentUnavailableView("タグがありません", systemImage: "tag")
                } else {
                    ForEach(store.tags) { tag in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(tag.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(tag.kanjiIDs.count) 字")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            if let source = tag.source {
                                Text(source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(tag.kanjiIDs.compactMap { id in
                                store.cards.first(where: { $0.id == id })?.kanji
                            }.joined())
                            .font(.body)
                            .lineLimit(2)

                            HStack {
                                Button {
                                    store.clearLinkedCard()
                                    store.selectedTagFilterID = tag.id
                                    store.currentIndex = 0
                                    store.saveFilterSettings()
                                    store.selectedTab = .practice
                                } label: {
                                    Label("このタグで練習", systemImage: "play.circle")
                                }
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    store.deleteTag(tag)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("タグ")
        }
    }
}
