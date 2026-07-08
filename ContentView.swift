import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: KanjiStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            PracticeView()
                .tabItem {
                    Label("練習", systemImage: "pencil.and.outline")
                }
                .tag(AppTab.practice)

            FilterView()
                .tabItem {
                    Label("絞り込み", systemImage: "line.3.horizontal.decrease.circle")
                }
                .tag(AppTab.filter)

            CardListView()
                .tabItem {
                    Label("一覧", systemImage: "list.bullet")
                }
                .tag(AppTab.list)

            PDFTagImportView()
                .tabItem {
                    Label("PDFタグ", systemImage: "doc.text.magnifyingglass")
                }
                .tag(AppTab.pdf)

            TagListView()
                .tabItem {
                    Label("タグ", systemImage: "tag")
                }
                .tag(AppTab.tag)

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
    }
}

struct FilterView: View {
    @EnvironmentObject private var store: KanjiStore
    @State private var isLevelSheetPresented = false

    private var levelSummary: String {
        let selected = store.selectedLevelFilters.filter { $0.id != "all" }
        if selected.isEmpty {
            return "すべて"
        }
        return selected.map { $0.title }.joined(separator: "・")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("ここで選んだ条件が、練習タブと一覧タブの表示対象になります。レベル・タグ・状態は重ねがけできます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("現在の対象")
                        Spacer()
                        Text("\(store.activeCards.count) 字")
                            .font(.headline.monospacedDigit())
                    }

                    Text(store.filterSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("出題条件")
                }

                Section("レベル") {
                    Button {
                        isLevelSheetPresented = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("レベルを選択")
                                    .foregroundStyle(.primary)
                                Text(levelSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("レベルは別画面で複数選択し、「決定」を押した時点で反映します。選択のたびに一覧を更新しないため、動作が重くなりにくくなります。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("タグ") {
                    Picker("タグ", selection: $store.selectedTagFilterID) {
                        Text("すべて").tag("all")
                        ForEach(store.tags) { tag in
                            Text("\(tag.name) (\(tag.kanjiIDs.count))").tag(tag.id)
                        }
                    }
                    .disabled(store.tags.isEmpty)

                    if store.tags.isEmpty {
                        Text("PDFタグ画面またはタグ画面でタグを作成すると選択できます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }


                Section("並び順") {
                    Picker("並び順", selection: $store.sortOrder) {
                        ForEach(KanjiSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }

                    Toggle("回答済みを先に表示", isOn: $store.prioritizeAnswered)

                    Text("初期順はJSONに入っている順です。タグ頻度順はPDFタグ作成時の出現回数順を使います。漢字コード順は読み順ではなく文字コード順です。回答済みを先に表示すると、書ける・書けないを選んだ漢字を未出題より前に出します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("状態") {
                    Toggle("未出題を出す", isOn: $store.includeUntried)
                    Toggle("書けない問題を出す", isOn: $store.includeReview)
                    Toggle("書ける問題も出す", isOn: $store.includeMastered)

                    Text("初期設定では、書ける問題は出題しません。必要なときだけ「書ける問題も出す」をONにしてください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        store.resetFilters()
                    } label: {
                        Label("絞り込みをリセット", systemImage: "arrow.counterclockwise")
                    }

                    Button {
                        store.selectedTab = .practice
                    } label: {
                        Label("この条件で練習へ", systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("絞り込み")
            .sheet(isPresented: $isLevelSheetPresented) {
                LevelSelectionSheet()
                    .environmentObject(store)
            }
            .onChange(of: store.selectedTagFilterID) { store.filterDidChange() }
            .onChange(of: store.includeUntried) { store.filterDidChange() }
            .onChange(of: store.includeReview) { store.filterDidChange() }
            .onChange(of: store.includeMastered) { store.filterDidChange() }
        }
    }
}

struct LevelSelectionSheet: View {
    @EnvironmentObject private var store: KanjiStore
    @Environment(\.dismiss) private var dismiss
    @State private var draftIDs: Set<String> = ["all"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.levelFilterOptions) { option in
                        Button {
                            toggle(option)
                        } label: {
                            HStack {
                                Text(option.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if draftIDs.contains(option.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("レベル")
                } footer: {
                    Text("選択内容は「決定」を押すまで反映されません。")
                }
            }
            .navigationTitle("レベルを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        store.applyLevelFilters(draftIDs)
                        dismiss()
                    }
                }
            }
            .onAppear {
                draftIDs = store.selectedLevelFilterIDs
                if draftIDs.isEmpty {
                    draftIDs = ["all"]
                }
            }
        }
    }

    private func toggle(_ option: KanjiLevelFilter) {
        if option.id == "all" {
            draftIDs = ["all"]
            return
        }

        draftIDs.remove("all")

        if draftIDs.contains(option.id) {
            draftIDs.remove(option.id)
        } else {
            draftIDs.insert(option.id)
        }

        if draftIDs.isEmpty {
            draftIDs = ["all"]
        }
    }
}

