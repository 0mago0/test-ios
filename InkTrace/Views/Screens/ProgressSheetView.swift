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
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (Int) -> Void
    let onReset: () -> Void
    let onRefresh: () -> Void
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

                if let errorMessage {
                    Section("GitHub 狀態") {
                        Text(errorMessage)
                            .foregroundColor(.red)
                        Button("重新整理") {
                            onRefresh()
                        }
                    }
                } else if isLoading {
                    Section("GitHub 狀態") {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("重新整理") {
                        onRefresh()
                    }
                }
            }
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
