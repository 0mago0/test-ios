//
//  PromptCarouselView.swift
//  InkTrace
//

import SwiftUI

struct PromptCarouselView: View {
    let questionBank: [String]
    let currentIndex: Int
    @Binding var visualIndex: Double
    @Binding var dragOffset: CGFloat
    let completedCharacters: Set<Int>
    let failedCharacters: Set<Int>
    let onJumpToQuestion: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            let baseItemWidth: CGFloat = 40
            let centerIndex = Int(round(visualIndex))
            let range = 50
            let minIndex = max(0, centerIndex - range)
            let maxIndex = min(questionBank.count - 1, centerIndex + range)
            let visibleIndices: [Int] = minIndex <= maxIndex ? Array(minIndex...maxIndex) : []

            ZStack {
                ForEach(visibleIndices, id: \.self) { index in
                    carouselItemView(
                        index: index,
                        centerX: center,
                        centerY: geo.size.height / 2,
                        baseItemWidth: baseItemWidth
                    )
                }
            }
        }
        .frame(height: 100)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    guard !questionBank.isEmpty else {
                        dragOffset = 0
                        return
                    }

                    let baseItemWidth: CGFloat = 40
                    let currentVisualPos = visualIndex - (value.translation.width / baseItemWidth)
                    let predictedPos = currentVisualPos - (value.velocity.width * 0.1 / baseItemWidth)

                    var targetIndex = Int(round(predictedPos))
                    targetIndex = max(0, min(targetIndex, questionBank.count - 1))

                    let maxJump = 15
                    let currentIndexInt = Int(round(currentVisualPos))
                    let jumpDist = targetIndex - currentIndexInt
                    if abs(jumpDist) > maxJump {
                        targetIndex = currentIndexInt + (jumpDist > 0 ? maxJump : -maxJump)
                    }

                    let distanceToTravel = abs(Double(targetIndex) - currentVisualPos)
                    let response = min(0.8, max(0.4, 0.3 + (distanceToTravel * 0.02)))

                    withAnimation(.spring(response: response, dampingFraction: 1.0)) {
                        visualIndex = Double(targetIndex)
                        dragOffset = 0
                    }

                    if targetIndex != currentIndex {
                        onJumpToQuestion(targetIndex)
                    }
                }
        )
    }

    private func carouselItemView(index: Int, centerX: CGFloat, centerY: CGFloat, baseItemWidth: CGFloat) -> some View {
        let effectiveVisualIndex = CGFloat(visualIndex) - (dragOffset / baseItemWidth)
        let offsetFromVisualCenter = CGFloat(index) - effectiveVisualIndex
        let logicalOffset = offsetFromVisualCenter * baseItemWidth
        let sign: CGFloat = logicalOffset > 0 ? 1 : -1
        let maxShift: CGFloat = 60
        let decay: CGFloat = 60
        let shift = sign * maxShift * (1 - exp(-abs(logicalOffset) / decay))
        let visualPos = logicalOffset + shift
        let dist = abs(visualPos)
        let scale = max(0.4, 1.0 - (dist / 220))
        let opacity = max(0.2, 1.0 - (dist / 180))

        let color: Color = failedCharacters.contains(index)
            ? .yellow
            : (completedCharacters.contains(index) ? .green : .white)

        return Text(questionBank[index])
            .font(.system(size: 80, weight: .bold))
            .foregroundColor(color)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(x: centerX + visualPos, y: centerY)
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    onJumpToQuestion(index)
                    visualIndex = Double(index)
                }
            }
    }
}
