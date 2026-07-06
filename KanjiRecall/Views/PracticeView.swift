import SwiftUI
import AVFoundation
import UIKit

struct PracticeView: View {
    @EnvironmentObject private var store: KanjiStore

    @State private var showAnswer = false
    @State private var showPartsHint = false
    @State private var clearSignal = 0
    @State private var lookupTerm: LookupTerm?
    @State private var pendingMasteredCard: KanjiCard?
    @State private var showMasteryPicker = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 10) {
                    header

                    if let card = store.currentCard {
                        answerOrQuestionCard(card)
                            .frame(maxWidth: .infinity, minHeight: 104)
                            .padding(.horizontal)

                        if showPartsHint, !card.parts.isEmpty, !showAnswer {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("パーツヒント")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                PartChipsView(parts: card.parts)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                        }

                        Spacer(minLength: 4)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("手書き欄")
                                    .font(.headline)
                                Spacer()
                                Button("クリア") {
                                    clearSignal += 1
                                }
                                .buttonStyle(.bordered)
                            }

                            PencilCanvasView(clearSignal: clearSignal)
                                .frame(height: canvasHeight(for: geometry.size.height, showingParts: showPartsHint && !showAnswer && !card.parts.isEmpty))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal)

                        HStack(spacing: 10) {
                            if showAnswer {
                                Button {
                                    showAnswer = false
                                } label: {
                                    Label("答えを隠す", systemImage: "eye.slash")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button {
                                    showPartsHint.toggle()
                                } label: {
                                    Label(showPartsHint ? "パーツを隠す" : "パーツを表示", systemImage: "square.grid.2x2")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(card.parts.isEmpty)

                                Button {
                                    showAnswer = true
                                    showPartsHint = false
                                } label: {
                                    Label("答えを見る", systemImage: "eye")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.horizontal)

                        HStack(spacing: 8) {
                            Button {
                                store.previous()
                                resetCardUI()
                            } label: {
                                Label("前へ", systemImage: "chevron.left")
                                    .labelStyle(.titleAndIcon)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .buttonStyle(.bordered)
                            .font(.subheadline)

                            Button {
                                store.next()
                                resetCardUI()
                            } label: {
                                Label("次へ", systemImage: "chevron.right")
                                    .labelStyle(.titleAndIcon)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .buttonStyle(.bordered)
                            .font(.subheadline)

                            Spacer(minLength: 4)

                            Button {
                                store.markWrong(card)
                                resetCardUI()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "bookmark.fill")
                                    Text("書けない")
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .minimumScaleFactor(0.75)
                                }
                            }
                            .buttonStyle(.bordered)
                            .font(.subheadline)

                            Button {
                                pendingMasteredCard = card
                                showMasteryPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle")
                                    Text("書ける")
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.subheadline)
                        }
                        .padding(.horizontal)
                    } else {
                        Spacer()

                        ContentUnavailableView(
                            "条件に合う漢字がありません",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("絞り込みタブで条件を変更してください。")
                        )

                        Button {
                            store.selectedTab = .filter
                        } label: {
                            Label("絞り込みへ", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()
                    }
                }
                .padding(.bottom, 8)
            }
            .navigationTitle("漢字練習")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.selectedTab = .filter
                    } label: {
                        Label("絞り込み", systemImage: "line.3.horizontal.decrease.circle")
                    }
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.filterSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(store.progressText)
                    Text("対象 \(store.activeCards.count)")
                    Text("書けない \(store.reviewIDs.count)")
                        .foregroundStyle(.orange)
                    Text("書ける \(store.masteredIDs.count)")
                        .foregroundStyle(.green)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func answerOrQuestionCard(_ card: KanjiCard) -> some View {
        if showAnswer {
            AnswerTopCard(card: card, isReview: store.reviewIDs.contains(card.id)) {
                lookupTerm = LookupTerm(text: card.kanji)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                QuestionTextView(card: card)
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    SpeechService.shared.speak(card.questionForSpeech)
                } label: {
                    Image(systemName: "speaker.wave.2.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("問題文を読み上げる")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func canvasHeight(for totalHeight: CGFloat, showingParts: Bool) -> CGFloat {
        let base = totalHeight * (showingParts ? 0.34 : 0.43)
        return min(max(base, 250), 380)
    }

    private func applyMastery(_ retention: MasteryRetention) {
        guard let card = pendingMasteredCard ?? store.currentCard else { return }
        store.markCorrect(card, retention: retention)
        pendingMasteredCard = nil
        showMasteryPicker = false
        resetCardUI()
    }

    private func resetCardUI() {
        showAnswer = false
        showPartsHint = false
        clearSignal += 1
        if store.currentIndex >= store.activeCards.count {
            store.currentIndex = 0
        }
    }
}

struct AnswerTopCard: View {
    @EnvironmentObject private var store: KanjiStore
    let card: KanjiCard
    let isReview: Bool
    let onLookup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                TextbookKanjiText(card.kanji, size: 84)

                VStack(alignment: .leading, spacing: 6) {
                    Text(card.targetText)
                        .font(.title3.bold())
                        .textSelection(.enabled)

                    Text(store.levelName(for: card.level))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(store.statusText(for: card))
                        .font(.caption)
                        .foregroundStyle(statusColor)

                    LookupButton(text: card.kanji) {
                        onLookup()
                    }
                }

                Spacer()

                Button {
                    SpeechService.shared.speak(card.questionForSpeech)
                } label: {
                    Image(systemName: "speaker.wave.2.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("問題文を読み上げる")

                if isReview {
                    Label("書けない", systemImage: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if !card.parts.isEmpty {
                PartChipsView(parts: card.parts)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var statusColor: Color {
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

struct TextbookKanjiText: View {
    @ObservedObject private var fontManager = AppFontManager.shared

    let text: String
    let size: CGFloat

    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(fontManager.font(size: size))
            .fontWeight(.bold)
            .textSelection(.enabled)
    }
}


final class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }
}


struct LookupTerm: Identifiable {
    let id = UUID()
    let text: String
}

struct ReferenceLookupView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ uiViewController: UIReferenceLibraryViewController, context: Context) {
    }
}

struct LookupButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label("調べる", systemImage: "book")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption)
        .accessibilityLabel("\(text)を調べる")
    }
}


struct MasteryRetentionBottomPicker: View {
    let onSelect: (MasteryRetention) -> Void
    let onCancel: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 44, height: 5)

            Text("いつ頃まで書けそうですか？")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(MasteryRetention.allCases) { retention in
                    Button {
                        onSelect(retention)
                    } label: {
                        Text(retention.title)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Button("キャンセル", role: .cancel) {
                onCancel()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .padding(.bottom, 6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(radius: 12)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
