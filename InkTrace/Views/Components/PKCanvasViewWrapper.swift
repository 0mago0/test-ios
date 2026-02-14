//
//  PKCanvasViewWrapper.swift
//  InkTrace
//
//  PencilKit 畫布包裝器
//

import SwiftUI
import PencilKit

// MARK: - PencilKit Canvas Wrapper
struct PKCanvasViewWrapper: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var lineWidth: CGFloat
    var onUndoManagerReady: ((UndoManager?) -> Void)?
    
    // Small PKCanvasView subclass to observe trait changes
    class CustomPKCanvasView: PKCanvasView {
        var onTraitChange: ((UIUserInterfaceStyle) -> Void)?
        // store pen width to reapply when enforcing black pen
        var penWidth: CGFloat = 5
        
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            // Always enforce black pen when traits change to avoid unexpected white ink
            if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
                onTraitChange?(traitCollection.userInterfaceStyle)
                self.tool = PKInkingTool(.pen, color: .black, width: penWidth)
            }
        }

        // Also enforce black pen on user interaction start (covers runtime cases where tool might flip)
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            self.tool = PKInkingTool(.pen, color: .black, width: penWidth)
        }
    }
    
    typealias UIViewType = CustomPKCanvasView

    func makeUIView(context: Context) -> CustomPKCanvasView {
        let canvas = CustomPKCanvasView()
        // Force the canvas to use light appearance so PencilKit doesn't invert ink colors in dark mode
        if #available(iOS 13.0, *) {
            canvas.overrideUserInterfaceStyle = .light
        }
        canvas.drawing = drawing
        // Keep canvas opaque and use a fixed white background so strokes are always visible
        canvas.isOpaque = true
        canvas.backgroundColor = .white
        canvas.drawingPolicy = .anyInput
        // Use fixed black pen color
        canvas.tool = PKInkingTool(.pen, color: .black, width: lineWidth)
        canvas.penWidth = lineWidth
        // Keep observer but set fixed black when trait changes (no-op for color)
        canvas.onTraitChange = { _ in
            DispatchQueue.main.async {
                canvas.tool = PKInkingTool(.pen, color: .black, width: self.lineWidth)
            }
        }
        canvas.delegate = context.coordinator
        canvas.isScrollEnabled = false
        // Expose undoManager to parent
        DispatchQueue.main.async {
            self.onUndoManagerReady?(canvas.undoManager)
        }
        return canvas
    }
    
    func updateUIView(_ uiView: CustomPKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        // Ensure pen remains black
        uiView.tool = PKInkingTool(.pen, color: .black, width: lineWidth)
        uiView.penWidth = lineWidth
        uiView.tool = PKInkingTool(.pen, color: .black, width: uiView.penWidth)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PKCanvasViewWrapper
        init(_ parent: PKCanvasViewWrapper) { self.parent = parent }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // 使用 Task 延遲狀態更新，避免在 view update 期間修改狀態
            Task { @MainActor in
                self.parent.drawing = canvasView.drawing
            }
        }
    }
}
