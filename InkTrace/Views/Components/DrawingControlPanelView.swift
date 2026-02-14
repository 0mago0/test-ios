//
//  DrawingControlPanelView.swift
//  InkTrace
//

import SwiftUI

struct DrawingControlPanelView: View {
    @Binding var brushWidth: CGFloat
    @Binding var canvasScalePercent: Int
    @Binding var usePencilKit: Bool
    let hasActiveUploads: Bool
    let onUndo: () -> Void
    let onClear: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "scribble")
                    .foregroundColor(.secondary)
                Slider(value: $brushWidth, in: 1...20, step: 1)
                Text("\(Int(brushWidth))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 25)
            }
            .padding(10)
            .background(Color(UIColor.systemGroupedBackground))
            .cornerRadius(12)

            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    Button(action: { canvasScalePercent = max(50, canvasScalePercent - 10) }) {
                        Image(systemName: "minus")
                            .frame(width: 32, height: 32)
                    }
                    Text("\(canvasScalePercent)%")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 40)
                    Button(action: { canvasScalePercent = min(100, canvasScalePercent + 10) }) {
                        Image(systemName: "plus")
                            .frame(width: 32, height: 32)
                    }
                }
                .background(Color(UIColor.systemGroupedBackground))
                .cornerRadius(12)
                .foregroundColor(.primary)

                Picker("Mode", selection: $usePencilKit) {
                    Text("有壓感").tag(true)
                    Text("無壓感").tag(false)
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 12) {
                Button(action: onUndo) {
                    HStack {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .foregroundColor(.orange)
                    .cornerRadius(16)
                }

                Button(action: onClear) {
                    HStack {
                        Image(systemName: "trash")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(16)
                }

                Button(action: onSubmit) {
                    HStack {
                        if hasActiveUploads {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
            }
        }
        .padding()
        .frame(width: 300)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.1), radius: 10, y: 5)
        .padding(.bottom, 8)
    }
}
