import SwiftUI
import UniformTypeIdentifiers

struct KanjiCardsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(cards: [KanjiCard]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.data = (try? encoder.encode(cards)) ?? Data("[]".utf8)
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
