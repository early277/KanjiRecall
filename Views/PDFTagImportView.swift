import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct PDFTagImportView: View {
    private enum PDFTagFocusedField: Hashable {
        case tagName
        case topCount
    }
    @EnvironmentObject private var store: KanjiStore

    @State private var isImporterPresented = false
    @State private var extracted: [ExtractedKanji] = []
    @State private var selectedTopCount: Int = 20
    @State private var selectedTopText: String = "20"
    @State private var tagName: String = ""
    @State private var sourceName: String = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: PDFTagFocusedField?

    private var selectedRegistered: [ExtractedKanji] {
        Array(extracted.prefix(selectedTopCount)).filter { $0.isRegistered }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("PDFタグは、PDFに頻出する漢字を自動で集めてタグ化し、その文書でよく出る漢字だけを重点的に練習するための機能です。")
                            .font(.body)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("使い方")
                                .font(.headline)
                            Text("1. PDFを選ぶ")
                            Text("2. PDF内の漢字を出現回数順に並べる")
                            Text("3. 上位何字までタグに入れるか決める")
                            Text("4. 作成したタグを練習画面のフィルターで使う")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 14) {
                        Text("PDF読込")
                            .font(.headline)

                        Button {
                            isImporterPresented = true
                        } label: {
                            Label("PDFを選択", systemImage: "doc")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Divider()

                        Text("PDFのテキスト層のみ読み込みます。スキャン画像PDFのOCRは行いません。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    if !extracted.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("タグ作成")
                                .font(.headline)

                            TextField("タグ名", text: $tagName)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .tagName)
                                .submitLabel(.done)
                                .onSubmit {
                                    dismissKeyboard()
                                }

                            HStack {
                                Text("上位")
                                TextField("件数", text: $selectedTopText)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                                    .onChange(of: selectedTopText) { applyTopCountText()
                                    }
                                Text("字まで")
                                Spacer()
                                Stepper("", value: $selectedTopCount, in: 1...max(1, extracted.count))
                                    .labelsHidden()
                                    .onChange(of: selectedTopCount) { _, value in
                                        selectedTopText = String(value)
                                   
                                    }
                            }

                            HStack {
                                Text("登録済み対象")
                                Spacer()
                                Text("\(selectedRegistered.count) 字")
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                createTag()
                            } label: {
                                Label("この範囲でタグを作成", systemImage: "tag")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedRegistered.isEmpty || tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Text("出現回数順。上から指定した件数までをタグ対象にします。アプリに漢字データがない字は「未登録」と表示します。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                        LazyVStack(spacing: 10) {
                            ForEach(Array(extracted.enumerated()), id: \.element.id) { index, item in
                                HStack {
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, alignment: .trailing)

                                    Text(item.kanji)
                                        .font(.title.bold())
                                        .frame(width: 44)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("\(item.count) 回")
                                                .font(.subheadline.monospacedDigit())

                                            if let level = item.level {
                                                Text(store.levelName(for: level))
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.blue.opacity(0.12))
                                                    .clipShape(Capsule())
                                            }
                                        }

                                        if item.isRegistered {
                                            Text("登録あり")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                        } else {
                                            Text("未登録")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if index < selectedTopCount {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(item.isRegistered ? .green : .gray)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }

                    if let errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("エラー")
                                .font(.headline)
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding()
                .padding(.bottom, 100)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("PDFタグ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        dismissKeyboard()
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                importPDF(result)
            }
        }
    }

    private func importPDF(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let result = try extractKanji(from: url)
            extracted = result
            selectedTopCount = min(20, max(1, result.count))
            selectedTopText = String(selectedTopCount)
            sourceName = url.lastPathComponent
            tagName = defaultTagName(from: url.lastPathComponent)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func extractKanji(from url: URL) throws -> [ExtractedKanji] {
        guard let document = PDFDocument(url: url) else {
            throw NSError(domain: "PDF", code: 1, userInfo: [NSLocalizedDescriptionKey: "PDFを開けませんでした。"])
        }

        var counts: [String: Int] = [:]

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let text = page.string else {
                continue
            }

            for scalar in text.unicodeScalars {
                if isCJKUnifiedIdeograph(scalar) {
                    let ch = String(Character(scalar))
                    counts[ch, default: 0] += 1
                }
            }
        }

        return counts
            .map { key, value in
                let card = store.card(forKanji: key)
                return ExtractedKanji(kanji: key, count: value, cardID: card?.id, level: card?.level)
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.kanji < rhs.kanji
            }
    }

    private func createTag() {
        applyTopCountText()
        let name = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = selectedRegistered.compactMap { $0.cardID }
        store.addOrReplaceTag(name: name, kanjiIDs: ids, source: sourceName)
        store.selectedTab = .filter
    }

    private func applyTopCountText() {
        let maxValue = max(1, extracted.count)
        guard let value = Int(selectedTopText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        selectedTopCount = min(max(value, 1), maxValue)
        if String(selectedTopCount) != selectedTopText {
            selectedTopText = String(selectedTopCount)
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func defaultTagName(from filename: String) -> String {
        filename
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            .prefix(24)
            .description
    }

    private func isCJKUnifiedIdeograph(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value
        return (0x3400...0x4DBF).contains(v)
            || (0x4E00...0x9FFF).contains(v)
            || (0xF900...0xFAFF).contains(v)
            || (0x20000...0x2A6DF).contains(v)
            || (0x2A700...0x2B73F).contains(v)
            || (0x2B740...0x2B81F).contains(v)
            || (0x2B820...0x2CEAF).contains(v)
            || (0x2CEB0...0x2EBEF).contains(v)
            || (0x30000...0x3134F).contains(v)
    }
}
