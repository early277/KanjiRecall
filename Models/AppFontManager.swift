import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppFontManager: ObservableObject {
    static let shared = AppFontManager()

    @Published private(set) var effectiveFontDisplayName: String = "標準: HiraMinProN-W6"

    private let selectedFontNameKey = "kanji_selected_system_font_name_v1"
    private let selectedFontDisplayKey = "kanji_selected_system_font_display_v1"

    private var selectedSystemFontName: String?

    private init() {
        selectedSystemFontName = UserDefaults.standard.string(forKey: selectedFontNameKey)

        if let selectedSystemFontName {
            let display = UserDefaults.standard.string(forKey: selectedFontDisplayKey) ?? selectedSystemFontName
            effectiveFontDisplayName = "選択: \(display)"
        }
    }

    func font(size: CGFloat) -> Font {
        if let selectedSystemFontName {
            return .custom(selectedSystemFontName, size: size)
        }

        return .custom("HiraMinProN-W6", size: size)
    }

    func selectSystemFont(fontName: String, displayName: String) {
        selectedSystemFontName = fontName
        effectiveFontDisplayName = "選択: \(displayName)"
        UserDefaults.standard.set(fontName, forKey: selectedFontNameKey)
        UserDefaults.standard.set(displayName, forKey: selectedFontDisplayKey)
    }

    func useDefaultFont() {
        selectedSystemFontName = nil
        effectiveFontDisplayName = "標準: HiraMinProN-W6"
        UserDefaults.standard.removeObject(forKey: selectedFontNameKey)
        UserDefaults.standard.removeObject(forKey: selectedFontDisplayKey)
    }
}
