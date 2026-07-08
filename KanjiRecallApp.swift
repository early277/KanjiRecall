import SwiftUI

@main
struct KanjiRecallApp: App {
    @StateObject private var store = KanjiStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
