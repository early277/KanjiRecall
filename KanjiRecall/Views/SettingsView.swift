import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: KanjiStore
    @ObservedObject private var fontManager = AppFontManager.shared

    @State private var errorMessage: String?
    @State private var pendingAction: ConfirmAction?
    @State private var showConfirmAlert = false
    @State private var isSystemFontPickerPresented = false

    enum ConfirmAction {
        case resetReview
        case resetStudyState

        var title: String {
            switch self {
            case .resetReview:
                return "書けないリストを空にしますか？"
            case .resetStudyState:
                return "出題状態をすべてリセットしますか？"
            }
        }

        var message: String {
            switch self {
            case .resetReview:
                return "書けない状態の記録だけを空にします。書ける状態は残ります。"
            case .resetStudyState:
                return "未出題・書けない・書けるの状態記録をすべてリセットします。漢字データ自体は消えません。"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("データ") {
                    HStack {
                        Text("収録件数")
                        Spacer()
                        Text("\(store.cards.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("レベル分類")
                        Spacer()
                        Text("\(max(store.levelFilterOptions.count - 1, 0))")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("タグ数")
                        Spacer()
                        Text("\(store.tags.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("書けない件数")
                        Spacer()
                        Text("\(store.reviewIDs.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("書ける件数")
                        Spacer()
                        Text("\(store.masteredIDs.count)")
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        requestConfirmation(.resetReview)
                    } label: {
                        Label("書けないリストを空にする", systemImage: "trash")
                    }

                    Button(role: .destructive) {
                        requestConfirmation(.resetStudyState)
                    } label: {
                        Label("出題状態をすべてリセット", systemImage: "arrow.counterclockwise.circle")
                    }
                }

                Section("漢字表示フォント") {
                    HStack {
                        Text("現在のフォント")
                        Spacer()
                        Text(fontManager.effectiveFontDisplayName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Button {
                        isSystemFontPickerPresented = true
                    } label: {
                        Label("端末内フォントから選択", systemImage: "textformat")
                    }

                    Button {
                        fontManager.useDefaultFont()
                        store.lastMessage = "標準フォントに戻しました。"
                    } label: {
                        Label("標準フォントに戻す", systemImage: "arrow.uturn.backward")
                    }

                    Text("教科書体に近い表示にしたい場合は、iOSの設定アプリでフォントを追加したうえで、「端末内フォントから選択」から選んでください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("iOSの「マイフォント」に表示されていても、標準のフォント選択画面に出ないフォントは、このアプリから直接選べない場合があります。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !store.lastMessage.isEmpty {
                    Section("状態") {
                        Text(store.lastMessage)
                    }
                }

                if let errorMessage {
                    Section("エラー") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("設定")
            .sheet(isPresented: $isSystemFontPickerPresented) {
                SystemFontPickerView { fontName, displayName in
                    fontManager.selectSystemFont(fontName: fontName, displayName: displayName)
                    store.lastMessage = "フォントを「\(displayName)」に設定しました。"
                }
            }
            .alert(
                pendingAction?.title ?? "確認",
                isPresented: $showConfirmAlert,
                presenting: pendingAction
            ) { action in
                Button("実行する", role: .destructive) {
                    perform(action)
                }
                Button("キャンセル", role: .cancel) {
                    pendingAction = nil
                }
            } message: { action in
                Text(action.message)
            }
        }
    }

    private func requestConfirmation(_ action: ConfirmAction) {
        pendingAction = action
        showConfirmAlert = true
    }

    private func perform(_ action: ConfirmAction) {
        switch action {
        case .resetReview:
            store.resetReview()
        case .resetStudyState:
            store.resetStudyState()
        }
        pendingAction = nil
    }
}


struct SystemFontPickerView: UIViewControllerRepresentable {
    let onPick: (String, String) -> Void

    func makeUIViewController(context: Context) -> UIFontPickerViewController {
        let configuration = UIFontPickerViewController.Configuration()
        configuration.includeFaces = true

        let controller = UIFontPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIFontPickerViewController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        let onPick: (String, String) -> Void

        init(onPick: @escaping (String, String) -> Void) {
            self.onPick = onPick
        }

        func fontPickerViewControllerDidPickFont(_ viewController: UIFontPickerViewController) {
            guard let descriptor = viewController.selectedFontDescriptor else {
                viewController.dismiss(animated: true)
                return
            }

            let font = UIFont(descriptor: descriptor, size: 17)
            let displayName = font.familyName == font.fontName
                ? font.fontName
                : "\(font.familyName) / \(font.fontName)"

            onPick(font.fontName, displayName)
            viewController.dismiss(animated: true)
        }

        func fontPickerViewControllerDidCancel(_ viewController: UIFontPickerViewController) {
            viewController.dismiss(animated: true)
        }
    }
}
