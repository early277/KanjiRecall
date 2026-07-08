import SwiftUI
import UIKit

struct PencilCanvasView: UIViewRepresentable {
    let clearSignal: Int

    func makeUIView(context: Context) -> SimpleDrawingView {
        let view = SimpleDrawingView()
        view.lineWidth = 6
        view.applyAppearance(for: view.traitCollection)
        context.coordinator.lastClearSignal = clearSignal
        return view
    }

    func updateUIView(_ uiView: SimpleDrawingView, context: Context) {
        uiView.lineWidth = 6
        uiView.applyAppearance(for: uiView.traitCollection)

        if context.coordinator.lastClearSignal != clearSignal {
            uiView.clear()
            context.coordinator.lastClearSignal = clearSignal
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastClearSignal: Int = 0
    }
}

final class SimpleDrawingView: UIView {
    var strokeColor: UIColor = .black
    var lineWidth: CGFloat = 6

    private var strokes: [[CGPoint]] = []
    private var currentStroke: [CGPoint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        contentMode = .redraw
        applyAppearance(for: traitCollection)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = false
        contentMode = .redraw
        applyAppearance(for: traitCollection)
    }

    func applyAppearance(for traits: UITraitCollection) {
        if traits.userInterfaceStyle == .dark {
            backgroundColor = .black
            strokeColor = .white
        } else {
            backgroundColor = .white
            strokeColor = .black
        }
        isOpaque = true
        setNeedsDisplay()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyAppearance(for: traitCollection)
    }

    func clear() {
        strokes.removeAll()
        currentStroke.removeAll()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setStrokeColor(strokeColor.cgColor)
        context.setFillColor(strokeColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes {
            drawStroke(stroke, in: context)
        }

        drawStroke(currentStroke, in: context)
    }

    private func drawStroke(_ stroke: [CGPoint], in context: CGContext) {
        guard let first = stroke.first else { return }

        if stroke.count == 1 {
            context.fillEllipse(in: CGRect(
                x: first.x - lineWidth / 2,
                y: first.y - lineWidth / 2,
                width: lineWidth,
                height: lineWidth
            ))
            return
        }

        context.beginPath()
        context.move(to: first)

        for point in stroke.dropFirst() {
            context.addLine(to: point)
        }

        context.strokePath()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        currentStroke = [point]
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        let touchesToUse = event?.coalescedTouches(for: touch) ?? [touch]
        for t in touchesToUse {
            currentStroke.append(t.location(in: self))
        }

        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !currentStroke.isEmpty {
            strokes.append(currentStroke)
            currentStroke.removeAll()
        }
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !currentStroke.isEmpty {
            strokes.append(currentStroke)
            currentStroke.removeAll()
        }
        setNeedsDisplay()
    }
}
