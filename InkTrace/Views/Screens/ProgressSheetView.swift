//
//  ProgressSheetView.swift
//  InkTrace
//
//  進度對話框頁面
//

import SwiftUI

/// 進度對話框，顯示所有題目列表與完成狀態
struct ProgressSheetView: View {
    let currentIndex: Int
    let questions: [String]
    let completedCharacters: Set<Int>
    let failedCharacters: Set<Int>
    let onSelect: (Int) -> Void
    let onClearLocalStatus: () -> Void
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(progressText)
                        .font(.headline)
                    if let character = currentCharacter {
                        Text("目前目標：『\(character)』")
                            .foregroundColor(.secondary)
                    } else {
                        Text("題庫載入中...")
                            .foregroundColor(.secondary)
                    }
                }

                Section("題目列表") {
                    if questions.isEmpty {
                        Text("題庫載入中...")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(questions.enumerated()), id: \.0) { index, char in
                            Button {
                                onSelect(index)
                                dismiss()
                            } label: {
                                HStack {
                                    Text("\(index + 1). \(char)")
                                    Spacer()
                                    if completedCharacters.contains(index) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    } else if failedCharacters.contains(index) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundColor(.yellow)
                                    } else {
                                        Circle()
                                            .stroke(Color(UIColor.separator), lineWidth: 1)
                                            .frame(width: 14, height: 14)
                                    }
                                    if index == currentIndex {
                                        Text("目前")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.accentColor.opacity(0.15))
                                            .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onClearLocalStatus()
                        dismiss()
                    } label: {
                        Text("清除本地狀態（留在當前題目）")
                    }
                    Button(role: .destructive) {
                        onReset()
                        dismiss()
                    } label: {
                        Text("重置進度（回到第 1 字）")
                    }
                    Button("關閉") {
                        dismiss()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("目前進度")
        }
    }

    private var progressText: String {
        let total = max(questions.count, 1)
        return "進度：\(min(currentIndex + 1, total)) / \(total)"
    }

    private var currentCharacter: String? {
        guard currentIndex >= 0, currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }
}
