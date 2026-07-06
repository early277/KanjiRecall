import SwiftUI

struct CardListView: View {
    @EnvironmentObject private var store: KanjiStore
    @State private var searchText = ""
    @State private var lookupTerm: LookupTerm?
    @State private var pendingMasteredCard: KanjiCard?
    @State private var showMasteryPicker = false

    private var filteredCards: [KanjiCard] {
        let baseCards = store.activeCards
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return baseCards }

        return baseCards.filter {
            $0.kanji.contains(text)
            || $0.targetText.contains(text)
            || $0.question.contains(text)
            || ($0.level?.contains(text) ?? false)
            || store.levelName(for: $0.level).contains(text)
            || $0.parts.joined(separator: " ").contains(text)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("絞り込み対象: \(filteredCards.count) 字 / \(store.filterSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(filteredCards) { card in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 6) {
                                TextbookKanjiText(card.kanji, size: 44)
                                    .frame(width: 48)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        store.jump(to: card)
                                    }

                                LookupButton(text: card.kanji) {
                                    lookupTerm = LookupTerm(text: card.kanji)
                                }

                                Text(store.levelName(for: card.level))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                QuestionTextView(card: card)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        store.jump(to: card)
                                    }

                                HStack(spacing: 6) {
                                    Text(store.compactStatusText(for: card))
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(statusBackground(for: card), in: Capsule())
                                        .foregroundStyle(statusForeground(for: card))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .layoutPriority(1)

                                    Spacer(minLength: 0)
                                }
                            }

                            Spacer(minLength: 4)

                            Button {
                                SpeechService.shared.speak(card.questionForSpeech)
                            } label: {
                                Image(systemName: "speaker.wave.2.circle")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("問題文を読み上げる")

                            StatusIconSelector(card: card) {
                                pendingMasteredCard = card
                                showMasteryPicker = true
                            }
                        }

                        if !card.parts.isEmpty {
                            PartChipsView(parts: card.parts, showLinkIcon: false)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("漢字一覧")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "漢字・読み・文・パーツで検索")
            .overlay {
                if store.cards.isEmpty {
                    ContentUnavailableView("データがありません", systemImage: "tray")
                } else if filteredCards.isEmpty {
                    ContentUnavailableView("条件に合う漢字がありません", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            .sheet(item: $lookupTerm) { item in
                ReferenceLookupView(term: item.text)
            }
            .overlay(alignment: .bottom) {
                if showMasteryPicker {
                    MasteryRetentionBottomPicker(
                        onSelect: { retention in
                            applyMastery(retention)
                        },
                        onCancel: {
                            pendingMasteredCard = nil
                            showMasteryPicker = false
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: showMasteryPicker)
        }
    }

    private func statusBackground(for card: KanjiCard) -> Color {
        switch store.status(for: card) {
        case .untried:
            return Color.clear
        case .review:
            return Color.orange.opacity(0.16)
        case .mastered:
            return Color.green.opacity(0.16)
        }
    }

    private func statusForeground(for card: KanjiCard) -> Color {
        switch store.status(for: card) {
        case .untried:
            return Color.secondary
        case .review:
            return Color.orange
        case .mastered:
            return Color.green
        }
    }

    private func applyMastery(_ retention: MasteryRetention) {
        guard let card = pendingMasteredCard else { return }
        store.setMastered(card, retention: retention)
        pendingMasteredCard = nil
        showMasteryPicker = false
    }

    private func statusColor(for card: KanjiCard) -> Color {
        switch store.status(for: card) {
        case .untried:
            return .secondary
        case .review:
            return .orange
        case .mastered:
            return .green
        }
    }
}

struct StatusIconSelector: View {
    @EnvironmentObject private var store: KanjiStore
    let card: KanjiCard
    let onMastered: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            statusButton(
                status: .untried,
                kind: .text("未"),
                color: .secondary,
                accessibilityLabel: "未出題"
            )

            statusButton(
                status: .review,
                kind: .systemImage("bookmark", selected: "bookmark.fill"),
                color: .orange,
                accessibilityLabel: "書けない"
            )

            statusButton(
                status: .mastered,
                kind: .systemImage("checkmark.circle", selected: "checkmark.circle.fill"),
                color: .green,
                accessibilityLabel: "書ける"
            )
        }
        .padding(4)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(Capsule())
    }

    private enum StatusButtonKind {
        case systemImage(String, selected: String)
        case text(String)
    }

    @ViewBuilder
    private func statusButton(
        status: CardStudyStatus,
        kind: StatusButtonKind,
        color: Color,
        accessibilityLabel: String
    ) -> some View {
        let selected = store.status(for: card) == status

        Button {
            if status == .mastered {
                onMastered()
            } else {
                store.setStatus(status, for: card)
            }
        } label: {
            Group {
                switch kind {
                case .systemImage(let image, let selectedImage):
                    Image(systemName: selected ? selectedImage : image)
                        .font(.title3)
                case .text(let text):
                    Text(text)
                        .font(.caption.bold())
                }
            }
            .frame(width: 30, height: 30)
            .foregroundStyle(selected ? color : .secondary)
            .background(selected ? color.opacity(0.18) : Color.clear)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(selected ? color.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
