//
//  UploadStatusCardView.swift
//  InkTrace
//

import SwiftUI

struct UploadStatusCardView: View {
    let uploadTasks: [UploadTask]
    let maxRows: Int
    let showTitle: Bool

    init(uploadTasks: [UploadTask], maxRows: Int = 4, showTitle: Bool = true) {
        self.uploadTasks = uploadTasks
        self.maxRows = maxRows
        self.showTitle = showTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showTitle {
                Text("上傳狀態")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if uploadTasks.isEmpty {
                Text("等待送出")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(uploadTasks.prefix(maxRows)) { task in
                    HStack(spacing: 8) {
                        if task.state == .uploading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: iconName(for: task.state))
                                .font(.caption)
                                .foregroundColor(color(for: task.state))
                        }

                        Text(statusText(for: task))
                            .font(.caption)
                            .foregroundColor(color(for: task.state))
                            .lineLimit(2)
                    }
                }
            }
        }
        .frame(width: 180, alignment: .leading)
        .padding(10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }

    private func statusText(for task: UploadTask) -> String {
        switch task.state {
        case .uploading:
            return "上傳中：\(task.character)"
        case .success:
            return "已上傳：\(task.character)"
        case .failed:
            return "失敗：\(task.character)"
        }
    }

    private func iconName(for state: UploadTaskState) -> String {
        switch state {
        case .uploading:
            return "arrow.up.circle"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }

    private func color(for state: UploadTaskState) -> Color {
        switch state {
        case .uploading:
            return .blue
        case .success:
            return .green
        case .failed:
            return .yellow
        }
    }
}
