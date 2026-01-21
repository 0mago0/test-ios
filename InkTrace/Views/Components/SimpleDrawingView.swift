//
//  SimpleDrawingView.swift
//  InkTrace
//
//  簡易繪圖 View（無壓感模式）
//

import SwiftUI

// MARK: - Simple SwiftUI Drawing
struct SimpleDrawingView: View {
    @Binding var strokes: [[StrokePoint]]
    @Binding var currentStroke: [StrokePoint]
    @Binding var lineWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // fixed white background
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(Path(rect), with: .color(.white))

                // draw previous strokes
                for stroke in strokes {
                    var path = Path()
                    guard !stroke.isEmpty else { continue }
                    path.move(to: stroke[0].point)
                    for p in stroke.dropFirst() {
                        path.addLine(to: p.point)
                    }
                    // 固定粗細，圓頭圓角
                    let width = stroke.first?.force ?? lineWidth
                    let style = StrokeStyle(
                        lineWidth: width,
                        lineCap: .round,
                        lineJoin: .round
                    )
                    ctx.stroke(path, with: .color(.black), style: style)
                }

                // current stroke
                if !currentStroke.isEmpty {
                    var path = Path()
                    path.move(to: currentStroke[0].point)
                    for p in currentStroke.dropFirst() {
                        path.addLine(to: p.point)
                    }
                    // 固定粗細，圓頭圓角
                    let width = currentStroke.first?.force ?? lineWidth
                    let style = StrokeStyle(
                        lineWidth: width,
                        lineCap: .round,
                        lineJoin: .round
                    )
                    ctx.stroke(path, with: .color(.black), style: style)
                }
            }
            // gesture 掛在 Canvas 外面
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        // 不用壓感，只吃 slider 的 lineWidth
                        let force: CGFloat = lineWidth
                        let pt = StrokePoint(point: value.location, force: force)
                        Task { @MainActor in
                            currentStroke.append(pt)
                        }
                    }
                    .onEnded { _ in
                        Task { @MainActor in
                            if !currentStroke.isEmpty {
                                strokes.append(currentStroke)
                                currentStroke = []
                            }
                        }
                    }
            )
        }
    }
}
