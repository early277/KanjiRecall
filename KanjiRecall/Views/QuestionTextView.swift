import SwiftUI

struct QuestionTextView: View {
    let card: KanjiCard

    var body: some View {
        composedText
            .lineSpacing(6)
            .textSelection(.enabled)
    }

    private var composedText: Text {
        let parts = card.question.components(separatedBy: "{target}")

        if parts.count == 2 {
            return Text(parts[0])
                + Text(card.targetText)
                    .foregroundColor(.red)
                    .bold()
                + Text(parts[1])
        }

        return Text(card.question)
    }
}
